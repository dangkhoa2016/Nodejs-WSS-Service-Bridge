#!/usr/bin/env bash
set -Eeuo pipefail
# Nodejs-WSS-Service-Bridge v1.0.0
# Linux / GitHub Codespaces SSH launcher.
#
# Usage:
#   ./ssh-via-nodejs-wss-service-bridge.sh ~/.ssh/kaggle_vscode_ed25519 kaggle-1
#   ./ssh-via-nodejs-wss-service-bridge.sh ~/.ssh/kaggle_vscode_ed25519 colab-1
#
# Optional third argument overrides local port.
SSH_KEY="${1:-}"
TUNNEL_ID="${2:-}"
LOCAL_PORT="${3:-}"
RELAY_HOST="${RELAY_HOST:-}"
INSTALL_UUID="${INSTALL_UUID:-}"
AGENT_USERNAME="${AGENT_USERNAME:-${TUNNEL_USERNAME:-}}"
TARGET_PORT="${TARGET_PORT:-2222}"
SSH_USER="${SSH_USER:-tunneluser}"
AGENT_DIR="${AGENT_DIR:-$HOME/.nodejs-wss-service-bridge-agent}"
DOWNLOAD_AGENT_URL="https://${RELAY_HOST}/${INSTALL_UUID}-tcp-agent.js"
DOWNLOAD_PACKAGE_URL="https://${RELAY_HOST}/${INSTALL_UUID}-tcp-agent-package.json"
die() {
  printf "\n[ERROR] %s\n" "$*" >&2
  exit 1
}
info() {
  printf "[INFO] %s\n" "$*"
}
ok() {
  printf "[OK] %s\n" "$*"
}
usage() {
  cat <<EOF
Usage:
  $(basename "$0") ~/.ssh/kaggle_vscode_ed25519 kaggle-1
  $(basename "$0") ~/.ssh/kaggle_vscode_ed25519 colab-1
Optional:
  $(basename "$0") ~/.ssh/kaggle_vscode_ed25519 colab-1 22010
EOF
}
[[ -n "$SSH_KEY" ]] || { usage; die "Missing SSH private-key path."; }
[[ -f "$SSH_KEY" ]] || die "SSH private key does not exist: $SSH_KEY"
[[ -n "$TUNNEL_ID" ]] || { usage; die "Missing TUNNEL_ID."; }
[[ -n "$RELAY_HOST" ]] || die "RELAY_HOST is required (for example: tunnel.example.com)."
[[ -n "$INSTALL_UUID" ]] || die "INSTALL_UUID is required."
[[ -n "$AGENT_USERNAME" ]] || die "AGENT_USERNAME or TUNNEL_USERNAME is required."
chmod 600 "$SSH_KEY" 2>/dev/null || true
if [[ -z "$LOCAL_PORT" ]]; then
  if [[ "$TUNNEL_ID" =~ ^kaggle-([0-9]+)$ ]]; then
    N="${BASH_REMATCH[1]}"
    LOCAL_PORT=$((22000 + N * 2 - 1))
  elif [[ "$TUNNEL_ID" =~ ^colab-([0-9]+)$ ]]; then
    N="${BASH_REMATCH[1]}"
    LOCAL_PORT=$((22000 + N * 2))
  else
    die "Cannot derive local port from TUNNEL_ID $TUNNEL_ID. Pass argument 3."
  fi
