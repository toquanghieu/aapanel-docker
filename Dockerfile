FROM ubuntu:22.04

LABEL org.opencontainers.image.source="https://github.com/toquanghieu/aapanel-docker"
LABEL org.opencontainers.image.description="aaPanel in Docker - panel-only, single /www volume, no privileged mode, multi-arch (amd64/arm64), auto-updated daily from official aaPanel releases"
LABEL org.opencontainers.image.licenses="MIT"

# Version is bumped automatically by .github/workflows/check-update.yml when a
# new stable aaPanel release is detected via the official version API.
ARG AAPANEL_VERSION=8.0.3
ENV AAPANEL_VERSION=${AAPANEL_VERSION} \
    DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# Install aaPanel at build time, then pack /www into a first-run seed tarball
# (see install-aapanel.sh for why). The script runs the official installer.
COPY scripts/install-aapanel.sh /tmp/install-aapanel.sh
RUN chmod +x /tmp/install-aapanel.sh && /tmp/install-aapanel.sh && rm -f /tmp/install-aapanel.sh

COPY scripts/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 8888 = panel UI. The rest are for services the user installs from the panel
# (Nginx, MySQL, FTP, phpMyAdmin) - published on demand via compose/run.
EXPOSE 8888 80 443 888 20 21 3306

ENTRYPOINT ["/entrypoint.sh"]
