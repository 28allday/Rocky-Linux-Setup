#!/usr/bin/env bash
#
# install_resolve_rocky10_from_zip_fixed_v6.sh
# DaVinci Resolve installer for Rocky/RHEL 10 (NVIDIA) installing from ZIP in ~/Downloads.
# v6: add libXt (fixes 'libXt.so.6' missing for USD.plugin), keep zlib-ng compatibility skip.
#
set -Eeuo pipefail

log() { echo -e "[resolve-install] $*"; }
die() { echo -e "\e[31mERROR:\e[0m $*" >&2; exit 1; }

# Root required
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  die "Please run as root (e.g., sudo -i && bash $0)"
fi

# Target user
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

# Repos & deps
log "Enabling EPEL and installing required packages..."
if ! rpm -q epel-release &>/dev/null; then
  dnf -y install epel-release || dnf -y install "https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm"
fi
dnf -y install unzip xcb-util-cursor mesa-libGLU libxcrypt-compat zlib libXt || die "Failed to install required packages."
dnf -y install libXrandr libXinerama libXcursor libXi fontconfig freetype || true

# Determine if we need to bypass BM's package checker (legacy 'zlib' rpm name)
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

# Post-install tweaks
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

# libcrypt link
if [[ -e /usr/lib64/libcrypt.so.1 ]]; then
  ln -sf /usr/lib64/libcrypt.so.1 "${RESOLVE_PREFIX}/libs/libcrypt.so.1" && \
    log "Linked /usr/lib64/libcrypt.so.1 into ${RESOLVE_PREFIX}/libs"
else
  log "WARNING: /usr/lib64/libcrypt.so.1 not found. libxcrypt-compat may not have installed correctly."
fi

# Logs + user dirs
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

# Sanity
if ! ldconfig -p | grep -q "libGLU.so.1"; then
  die "libGLU.so.1 not found even after mesa-libGLU install."
fi
if ! ldconfig -p | grep -q "libXt.so.6"; then
  die "libXt.so.6 not found even after libXt install."
fi

log "Installation complete."
log "Launch DaVinci Resolve as the normal user (${TARGET_USER}), NOT with sudo:"
log "  ${RESOLVE_PREFIX}/bin/resolve"