fi
[[ "$LOCAL_PORT" =~ ^[0-9]+$ ]] || die "Invalid local port: $LOCAL_PORT"
(( LOCAL_PORT >= 1 && LOCAL_PORT <= 65535 )) || die "Local port out of range: $LOCAL_PORT"
PID_FILE="$AGENT_DIR/agent-$LOCAL_PORT.pid"
LOG_FILE="$AGENT_DIR/agent-$LOCAL_PORT.log"
ERR_FILE="$AGENT_DIR/agent-$LOCAL_PORT.err.log"
KEYSCAN_FILE="${TMPDIR:-/tmp}/nodejs-wss-keyscan-$LOCAL_PORT.txt"
printf "\n============================================================\n"
printf " Nodejs-WSS-Service-Bridge - SSH Target (Linux/Codespaces)\n"
printf "============================================================\n"
printf " Relay      : %s\n" "$RELAY_HOST"
printf " Target ID  : %s\n" "$TUNNEL_ID"
printf " Local port : %s\n" "$LOCAL_PORT"
printf " Target port: %s\n" "$TARGET_PORT"
printf " SSH user   : %s\n" "$SSH_USER"
printf " SSH key    : %s\n" "$SSH_KEY"
printf "============================================================\n\n"
command -v curl >/dev/null 2>&1 || die "curl was not found."
command -v ssh >/dev/null 2>&1 || die "ssh was not found."
command -v ssh-keyscan >/dev/null 2>&1 || die "ssh-keyscan was not found."
command -v ssh-keygen >/dev/null 2>&1 || die "ssh-keygen was not found."
command -v npm >/dev/null 2>&1 || die "npm was not found."
NODE_EXE=""
if command -v mise >/dev/null 2>&1; then
  NODE_FROM_MISE="$(mise which node 2>/dev/null || true)"
  if [[ -n "$NODE_FROM_MISE" && -x "$NODE_FROM_MISE" ]]; then
    NODE_EXE="$NODE_FROM_MISE"
    info "Using Node resolved by mise."
  fi
fi
if [[ -z "$NODE_EXE" ]]; then
  NODE_EXE="$(command -v node || true)"
fi
[[ -n "$NODE_EXE" && -x "$NODE_EXE" ]] || die "node was not found."
ok "Node: $("$NODE_EXE" --version)"
ok "npm: $(npm --version)"
ok "SSH: $(ssh -V 2>&1)"
mkdir -p "$AGENT_DIR"
chmod 700 "$AGENT_DIR" 2>/dev/null || true
if [[ ! -s "$AGENT_DIR/tcp-agent.js" ]]; then
  info "Downloading tcp-agent.js..."
  curl -fsSL "$DOWNLOAD_AGENT_URL" -o "$AGENT_DIR/tcp-agent.js"
else
  ok "tcp-agent.js already exists."
fi
if [[ ! -s "$AGENT_DIR/package.json" ]]; then
  info "Downloading package.json..."
  curl -fsSL "$DOWNLOAD_PACKAGE_URL" -o "$AGENT_DIR/package.json"
else
  ok "package.json already exists."
fi
if [[ ! -d "$AGENT_DIR/node_modules" ]]; then
  info "Installing tcp-agent dependencies..."
  (
    cd "$AGENT_DIR"
    npm install --omit=dev
  )
else
  ok "node_modules already exists."
fi
OLD_PID=""
if [[ -s "$PID_FILE" ]]; then
  OLD_PID="$(cat "$PID_FILE" 2>/dev/null || true)"
fi
if [[ "$OLD_PID" =~ ^[0-9]+$ ]] && kill -0 "$OLD_PID" 2>/dev/null; then
  info "Stopping previous route on port $LOCAL_PORT PID $OLD_PID..."
  kill "$OLD_PID" 2>/dev/null || true
  for _ in {1..20}; do
    kill -0 "$OLD_PID" 2>/dev/null || break
    sleep 0.1
  done
  if kill -0 "$OLD_PID" 2>/dev/null; then
    kill -9 "$OLD_PID" 2>/dev/null || true
  fi
fi
rm -f "$PID_FILE"
# ---------- Detect and clean stale listener on this local port ----------
PORT_PID=""
if command -v ss >/dev/null 2>&1; then
  PORT_PID="$(
    ss -ltnp 2>/dev/null       | awk -v p=":$LOCAL_PORT" '
          index($4, p) && $4 ~ /127\.0\.0\.1:/ {
            if (match($0, /pid=[0-9]+/)) {
              s = substr($0, RSTART + 4, RLENGTH - 4)
              print s
              exit
            }
          }
        ' || true
  )"
fi
if [[ -z "$PORT_PID" ]] && command -v lsof >/dev/null 2>&1; then
  PORT_PID="$(lsof -nP -t -iTCP:"$LOCAL_PORT" -sTCP:LISTEN 2>/dev/null | head -n1 || true)"
fi
if [[ -z "$PORT_PID" ]] && command -v fuser >/dev/null 2>&1; then
  PORT_PID="$(fuser -n tcp "$LOCAL_PORT" 2>/dev/null | awk "{print \$1}" || true)"
