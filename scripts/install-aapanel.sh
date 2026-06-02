#!/bin/bash
# Build-time installer for aaPanel.
#
# Runs the official aaPanel install script inside the image, then packs the
# resulting /www tree into a compressed seed tarball.
#
# Why the seed tarball: at runtime we mount a single volume at /www. An empty
# volume mounted over /www would hide the baked-in install, so the entrypoint
# extracts this seed on first run (when /www has no panel yet). Shipping only
# the tarball (and removing /www from the image) keeps a single, compressed
# copy of the panel instead of two.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "==> Installing base dependencies..."
apt-get update
apt-get install -y --no-install-recommends \
    curl wget ca-certificates \
    procps cron \
    tar gzip xz-utils \
    net-tools iproute2 \
    locales tzdata
update-ca-certificates || true

echo "==> Downloading aaPanel installer..."
INSTALL_URL="https://www.aapanel.com/script/install_panel_en.sh"
cd /tmp
curl -ksSO "$INSTALL_URL"

echo "==> Installing aaPanel (panel-only)..."
# The installer prompts to confirm installing into /www; answer 'y'. It lays
# down a self-contained python env under /www/server/panel and an init script
# at /etc/init.d/bt. No web stack (Nginx/MySQL/PHP) is installed here - users
# add those from the panel UI on demand, keeping this image small.
echo "y" | bash install_panel_en.sh || true

# Sanity check: the panel must have been laid down.
if [ ! -d /www/server/panel ]; then
    echo "ERROR: aaPanel install did not create /www/server/panel" >&2
    exit 1
fi

echo "==> Stopping panel daemon started by the installer..."
/etc/init.d/bt stop || true

echo "==> Recording installed version..."
mkdir -p /opt/aapanel
# Best-effort: read the version string the panel reports about itself.
INSTALLED=$(grep -rohE "version[[:space:]]*=[[:space:]]*['\"][0-9][0-9.]+" \
    /www/server/panel/class/common.py 2>/dev/null \
    | grep -oE "[0-9][0-9.]+" | head -1 || true)
echo "${INSTALLED:-$AAPANEL_VERSION}" > /opt/aapanel/VERSION
echo "==> Installed aaPanel version: $(cat /opt/aapanel/VERSION)"

echo "==> Hardening: removing the build toolchain (not needed at runtime)..."
# aaPanel pulls in build-essential (gcc/g++/make/libc6-dev) during install, and
# libc6-dev drags in linux-libc-dev whose kernel-header CVEs have no fix and are
# not exploitable inside a container. aaPanel installs runtime software from
# precompiled packages, so this toolchain is build-time-only. Purging it clears
# those CVEs and trims a few hundred MB from the image.
apt-get update
apt-get upgrade -y
apt-get purge -y \
    build-essential gcc g++ cpp make dpkg-dev \
    libc6-dev linux-libc-dev 2>/dev/null || true
apt-get autoremove --purge -y

echo "==> Cleaning up caches, logs and temp files..."
rm -f /tmp/install_panel_en.sh
apt-get clean
rm -rf /var/lib/apt/lists/* /var/tmp/* || true
rm -rf /www/server/panel/logs/* /www/server/panel/temp/* 2>/dev/null || true
# Drop any pre-generated SSL/session state so it is regenerated per deployment.
rm -f /www/server/panel/data/ssl.pl 2>/dev/null || true

echo "==> Stopping any remaining panel processes before packaging..."
/etc/init.d/bt stop || true
pkill -9 -f 'BT-Panel|BT-Tasks|/www/server/panel' 2>/dev/null || true
sleep 2

echo "==> Packaging /www into a first-run seed tarball..."
# tar exits 1 with "file changed as we read it" if a daemon touches /www
# mid-archive. For our freshly-installed tree that warning is harmless, so we
# tolerate exit code 1 but still fail on exit code >= 2 (real tar errors).
set +e
tar czpf /opt/aapanel/www-seed.tar.gz --warning=no-file-changed -C / www
rc=$?
set -e
if [ "$rc" -gt 1 ]; then
    echo "ERROR: tar failed with exit code $rc" >&2
    exit "$rc"
fi

rm -rf /www
echo "==> Done. Seed size: $(du -h /opt/aapanel/www-seed.tar.gz | cut -f1)"
