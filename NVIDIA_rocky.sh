#!/usr/bin/env bash
# ==============================================================================
# NVIDIA Open Kernel Driver Installer for Rocky Linux 10
#
# Installs NVIDIA's open-source kernel driver on Rocky Linux 10. This driver
# supports RTX 2000-series GPUs and newer (Turing, Ampere, Ada Lovelace, etc.).
#
# What this script does:
#   1. Enables the CRB (CodeReady Builder) and EPEL repositories
#   2. Installs kernel headers and DKMS build tools
#   3. Adds NVIDIA's official RHEL10 repository
#   4. Installs nvidia-driver with the open-source kernel module (via DKMS)
#   5. Checks for Secure Boot and advises on MOK key enrollment
#
# DKMS (Dynamic Kernel Module Support) automatically recompiles the NVIDIA
# module whenever the kernel is updated, so the driver survives kernel upgrades.
#
# Prerequisites:
#   - Rocky Linux 10
#   - NVIDIA GPU (RTX 2000-series or newer for open kernel driver)
#   - Internet connection
#
# Usage:
#   sudo ./NVIDIA_rocky.sh
# ==============================================================================

set -euo pipefail
# Trap errors and show which line failed — makes debugging much easier
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

need_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Please run as root: sudo $0"; exit 1
  fi
}

log() { printf "\n==> %s\n" "$*"; }

need_root

# Detect CPU architecture to select the correct NVIDIA repo URL.
# We use uname -m instead of uname -i because -i can return "unknown"
# on some systems. x86_64 is standard desktop/server, aarch64 is ARM.
arch_m=$(uname -m)
case "$arch_m" in
  x86_64) archdir="x86_64" ;;
  aarch64|arm64) archdir="sbsa" ;;
  *) echo "Unsupported arch: $arch_m"; exit 1 ;;
esac

# Enable CRB (CodeReady Builder) — Rocky's equivalent of RHEL's optional repo.
# It provides development packages like kernel-devel that aren't in the base repo.
log "Ensuring DNF plugins and enabling CRB…"
dnf -y install dnf-plugins-core
dnf config-manager --set-enabled crb || /usr/bin/crb enable || true

# Enable EPEL (Extra Packages for Enterprise Linux) — community-maintained
# packages that fill gaps in the RHEL/Rocky base repos. Provides DKMS and
# other tools needed for building kernel modules.
log "Enabling EPEL…"
dnf -y install epel-release || \
  dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm

# Install kernel headers and build tools. These must match the RUNNING kernel
# version exactly — DKMS uses them to compile the NVIDIA module against
# the correct kernel source. If the kernel was recently updated but not
# rebooted, this may install headers for the old kernel.
log "Installing kernel build prerequisites for the running kernel…"
dnf -y install \
  "kernel-devel-$(uname -r)" \
  "kernel-headers-$(uname -r)" \
  dkms make gcc elfutils-libelf-devel libglvnd-devel pciutils pkgconf mokutil

# Add NVIDIA's official CUDA/driver repository. Rocky 10 uses the RHEL10 repo
# since Rocky is binary-compatible with RHEL. The repo URL includes the
# architecture (x86_64 or sbsa for ARM servers).
log "Adding NVIDIA's official RHEL10 repo (for Rocky 10)…"
repo_url="https://developer.download.nvidia.com/compute/cuda/repos/rhel10/${archdir}/cuda-rhel10.repo"
dnf config-manager --add-repo "${repo_url}"
dnf clean expire-cache

# Install the NVIDIA driver stack:
#   nvidia-driver:          Userspace driver (OpenGL, Vulkan, CUDA runtime)
#   kmod-nvidia-open-dkms:  Open-source kernel module (auto-rebuilds on kernel updates)
#   nvidia-settings:        GUI tool for configuring GPU settings
#   dnf-plugin-nvidia:      Optional DNF plugin that prevents driver/kernel mismatches
log "Installing NVIDIA open kernel driver (display + compute)…"
dnf -y install nvidia-driver kmod-nvidia-open-dkms nvidia-settings
dnf -y install dnf-plugin-nvidia || true

# Check for Secure Boot. If enabled, the NVIDIA kernel module won't load
# unless its signing key (MOK — Machine Owner Key) is enrolled in the
# UEFI firmware. DKMS generates this key automatically, but the user must
# enroll it manually on the next reboot via the blue MOK management screen.
echo
if mokutil --sb-state 2>/dev/null | grep -qi enabled; then
  cat <<'SB'
⚠️  Secure Boot is ENABLED.
Before rebooting, enroll the DKMS MOK key so the module can load:
  sudo mokutil --import /var/lib/dkms/mok.pub
You’ll set a one-time password and confirm enrollment on the next boot screen.
SB
else
  echo "Secure Boot is disabled — no MOK enrollment needed."
fi

cat <<'POST'

All done. Now reboot to load the driver, then verify with:
  sudo reboot
  # after reboot:
  nvidia-smi

If you ever see Nouveau conflicts, you can disable it with:
  sudo grubby --args="nouveau.modeset=0 rd.driver.blacklist=nouveau" --update-kernel=ALL
  sudo reboot
POST