# Rocky Linux Setup

Setup scripts for getting a Rocky Linux 10 workstation ready for video editing with DaVinci Resolve.

Three scripts that should be run in order:

1. **NVIDIA_rocky.sh** — Install NVIDIA GPU drivers
2. **fonts.sh** — Install Microsoft core fonts (Arial, Times New Roman, etc.)
3. **rocky_resolve.sh** — Install DaVinci Resolve

## Requirements

- **OS**: Rocky Linux 10
- **GPU**: NVIDIA (RTX 2000-series or newer for open kernel driver)
- **DaVinci Resolve ZIP**: Downloaded from [blackmagicdesign.com](https://www.blackmagicdesign.com/products/davinciresolve) to `~/Downloads/`

## Quick Start

```bash
git clone https://github.com/28allday/Rocky-Linux-Setup.git
cd Rocky-Linux-Setup

# Step 1: Install NVIDIA drivers
sudo ./NVIDIA_rocky.sh
sudo reboot

# Step 2: Install fonts (after reboot)
sudo ./fonts.sh

# Step 3: Install DaVinci Resolve
sudo ./rocky_resolve.sh
```

## Scripts

### NVIDIA_rocky.sh — NVIDIA Driver Installation

Installs NVIDIA's open-source kernel driver via DKMS (auto-rebuilds on kernel updates).

**What it does:**

| Step | Action |
|------|--------|
| 1 | Enables CRB (CodeReady Builder) repository |
| 2 | Enables EPEL repository |
| 3 | Installs kernel headers and DKMS build tools |
| 4 | Adds NVIDIA's official RHEL10 repository |
| 5 | Installs `nvidia-driver`, `kmod-nvidia-open-dkms`, `nvidia-settings` |
| 6 | Checks Secure Boot status and advises on MOK enrollment |

**After running:** Reboot, then verify with `nvidia-smi`.

**Secure Boot:** If enabled, you'll need to enroll the DKMS signing key:
```bash
sudo mokutil --import /var/lib/dkms/mok.pub
# Set a one-time password, then confirm on the next boot screen
sudo reboot
```

### fonts.sh — Microsoft Core Fonts

Installs Microsoft TrueType core fonts (Arial, Times New Roman, Courier New, Verdana, etc.).

**What it does:**

| Step | Action |
|------|--------|
| 1 | Installs build tools (`rpm-build`, `cabextract`, `wget`) |
| 2 | Downloads the font RPM spec from SourceForge |
| 3 | Builds the font RPM locally with `rpmbuild` |
| 4 | Installs the built RPM |
| 5 | Updates the system font cache |

**Why:** DaVinci Resolve and many documents expect these fonts. Without them, text renders with wrong fonts or missing characters.

### rocky_resolve.sh — DaVinci Resolve

Installs DaVinci Resolve from the official ZIP download.

**What it does:**

| Step | Action |
|------|--------|
| 1 | Installs runtime dependencies (OpenGL, X11 libs, libxcrypt-compat) |
| 2 | Detects zlib-ng-compat and sets SKIP_PACKAGE_CHECK if needed |
| 3 | Finds and extracts the Resolve ZIP from `~/Downloads/` |
| 4 | Runs Blackmagic's installer |
| 5 | Moves conflicting GLib/Pango libraries to a backup directory |
| 6 | Symlinks libcrypt.so.1 into Resolve's lib directory |
| 7 | Creates user data directories with correct ownership |
| 8 | Verifies critical libraries are loadable |

**Rocky 10 specific fix:** Rocky 10 replaced the `zlib` package with `zlib-ng-compat`. The library (`libz.so.1`) is identical, but Resolve's installer checks for the RPM name "zlib" and fails. The script detects this and bypasses the check.

**Launch Resolve** as your normal user (not root):
```bash
/opt/resolve/bin/resolve
```

## Troubleshooting

### NVIDIA driver not loading after reboot

```bash
# Check if module is loaded
lsmod | grep nvidia

# Check for Nouveau conflicts
lsmod | grep nouveau

# Disable Nouveau if conflicting
sudo grubby --args="nouveau.modeset=0 rd.driver.blacklist=nouveau" --update-kernel=ALL
sudo reboot
```

### DaVinci Resolve crashes on launch

- Check logs: `~/.local/share/DaVinciResolve/logs/`
- Verify NVIDIA driver: `nvidia-smi`
- Verify libraries: `ldconfig -p | grep libGLU`
- Try launching from terminal for error output: `/opt/resolve/bin/resolve`

### Font RPM build fails

- Check you have internet access (fonts are downloaded from Microsoft servers)
- Make sure `cabextract` installed: `rpm -q cabextract`
- Check rpmbuild output for specific download failures

### "zlib not found" during Resolve install

This is the zlib-ng-compat issue. The script handles it automatically, but if running the installer manually:
```bash
SKIP_PACKAGE_CHECK=1 ./DaVinci_Resolve_*.run
```

## Uninstalling

### NVIDIA Driver
```bash
sudo dnf remove nvidia-driver kmod-nvidia-open-dkms nvidia-settings
sudo reboot
```

### DaVinci Resolve
```bash
sudo rm -rf /opt/resolve
sudo rm -f /usr/share/applications/DaVinciResolve.desktop
rm -rf ~/.local/share/DaVinciResolve
rm -rf ~/.config/Blackmagic\ Design
```

### Microsoft Fonts
```bash
sudo rpm -e msttcorefonts
sudo fc-cache -fv
```

## Credits

- [Rocky Linux](https://rockylinux.org/) - Enterprise Linux distribution
- [Blackmagic Design](https://www.blackmagicdesign.com/) - DaVinci Resolve
- [NVIDIA](https://www.nvidia.com/) - GPU drivers

## License

This project is provided as-is.
