# aaPanel — Docker

[![Build and Push](https://github.com/toquanghieu/aapanel-docker/actions/workflows/build.yml/badge.svg)](https://github.com/toquanghieu/aapanel-docker/actions/workflows/build.yml)
[![Check for Updates](https://github.com/toquanghieu/aapanel-docker/actions/workflows/check-update.yml/badge.svg)](https://github.com/toquanghieu/aapanel-docker/actions/workflows/check-update.yml)
[![Docker Pulls](https://img.shields.io/docker/pulls/hieutq/aapanel)](https://hub.docker.com/r/hieutq/aapanel)
[![Docker Image Size](https://img.shields.io/docker/image-size/hieutq/aapanel/latest)](https://hub.docker.com/r/hieutq/aapanel)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)

A clean, production-minded Docker packaging of [**aaPanel**](https://www.aapanel.com/) — the
free, open web hosting control panel for Linux. One container, one volume, no
privileged mode, multi-architecture, and **rebuilt automatically every day** to
track the latest official aaPanel release.

> This is an **unofficial** community image. aaPanel itself is developed by its
> respective owners; this repository only packages it for Docker.

## Why this image

- 🧱 **Panel-only, lightweight** — ships the aaPanel core only. Install Nginx,
  Apache, MySQL, PHP, Redis, FTP and the rest **from the panel UI**, on demand —
  so the base image stays small and your stack stays exactly what you choose.
- 💾 **Single volume** — all state lives under one `/www` volume. Easy to back
  up, move, or snapshot.
- 🔓 **No `privileged: true`** — runs as an ordinary container with a plain
  process model (no systemd-in-Docker gymnastics, no host cgroup mount).
- 🏗️ **Multi-arch** — native `linux/amd64` and `linux/arm64` images behind a
  single tag.
- 🔄 **Auto-updated daily** — a scheduled pipeline checks the official aaPanel
  version API every day, and rebuilds + republishes when a new stable release
  ships. Image tags track the upstream version (e.g. `8.0.3`).
- 🔐 **Secure by default** — generates a random username, password, and secured
  entry path on first run, and prints them to the container logs.

## Supported Tags

| Tag | Description |
|---|---|
| `latest` | Most recent stable aaPanel release |
| `8.0.3`, `8.0.2`, … | Pinned to a specific aaPanel version |

Each version tag is a multi-arch manifest covering `amd64` and `arm64`.

## Quick Start

### Docker Compose (recommended)

```bash
git clone https://github.com/toquanghieu/aapanel-docker.git
cd aapanel-docker
cp .env.example .env          # optional — tweak the port or set fixed credentials
docker compose up -d
```

### Docker Run

```bash
docker run -d \
  --name aapanel \
  -p 8888:8888 \
  -p 80:80 -p 443:443 \
  -v aapanel_data:/www \
  --restart unless-stopped \
  hieutq/aapanel:latest
```

### Get your login details

On the **first** start the panel generates a random username, password, and a
secured entry path, then prints them to the logs:

```bash
docker logs aapanel
```

```
============================================================
  aaPanel is ready
------------------------------------------------------------
  URL (host):      http://<your-server-ip>:8888/a1b2c3d4
  Username:        aapanel_x7f9k2
  Password:        3f8a1c9e2b7d4a06
------------------------------------------------------------
```

Open the printed URL and log in. The credentials are also stored inside the
volume at `/www/.aapanel-credentials`, and you can always re-display panel info
from inside the container:

```bash
docker exec -it aapanel bt 14
```

To set **fixed** credentials instead, provide the environment variables below
*before* the first start.

## Environment Variables

All variables are optional. Credentials left unset are generated randomly on
first run.

| Variable | Default | Description |
|---|---|---|
| `AAPANEL_PORT` | `8888` | Panel web UI port |
| `AAPANEL_USERNAME` | random | Panel login username |
| `AAPANEL_PASSWORD` | random | Panel login password |
| `AAPANEL_ENTRY` | random | Secured entry path, e.g. `/my-secret-entry` |
| `AAPANEL_SSL` | `off` | Serve the panel over HTTPS (`on`/`off`) |

> These apply only on **first run**, when the panel is initialized. To change
> them later, use the panel UI or the `bt` CLI inside the container.

## Ports

| Port | Published by default | Description |
|---|---|---|
| `8888` | ✅ | aaPanel web UI |
| `80` | ✅ | HTTP — your websites (once a web server is installed) |
| `443` | ✅ | HTTPS |
| `888` | — | phpMyAdmin |
| `21` / `20` | — | FTP (control / data) |
| `3306` | — | MySQL |

The non-panel ports only carry traffic once you install the matching service
from the panel. Publish them by uncommenting the relevant lines in
`docker-compose.yml` (or adding `-p` flags) when you need them.

## Data Persistence

Everything aaPanel manages lives under a **single** `/www` volume:

| Path | Contents |
|---|---|
| `/www/server/panel` | Panel application, config, and database |
| `/www/wwwroot` | Your website files |
| `/www/server/data` | MySQL data (after you install MySQL) |
| `/www/server/*` | Other services you install (Nginx, PHP, …) |

Back up by snapshotting the `aapanel_data` volume. To use a host bind mount
instead, replace `aapanel_data:/www` with `./www:/www` in the compose file and
drop the trailing `volumes:` block.

## Installing a Web Stack

This image intentionally ships **only the panel**. After logging in:

1. Go to the panel's home page; it will offer a recommended stack.
2. Pick **LNMP** (Nginx) or **LAMP** (Apache) — or install components à la carte
   from **App Store → Runtime / Web Server / Database**.
3. Add your site under **Website**, then publish ports `80`/`443` (and `3306`,
   `888`, `21` as needed) on the container.

## Security

- Random username, password, and secured entry path on first boot — no
  well-known default credentials.
- Runs without `privileged: true` and without mounting the host cgroup.
- Change the panel port and entry path, and enable HTTPS + two-factor auth from
  the panel's **Settings** page for any internet-facing deployment.
- Restrict access to the panel port (`8888`) with a firewall or reverse proxy.

## Troubleshooting

**Lost your password?**

```bash
# Re-display panel info (URL, user, entry path):
docker exec -it aapanel bt 14
# Reset the password:
docker exec -it aapanel bt 5
```

**Panel not reachable?**
Confirm the daemon is up and you are hitting the **secured entry path** (the URL
suffix from the logs), not just the bare port:

```bash
docker logs aapanel
docker exec -it aapanel /etc/init.d/bt status
```

**A service you installed (Nginx/MySQL) isn't reachable from the host.**
Make sure its port is published on the container — add the `-p` flag (or compose
line) and recreate the container.

## How It Works

1. The Dockerfile installs aaPanel into a clean `ubuntu:22.04` base using the
   official installer, then packs `/www` into a compressed first-run seed.
2. On first start the entrypoint seeds the `/www` volume, sets the port and
   secured entry path, generates (or applies) credentials, and starts the panel
   daemon — no systemd required.
3. A daily GitHub Actions workflow polls the official aaPanel version API. When
   a new stable release appears, it bumps the version, tags `vX.Y.Z`, and
   triggers a multi-arch build that publishes `:X.Y.Z` and `:latest` to Docker
   Hub and refreshes this description automatically.

## Building Locally

```bash
git clone https://github.com/toquanghieu/aapanel-docker.git
cd aapanel-docker
docker build -t hieutq/aapanel:local .
docker run -d --name aapanel -p 8888:8888 -v aapanel_data:/www hieutq/aapanel:local
docker logs aapanel        # grab the generated credentials
```

## License

[MIT](./LICENSE). aaPanel is a trademark of its respective owners; this project
is not affiliated with or endorsed by aaPanel.
