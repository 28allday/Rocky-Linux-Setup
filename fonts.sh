#!/bin/bash
# ==============================================================================
# Microsoft Core Fonts Installer for Rocky Linux
#
# Installs Microsoft's TrueType core fonts (Arial, Times New Roman, Courier
# New, Verdana, etc.) on Rocky Linux. These fonts are needed for proper
# document rendering, web compatibility, and applications like DaVinci Resolve
# that expect standard Windows fonts to be available.
#
# The fonts aren't distributed as a package — instead, this script downloads
# an RPM spec file from SourceForge, builds the font RPM locally using
# rpmbuild, then installs it. This is the standard approach on RHEL-based
# systems since Microsoft's license doesn't allow redistribution as a
# pre-built package.
#
# Usage:
#   sudo ./fonts.sh
# ==============================================================================

set -e  # Exit on any error

# Root is required for installing packages and system fonts.
if [[ "$(id -u)" -ne 0 ]]; then
    echo "Error: This script must be run as root (use sudo or login as root)."
    exit 1
fi

# Install the tools needed to download and build the font RPM:
#   rpm-build:   RPM package building tools (rpmbuild command)
#   cabextract:  Extracts Microsoft .cab archives (fonts are distributed in .cab files)
#   wget:        Downloads the spec file and font archives from the internet
#   ttmkfdir:    Creates font directory indexes for X11 font paths
REQUIRED_PKGS=(rpm-build cabextract wget)
REQUIRED_PKGS+=(ttmkfdir)

echo "Installing required packages: ${REQUIRED_PKGS[*]}"
dnf install -y "${REQUIRED_PKGS[@]}" 2>/dev/null || yum install -y "${REQUIRED_PKGS[@]}"

# Download the RPM spec file that defines how to build the font package.
# This spec file tells rpmbuild where to download each font's .cab archive
# from Microsoft's servers and how to extract and install them.
SPEC_URL="http://corefonts.sourceforge.net/msttcorefonts-2.5-1.spec"
echo "Downloading spec file from $SPEC_URL"
wget -O /tmp/msttcorefonts.spec "$SPEC_URL"

# Build the RPM. rpmbuild downloads the font archives from Microsoft,
# extracts the .ttf files, and packages them into an installable RPM.
# The built RPM lands in ~/rpmbuild/RPMS/noarch/.
echo "Building RPM package for Microsoft TrueType core fonts..."
rpmbuild -bb /tmp/msttcorefonts.spec

# Find and install the built RPM.
FONT_RPM="$(find ~/rpmbuild/RPMS/noarch -name 'msttcorefonts*-*.noarch.rpm' -print -quit)"
if [[ -f "$FONT_RPM" ]]; then
    echo "Installing $FONT_RPM"
    rpm -ivh "$FONT_RPM"
else
    echo "Error: Font RPM not found. Please check rpmbuild output for errors."
    exit 1
fi

# Rebuild the font cache so applications can discover the newly installed fonts.
# fc-cache scans font directories and builds indexes for fast font lookup.
echo "Updating font cache..."
fc-cache -fv

echo "Microsoft core fonts have been installed successfully."
