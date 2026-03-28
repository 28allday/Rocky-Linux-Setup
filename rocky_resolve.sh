#!/usr/bin/env bash
# ==============================================================================
# DaVinci Resolve Installer for Rocky Linux 10
#
# Installs DaVinci Resolve on Rocky Linux 10 with NVIDIA GPU support.
# Handles the specific compatibility issues on RHEL-based systems:
#   - zlib-ng-compat vs legacy zlib (Rocky 10 uses zlib-ng which confuses
#     Resolve's package checker — we bypass it with SKIP_PACKAGE_CHECK)
#   - GLib/Pango library conflicts (same issue as Arch/Mint — bundled
#     versions conflict with system libraries)
#   - libcrypt.so.1 compatibility symlink
#   - libXt for USD plugin support
#
# Prerequisites:
#   - Rocky Linux 10 with NVIDIA drivers installed (run NVIDIA_rocky.sh first)
#   - DaVinci Resolve Linux ZIP downloaded to ~/Downloads/
#
# Usage:
#   sudo ./rocky_resolve.sh
# ==============================================================================

set -Eeuo pipefail
# -E: ERR traps inherited by functions/subshells
# -e: Exit on error
# -u: Error on unset variables
# -o pipefail: Pipe fails if any command in it fails

log() { echo -e "[resolve-install] $*"; }
die() { echo -e "\e[31mERROR:\e[0m $*" >&2; exit 1; }

# Root is required for installing packages and writing to /opt/resolve.
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  die "Please run as root (e.g., sudo -i && bash $0)"
fi

# Figure out the real user — when running with sudo, we need to find their
# home directory to locate the Resolve ZIP in ~/Downloads/. Falls back to
# the first user in /home/ if SUDO_USER isn't set (e.g. running as root directly).
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  TARGET_USER="$SUDO_USER"
else
  TARGET_USER="$(ls -1 /home 2>/dev/null | head -n 1 || true)"
  [[ -n "$TARGET_USER" ]] || TARGET_USER="root"
fi
USER_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6 || echo "/root")"
DOWNLOADS_DIR="${USER_HOME}/Downloads"
RESOLVE_PREFIX="/opt/resolve"

log "Target user: ${TARGET_USER}"
log "Downloads folder: ${DOWNLOADS_DIR}"

# Install runtime dependencies that Resolve needs:
#   xcb-util-cursor:   X11 cursor handling
#   mesa-libGLU:       OpenGL Utility Library (3D rendering)
#   libxcrypt-compat:  Legacy libcrypt.so.1 (Rocky 10 uses libxcrypt v2)
#   zlib:              Compression library
#   libXt:             X Toolkit library (fixes missing libXt.so.6 for USD plugin)
#   libXrandr/etc:     X11 extensions for display management
log "Enabling EPEL and installing required packages..."
if ! rpm -q epel-release &>/dev/null; then
  dnf -y install epel-release || dnf -y install "https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm"
fi
dnf -y install unzip xcb-util-cursor mesa-libGLU libxcrypt-compat zlib libXt || die "Failed to install required packages."
dnf -y install libXrandr libXinerama libXcursor libXi fontconfig freetype || true

# Rocky Linux 10 uses zlib-ng-compat instead of the legacy 'zlib' package.
# zlib-ng is a drop-in replacement that provides the same libz.so.1 library,
# but Resolve's built-in package checker looks for an RPM literally named
# "zlib" and fails when it doesn't find it. Setting SKIP_PACKAGE_CHECK=1
# tells the installer to skip this check.
NEED_SKIP=0
if ! rpm -q zlib &>/dev/null; then
  if rpm -q zlib-ng-compat &>/dev/null && [[ -e /usr/lib64/libz.so.1 || -e /lib64/libz.so.1 ]]; then
    log "Detected zlib-ng-compat provides libz.so.1 but 'zlib' RPM is absent. Will use SKIP_PACKAGE_CHECK=1."
    NEED_SKIP=1
  fi
fi

