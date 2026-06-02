#!/bin/bash
set -e

PANEL_DIR=/www/server/panel
SEED=/opt/aapanel/www-seed.tar.gz
MARKER=/www/.aapanel-initialized
CREDS=/www/.aapanel-credentials

# Use the panel's bundled python; fall back to system python3.
PYTHON="$PANEL_DIR/pyenv/bin/python"
[ -x "$PYTHON" ] || PYTHON="$(command -v python3 || echo python3)"

log() { echo "[entrypoint] $*"; }

rand() { head -c 64 /dev/urandom | md5sum | cut -c1-"${1:-12}"; }

# --- 1. Seed /www on first run (empty volume) ---
if [ ! -d "$PANEL_DIR" ]; then
    log "No panel found in /www - seeding from image defaults..."
    mkdir -p /www
    tar xzpf "$SEED" -C /
fi

# --- 2. First-run initialization (runs once, gated by the marker file) ---
PRINT_CREDS=0
if [ ! -f "$MARKER" ]; then
    log "First run - initializing panel configuration..."

    # Panel port
    PORT="${AAPANEL_PORT:-8888}"
    echo "$PORT" > "$PANEL_DIR/data/port.pl"
    log "Panel port set to $PORT"

    # Secured entry path (the random URL suffix required to reach the panel)
    ENTRY="${AAPANEL_ENTRY:-/$(rand 8)}"
    echo "$ENTRY" > "$PANEL_DIR/data/admin_path.pl"

    # SSL on/off (off by default; users can enable it inside the panel)
    if [ "${AAPANEL_SSL:-off}" = "on" ]; then
        : > "$PANEL_DIR/data/ssl.pl"
    else
        rm -f "$PANEL_DIR/data/ssl.pl"
    fi

    # Credentials: use env vars if provided, otherwise generate strong randoms
    USERNAME="${AAPANEL_USERNAME:-aapanel_$(rand 6)}"
    PASSWORD="${AAPANEL_PASSWORD:-$(rand 16)}"

    cd "$PANEL_DIR"
    # Set the password through the panel's own tool (handles hashing).
    "$PYTHON" tools.py panel "$PASSWORD" >/dev/null 2>&1 || true
    # Set the username directly in the panel's sqlite DB.
    "$PYTHON" - "$USERNAME" <<'PYEOF' || true
import sys, os, sqlite3
username = sys.argv[1]
db = "/www/server/panel/data/default.db"
if os.path.exists(db):
    conn = sqlite3.connect(db)
    conn.execute("UPDATE users SET username=? WHERE id=1", (username,))
    conn.commit()
    conn.close()
PYEOF

    # Persist the credentials so they can be retrieved later from the volume.
    umask 077
    cat > "$CREDS" <<EOF
username: $USERNAME
password: $PASSWORD
entry:    $ENTRY
port:     $PORT
EOF

    touch "$MARKER"
    PRINT_CREDS=1
fi

# --- 3. Start supporting services and the panel daemon ---
log "Starting cron..."
( cron || crond || service cron start ) 2>/dev/null || true

log "Starting aaPanel daemon..."
/etc/init.d/bt start || true

# --- 4. Print login info on first run ---
if [ "$PRINT_CREDS" = "1" ]; then
    PORT="$(cat "$PANEL_DIR/data/port.pl" 2>/dev/null || echo 8888)"
    ENTRY="$(cat "$PANEL_DIR/data/admin_path.pl" 2>/dev/null || echo /)"
    IP="$(hostname -i 2>/dev/null | awk '{print $1}')"
    cat <<EOF

============================================================
  aaPanel is ready
------------------------------------------------------------
  URL (container): http://${IP}:${PORT}${ENTRY}
  URL (host):      http://<your-server-ip>:${PORT}${ENTRY}
  Username:        $(awk '/^username/{print $2}' "$CREDS")
  Password:        $(awk '/^password/{print $2}' "$CREDS")
------------------------------------------------------------
  Credentials are also saved to /www/.aapanel-credentials
  Inside the container, run 'bt 14' to view panel info again.
============================================================

EOF
fi

# --- 5. Keep PID 1 alive and forward shutdown to the panel ---
term() {
    log "Received stop signal - stopping aaPanel..."
    /etc/init.d/bt stop || true
    exit 0
}
trap term SIGTERM SIGINT

mkdir -p "$PANEL_DIR/logs"
touch "$PANEL_DIR/logs/error.log"

log "aaPanel is running. Tailing panel error log (Ctrl-C / SIGTERM to stop)."
tail -F "$PANEL_DIR/logs/error.log" &
wait $!
