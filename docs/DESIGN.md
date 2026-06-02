# Design — aapanel-docker

Docker packaging of aaPanel with a daily auto-update pipeline, published to
Docker Hub as `hieutq/aapanel`. Modeled on the `unifi-os-server-docker` repo's
conventions (multi-arch build + daily check-update + auto-tag `vX.Y.Z` +
auto-synced Docker Hub description).

## Decisions

| Topic | Choice | Rationale |
|---|---|---|
| Version source | aaPanel API `updateLinuxEn` → `.version` (8.x stable) | Matches the "latest stable" the panel itself reports; the GitHub release scheme (7.x) drifts from it |
| Image flavor | Panel-only (no baked web stack) | Small image, fast daily rebuilds; users add Nginx/MySQL/PHP from the panel UI |
| Credentials | Random on first run, printed to `docker logs`; ENV override | Secure by default, no shared known passwords |
| Process model | Lightweight entrypoint, no systemd | No `--privileged`/cgroup host/tmpfs needed; deployable via GUIs |
| Base image | `ubuntu:22.04` | aaPanel's recommended OS |
| Persistence | Single `/www` volume, seeded from a baked tarball on first run | One thing to back up; empty-volume-over-install problem solved by the seed |

## Build & pipeline

- **Dockerfile** installs aaPanel at build time (`scripts/install-aapanel.sh`),
  then packs `/www` into `/opt/aapanel/www-seed.tar.gz`.
- **scripts/entrypoint.sh** seeds `/www` if empty, initializes port / entry path
  / credentials on first run, starts cron + the `bt` daemon, and keeps PID 1
  alive by tailing the panel log (with SIGTERM → graceful `bt stop`).
- **.github/workflows/build.yml** — native per-arch build (amd64 on
  `ubuntu-24.04`, arm64 on `ubuntu-24.04-arm`) → push `VERSION-arch` →
  `manifest` job creates `:VERSION` + `:latest`, syncs the Docker Hub
  description, and cuts a GitHub Release on tags.
- **.github/workflows/check-update.yml** — daily cron (06:00 UTC); polls the
  version API, bumps the Dockerfile `ARG`, commits, tags `vX.Y.Z`, and triggers
  the build.

## Required repository secrets

- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN`

## Validation note

The image hasn't been built on this machine (no local Docker; the build is
Linux/amd64-native). The first CI run is the real validation — in particular the
aaPanel install-in-container path and the credential-setting CLI may need a
small tweak once the first build's logs are available.