# Find newest ZIP
log "Looking for Resolve ZIP in ${DOWNLOADS_DIR} ..."
shopt -s nullglob
zip_candidates=( "${DOWNLOADS_DIR}"/DaVinci_Resolve_*.zip )
shopt -u nullglob
(( ${#zip_candidates[@]} )) || die "No DaVinci_Resolve_*.zip found in ${DOWNLOADS_DIR}."
ZIP_FILE="${zip_candidates[0]}"
for z in "${zip_candidates[@]}"; do [[ "$z" -nt "$ZIP_FILE" ]] && ZIP_FILE="$z"; done
log "Using ZIP: ${ZIP_FILE}"

# Extract
WORK_DIR="${DOWNLOADS_DIR}/.resolve_zip_extract.$$"
mkdir -p "$WORK_DIR"
log "Extracting ZIP into: ${WORK_DIR}"
unzip -q -o "$ZIP_FILE" -d "$WORK_DIR" || die "Failed to extract ZIP."

# Locate .run
shopt -s globstar nullglob
run_candidates=( "$WORK_DIR"/**/DaVinci_Resolve*Linux*.run "$WORK_DIR"/DaVinci_Resolve_*_Linux.run )
shopt -u nullglob
(( ${#run_candidates[@]} )) || die "Could not find a DaVinci Resolve .run installer inside the ZIP."
INSTALLER="${run_candidates[0]}"
for f in "${run_candidates[@]}"; do [[ "$f" -nt "$INSTALLER" ]] && INSTALLER="$f"; done
log "Found installer: ${INSTALLER}"

# Copy to /tmp and execute
TMPDIR="$(mktemp -d -p /tmp resolve-installer.XXXXXX)"
trap 'rm -rf "$TMPDIR" "$WORK_DIR"' EXIT
cp -f "$INSTALLER" "$TMPDIR/resolve.run"
chmod +x "$TMPDIR/resolve.run"
ftype="$(file -b "$TMPDIR/resolve.run" || true)"
log "Installer file type: ${ftype}"
log "Running Blackmagic installer... (GUI may open)"

if echo "$ftype" | grep -qiE 'shell script|text'; then
  if (( NEED_SKIP )); then
    SKIP_PACKAGE_CHECK=1 bash "$TMPDIR/resolve.run" || die "Blackmagic installer failed."
  else
    bash "$TMPDIR/resolve.run" || die "Blackmagic installer failed."
  fi
else
  if (( NEED_SKIP )); then
    SKIP_PACKAGE_CHECK=1 "$TMPDIR/resolve.run" || die "Blackmagic installer failed."
  else
    "$TMPDIR/resolve.run" || die "Blackmagic installer failed."
  fi
fi

# Post-install library conflict resolution.
# Resolve bundles old versions of GLib and Pango that conflict with the
# system versions on Rocky 10. Moving them to a backup directory forces
# Resolve to use the system libraries instead, which are newer and
# compatible (stable C ABI). This fixes crashes and "symbol not found" errors.
if [[ -d "${RESOLVE_PREFIX}/libs" ]]; then
  log "Applying GLib/Pango conflict workaround in ${RESOLVE_PREFIX}/libs ..."
  pushd "${RESOLVE_PREFIX}/libs" >/dev/null
  mkdir -p backup_conflicts
  for patt in \
    "libglib-2.0.so*" "libgobject-2.0.so*" "libgio-2.0.so*" "libgmodule-2.0.so*" "libgthread-2.0.so*" \
    "libpango-1.0.so*" "libpangocairo-1.0.so*" "libpangoft2-1.0.so*"
  do
    for lib in $patt; do
      [[ -e "$lib" ]] && mv -f "$lib" backup_conflicts/ || true
    done
  done
  popd >/dev/null
else
  log "WARNING: ${RESOLVE_PREFIX}/libs not found. Was the install path different?"
fi

# Create a symlink for libcrypt.so.1 inside Resolve's lib directory.
# Rocky 10 provides this via libxcrypt-compat, but Resolve may not find
# it in the system path due to its custom RPATH settings.
if [[ -e /usr/lib64/libcrypt.so.1 ]]; then
  ln -sf /usr/lib64/libcrypt.so.1 "${RESOLVE_PREFIX}/libs/libcrypt.so.1" && \
    log "Linked /usr/lib64/libcrypt.so.1 into ${RESOLVE_PREFIX}/libs"
else
  log "WARNING: /usr/lib64/libcrypt.so.1 not found. libxcrypt-compat may not have installed correctly."
fi

# Create Resolve's data directories with correct ownership. These store
# projects, preferences, cache, and logs. They must be owned by the real
# user (not root) since Resolve should be launched as a normal user.
install -d -m 1777 "${RESOLVE_PREFIX}/logs"
for d in \
  "${USER_HOME}/.local/share/DaVinciResolve" \
  "${USER_HOME}/.config/Blackmagic Design" \
  "${USER_HOME}/.BlackmagicDesign" \
  "${USER_HOME}/.cache/BlackmagicDesign"
do
  mkdir -p "$d" || true
  chown -R "${TARGET_USER}:${TARGET_USER}" "$d" || true
done

# Final sanity checks — verify that critical libraries are findable by the
# dynamic linker. If these fail, Resolve will crash on launch.
if ! ldconfig -p | grep -q "libGLU.so.1"; then
  die "libGLU.so.1 not found even after mesa-libGLU install."
fi
if ! ldconfig -p | grep -q "libXt.so.6"; then
  die "libXt.so.6 not found even after libXt install."
fi

log "Installation complete."
log "Launch DaVinci Resolve as the normal user (${TARGET_USER}), NOT with sudo:"
log "  ${RESOLVE_PREFIX}/bin/resolve"
