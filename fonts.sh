#!/bin/bash

# Exit on any error
set -e

# 1. Ensure running as root (or via sudo)
if [[ "$(id -u)" -ne 0 ]]; then
    echo "Error: This script must be run as root (use sudo or login as root)."
    exit 1
fi

# 2. Install necessary tools if not already installed
REQUIRED_PKGS=(rpm-build cabextract wget)
# Include ttmkfdir (or mkfontscale) if available/needed for font installation
REQUIRED_PKGS+=(ttmkfdir)

echo "Installing required packages: ${REQUIRED_PKGS[*]}"
dnf install -y "${REQUIRED_PKGS[@]}" 2>/dev/null || yum install -y "${REQUIRED_PKGS[@]}"

# 3. Download the Microsoft core fonts spec file from SourceForge
SPEC_URL="http://corefonts.sourceforge.net/msttcorefonts-2.5-1.spec"
echo "Downloading spec file from $SPEC_URL"
wget -O /tmp/msttcorefonts.spec "$SPEC_URL"

# 4. Build the RPM package for Microsoft core fonts
echo "Building RPM package for Microsoft TrueType core fonts..."
rpmbuild -bb /tmp/msttcorefonts.spec

# 5. Install the generated RPM (containing the TrueType font files)
FONT_RPM="$(find ~/rpmbuild/RPMS/noarch -name 'msttcorefonts*-*.noarch.rpm' -print -quit)"
if [[ -f "$FONT_RPM" ]]; then
    echo "Installing $FONT_RPM"
    rpm -ivh "$FONT_RPM"
else
    echo "Error: Font RPM not found. Please check rpmbuild output for errors."
    exit 1
fi

# 6. Update font cache so the system recognizes new fonts
echo "Updating font cache..."
fc-cache -fv

echo "Microsoft core fonts have been installed successfully."