fi
if [[ "$PORT_PID" =~ ^[0-9]+$ ]]; then
  PORT_CMD="$(ps -p "$PORT_PID" -o args= 2>/dev/null || true)"
  if [[ "$PORT_CMD" == *"tcp-agent.js"* ]]; then
    info "Stopping stale tcp-agent on port $LOCAL_PORT PID $PORT_PID..."
    kill "$PORT_PID" 2>/dev/null || true
    for _ in {1..30}; do
      kill -0 "$PORT_PID" 2>/dev/null || break
      sleep 0.1
    done
    if kill -0 "$PORT_PID" 2>/dev/null; then
      kill -9 "$PORT_PID" 2>/dev/null || true
    fi
    sleep 0.2
  else
    printf "\n[ERROR] Local port %s is already in use by PID %s.\n" "$LOCAL_PORT" "$PORT_PID" >&2
    printf "        Command: %s\n" "$PORT_CMD" >&2
    printf "        Refusing to kill a process that is not tcp-agent.js.\n" >&2
    exit 1
  fi
fi
# Final hard check before launching the new agent.
if command -v ss >/dev/null 2>&1; then
  if ss -ltn 2>/dev/null | awk -v p=":$LOCAL_PORT" 'index($4,p) && $4 ~ /127\.0\.0\.1:/ {found=1} END{exit !found}'; then
    die "Local port $LOCAL_PORT is still in use after stale-agent cleanup."
  fi
elif command -v lsof >/dev/null 2>&1; then
  if lsof -nP -iTCP:"$LOCAL_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    die "Local port $LOCAL_PORT is still in use."
  fi
fi
if [[ -z "${AGENT_PASSWORD:-}" ]]; then
  if [[ -t 0 ]]; then
    read -r -s -p "Tunnel password: " AGENT_PASSWORD
    printf "\n"
  else
    die "AGENT_PASSWORD is not set and stdin is not interactive."
  fi
fi
[[ -n "$AGENT_PASSWORD" ]] || die "Tunnel password was empty."
export TUNNEL_SERVER_URL="wss://$RELAY_HOST/tcp"
export AGENT_USERNAME
export AGENT_PASSWORD
export AGENT_BIND_HOST="127.0.0.1"
export AGENT_ROUTES="$LOCAL_PORT=$TUNNEL_ID:$TARGET_PORT"
printf "\n"
info "Starting tcp-agent..."
printf "       Route    : %s\n" "$AGENT_ROUTES"
printf "       Log      : %s\n" "$LOG_FILE"
printf "       Error log: %s\n" "$ERR_FILE"
rm -f "$LOG_FILE" "$ERR_FILE"
# Keep tcp-agent as a direct child of this launcher for the lifetime of the
# interactive SSH session. This is more reliable inside Codespaces than
# orphaning it from a short-lived subshell with nohup.
ORIGINAL_DIR="$PWD"
cd "$AGENT_DIR"
"$NODE_EXE" tcp-agent.js >"$LOG_FILE" 2>"$ERR_FILE" < /dev/null &
AGENT_PID=$!
cd "$ORIGINAL_DIR"
printf "%s\n" "$AGENT_PID" > "$PID_FILE"
unset AGENT_PASSWORD
cleanup() {
  RC=$?
  if [[ -n "${AGENT_PID:-}" ]] && kill -0 "$AGENT_PID" 2>/dev/null; then
    info "Stopping tcp-agent PID $AGENT_PID..."
    kill "$AGENT_PID" 2>/dev/null || true
    for _ in {1..20}; do
      kill -0 "$AGENT_PID" 2>/dev/null || break
      sleep 0.1
    done
    if kill -0 "$AGENT_PID" 2>/dev/null; then
      kill -9 "$AGENT_PID" 2>/dev/null || true
    fi
  fi
  rm -f "$PID_FILE" "$KEYSCAN_FILE"
  exit "$RC"
}
trap cleanup EXIT INT TERM HUP
info "Waiting for 127.0.0.1:$LOCAL_PORT..."
LISTENING=0
for _ in {1..40}; do
  if ! kill -0 "$AGENT_PID" 2>/dev/null; then
    printf "\n==================== %s ====================\n" "$LOG_FILE"
    [[ -f "$LOG_FILE" ]] && cat "$LOG_FILE"
    printf "\n==================== %s ====================\n" "$ERR_FILE"
    [[ -f "$ERR_FILE" ]] && cat "$ERR_FILE"
    die "tcp-agent exited before opening local port $LOCAL_PORT."
  fi
  if command -v ss >/dev/null 2>&1; then
    if ss -ltn 2>/dev/null | awk -v p=":$LOCAL_PORT" 'index($4,p) && $4 ~ /127\.0\.0\.1:/ {found=1} END{exit !found}'; then
      LISTENING=1
      break
    fi
  elif command -v nc >/dev/null 2>&1; then
    if nc -z 127.0.0.1 "$LOCAL_PORT" >/dev/null 2>&1; then
      LISTENING=1
      break
    fi
  else
    if timeout 1 bash -c "echo >/dev/tcp/127.0.0.1/$LOCAL_PORT" >/dev/null 2>&1; then
      LISTENING=1
      break
    fi
  fi
  sleep 0.25
