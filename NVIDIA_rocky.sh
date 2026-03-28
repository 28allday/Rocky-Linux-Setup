#!/usr/bin/env bash
# NVIDIA open-kernel driver on Rocky Linux 10 (RTX 2000-series+)
set -euo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

need_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Please run as root: sudo $0"; exit 1
  fi
}

log() { printf "\n==> %s\n" "$*"; }

need_root

# Robust arch detection (avoid `uname -i` which can be "unknown")
arch_m=$(uname -m)
case "$arch_m" in
  x86_64) archdir="x86_64" ;;
  aarch64|arm64) archdir="sbsa" ;;
  *) echo "Unsupported arch: $arch_m"; exit 1 ;;
esac

log "Ensuring DNF plugins and enabling CRB…"
dnf -y install dnf-plugins-core
# CRB name is 'crb' on Rocky; fall back to helper if present
dnf config-manager --set-enabled crb || /usr/bin/crb enable || true

log "Enabling EPEL…"
dnf -y install epel-release || \
  dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm

log "Installing kernel build prerequisites for the running kernel…"
dnf -y install \
  "kernel-devel-$(uname -r)" \
  "kernel-headers-$(uname -r)" \
  dkms make gcc elfutils-libelf-devel libglvnd-devel pciutils pkgconf mokutil

log "Adding NVIDIA's official RHEL10 repo (for Rocky 10)…"
repo_url="https://developer.download.nvidia.com/compute/cuda/repos/rhel10/${archdir}/cuda-rhel10.repo"
dnf config-manager --add-repo "${repo_url}"
dnf clean expire-cache

log "Installing NVIDIA open kernel driver (display + compute)…"
dnf -y install nvidia-driver kmod-nvidia-open-dkms nvidia-settings
# Optional guardrails (OK if missing)
dnf -y install dnf-plugin-nvidia || true

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