done
if [[ "$LISTENING" != 1 ]]; then
  printf "\n==================== %s ====================\n" "$LOG_FILE"
  [[ -f "$LOG_FILE" ]] && cat "$LOG_FILE"
  printf "\n==================== %s ====================\n" "$ERR_FILE"
  [[ -f "$ERR_FILE" ]] && cat "$ERR_FILE"
  die "tcp-agent did not listen on port $LOCAL_PORT."
fi
ok "tcp-agent PID: $AGENT_PID"
ok "Listening: 127.0.0.1:$LOCAL_PORT"
info "Waiting for authenticated relay WebSocket..."
RELAY_CONNECTED=0
for _ in {1..60}; do
  if ! kill -0 "$AGENT_PID" 2>/dev/null; then
    printf "\n==================== %s ====================\n" "$LOG_FILE"
    [[ -f "$LOG_FILE" ]] && cat "$LOG_FILE"
    printf "\n==================== %s ====================\n" "$ERR_FILE"
    [[ -f "$ERR_FILE" ]] && cat "$ERR_FILE"
    die "tcp-agent exited before relay connection became ready."
  fi
  # IMPORTANT: do not search for the bare substring connected because
  # disconnected contains connected.
  if grep -Eq "\[standard\] \[agent\] connected([[:space:]]|$)" "$LOG_FILE" 2>/dev/null; then
    RELAY_CONNECTED=1
    break
  fi
  if grep -Eq "\[standard\] \[agent\] auth_failed([[:space:]]|$)" "$LOG_FILE" 2>/dev/null; then
    printf "\n==================== %s ====================\n" "$LOG_FILE"
    cat "$LOG_FILE"
    die "Relay rejected tcp-agent credentials."
  fi
  sleep 0.25
done
if [[ "$RELAY_CONNECTED" != 1 ]]; then
  printf "\n==================== %s ====================\n" "$LOG_FILE"
  [[ -f "$LOG_FILE" ]] && cat "$LOG_FILE"
  printf "\n==================== %s ====================\n" "$ERR_FILE"
  [[ -f "$ERR_FILE" ]] && cat "$ERR_FILE"
  die "tcp-agent local listener opened, but relay WebSocket never reached connected state."
fi
ok "Relay connection confirmed."
rm -f "$KEYSCAN_FILE"
ssh-keyscan -T 5 -p "$LOCAL_PORT" 127.0.0.1 >"$KEYSCAN_FILE" 2>/dev/null || true
if [[ -s "$KEYSCAN_FILE" ]]; then
  printf "\n[INFO] SSH host fingerprints for %s:\n" "$TUNNEL_ID"
  ssh-keygen -lf "$KEYSCAN_FILE" || true
  printf "\nVerify the ED25519 fingerprint against the target notebook before accepting a new or changed host key.\n"
else
  printf "\n[WARN] ssh-keyscan did not obtain a host key. SSH will still be attempted.\n"
fi
printf "\n"
info "Connecting to $TUNNEL_ID..."
printf "       ssh -i %s -p %s %s@127.0.0.1\n\n" "$SSH_KEY" "$LOCAL_PORT" "$SSH_USER"
set +e
ssh -i "$SSH_KEY" -p "$LOCAL_PORT" "$SSH_USER@127.0.0.1"
SSH_RC=$?
set -e
printf "\n[INFO] SSH exited with code %s.\n" "$SSH_RC"
printf "[INFO] Route %s on local port %s will now be closed.\n" "$TUNNEL_ID" "$LOCAL_PORT"
exit "$SSH_RC"
