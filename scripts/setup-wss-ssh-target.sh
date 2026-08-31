#!/usr/bin/env bash
set -Eeuo pipefail
# Nodejs-WSS-Service-Bridge v1.0.0
# Portable SSH target bootstrap for Kaggle, Google Colab, and Ubuntu-like runtimes.
#
# Usage:
#   export TUNNEL_SERVER_URL='https://tunnel.example.com'
#   export TUNNEL_USERNAME='bridge-user'
#   export INSTALL_UUID='stable-install-uuid'
#   export TUNNEL_PASSWORD='...'
#   export SSH_PUBLIC_KEY_FILE='$HOME/.ssh/id_ed25519.pub'
#   sudo -E bash setup-wss-ssh-target.sh colab-1
#
# Optional overrides:
#   TUNNEL_SERVER_URL
#   TUNNEL_USERNAME
#   INSTALL_UUID
#   SSH_PUBLIC_KEY or SSH_PUBLIC_KEY_FILE
#   SSH_USER
#   SSH_PORT
#
# The only target-specific argument is TUNNEL_ID. Relay identity and SSH key
# material are supplied through environment variables so the script is reusable.
TUNNEL_ID="${1:-}"
: "${SSH_USER:=tunneluser}"
: "${SSH_PORT:=2222}"
: "${SSH_PUBLIC_KEY:=}"
: "${SSH_PUBLIC_KEY_FILE:=}"
die() {
  printf '\n[ERROR] %s\n' "$*" >&2
  exit 1
}
section() {
  printf '\n=== %s ===\n' "$*"
}
if [[ $EUID -ne 0 ]]; then
  die "Run this script as root (Kaggle/Colab notebook %%bash cells normally run as root)."
fi
if [[ -z "$TUNNEL_ID" ]]; then
  cat >&2 <<'USAGE'
Usage:
  export TUNNEL_SERVER_URL='https://tunnel.example.com'
  export TUNNEL_USERNAME='bridge-user'
  export INSTALL_UUID='stable-install-uuid'
  export TUNNEL_PASSWORD='YOUR_RELAY_PASSWORD'
  export SSH_PUBLIC_KEY_FILE="$HOME/.ssh/id_ed25519.pub"
  sudo -E bash setup-wss-ssh-target.sh <TUNNEL_ID>
Examples:
  sudo -E bash setup-wss-ssh-target.sh kaggle-1
  sudo -E bash setup-wss-ssh-target.sh colab-1
USAGE
  exit 2
fi
if [[ ! "$TUNNEL_ID" =~ ^[A-Za-z0-9._-]+$ ]]; then
  die "Invalid TUNNEL_ID '$TUNNEL_ID'. Allowed: letters, digits, dot, underscore, hyphen."
fi
[[ -n "${TUNNEL_SERVER_URL:-}" ]] || die "TUNNEL_SERVER_URL is required (for example: https://tunnel.example.com)."
[[ -n "${TUNNEL_USERNAME:-}" ]] || die "TUNNEL_USERNAME is required."
[[ -n "${INSTALL_UUID:-}" ]] || die "INSTALL_UUID is required."
if [[ -z "$SSH_PUBLIC_KEY" && -n "$SSH_PUBLIC_KEY_FILE" ]]; then
  [[ -f "$SSH_PUBLIC_KEY_FILE" ]] || die "SSH_PUBLIC_KEY_FILE does not exist: $SSH_PUBLIC_KEY_FILE"
  SSH_PUBLIC_KEY="$(tr -d '\r\n' < "$SSH_PUBLIC_KEY_FILE")"
fi
[[ -n "$SSH_PUBLIC_KEY" ]] || die "Set SSH_PUBLIC_KEY or SSH_PUBLIC_KEY_FILE before running the script."
if [[ -z "${TUNNEL_PASSWORD:-}" ]]; then
  if [[ -t 0 ]]; then
    read -r -s -p "Tunnel password: " TUNNEL_PASSWORD
    printf '\n'
    export TUNNEL_PASSWORD
  else
    die "TUNNEL_PASSWORD is not set. Export it before running this script."
  fi
fi
export TUNNEL_SERVER_URL
export TUNNEL_USERNAME
export TUNNEL_PASSWORD
export INSTALL_UUID
export TUNNEL_ID
section "PROFILE"
printf 'TUNNEL_SERVER_URL=%s\n' "$TUNNEL_SERVER_URL"
printf 'TUNNEL_USERNAME=%s\n' "$TUNNEL_USERNAME"
printf 'INSTALL_UUID=%s\n' "$INSTALL_UUID"
printf 'TUNNEL_ID=%s\n' "$TUNNEL_ID"
printf 'SSH_USER=%s\n' "$SSH_USER"
printf 'SSH_PORT=%s\n' "$SSH_PORT"
printf 'TUNNEL_PASSWORD=[hidden]\n'
section "INSTALL PACKAGES"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  openssh-server \
  curl \
  ca-certificates
section "SSH USER"
if ! id "$SSH_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$SSH_USER"
fi
USER_HOME="$(getent passwd "$SSH_USER" | cut -d: -f6)"
[[ -n "$USER_HOME" ]] || die "Could not resolve home directory for $SSH_USER."
usermod --home "$USER_HOME" --shell /bin/bash "$SSH_USER"
# useradd commonly leaves a new account with a locked password marker.
# We use key-only SSH, but some OpenSSH/PAM combinations reject a locked
# account before public-key authentication. NP (no password) avoids that.
# Password SSH stays disabled below.
passwd -d "$SSH_USER" >/dev/null
chown "$SSH_USER:$SSH_USER" "$USER_HOME"
chmod 750 "$USER_HOME"
printf 'Account status: '
passwd -S "$SSH_USER" || true
section "SUDO ACCESS"
# The SSH account is key-only and has no usable password. Granting NOPASSWD
# allows administrative work after SSH login, which is convenient for
# ephemeral Kaggle/Colab runtimes. Anyone holding the SSH private key can
# therefore become root on this runtime.
if ! command -v sudo >/dev/null 2>&1; then
  DEBIAN_FRONTEND=noninteractive apt-get install -y sudo
fi
if getent group sudo >/dev/null 2>&1; then
  usermod -aG sudo "$SSH_USER"
fi
cat > "/etc/sudoers.d/90-${SSH_USER}-nodejs-wss-service-bridge" <<EOF
${SSH_USER} ALL=(ALL:ALL) NOPASSWD: ALL
EOF
chmod 0440 "/etc/sudoers.d/90-${SSH_USER}-nodejs-wss-service-bridge"
visudo -cf "/etc/sudoers.d/90-${SSH_USER}-nodejs-wss-service-bridge"
printf 'Sudo groups: '
id "$SSH_USER"
printf 'Sudo policy check:\n'
su -s /bin/bash - "$SSH_USER" -c 'sudo -n id'
section "AUTHORIZED KEY"
install -d \
  -o "$SSH_USER" \
  -g "$SSH_USER" \
  -m 700 \
  "$USER_HOME/.ssh"
printf '%s\n' "$SSH_PUBLIC_KEY" > "$USER_HOME/.ssh/authorized_keys"
chown "$SSH_USER:$SSH_USER" "$USER_HOME/.ssh/authorized_keys"
chmod 600 "$USER_HOME/.ssh/authorized_keys"
printf 'Authorized key fingerprint:\n'
ssh-keygen -lf "$USER_HOME/.ssh/authorized_keys"
section "SSHD"
mkdir -p /run/sshd
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-nodejs-wss-service-bridge.conf <<EOF
Port $SSH_PORT
ListenAddress 127.0.0.1
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
AuthorizedKeysFile .ssh/authorized_keys
StrictModes yes
AllowUsers $SSH_USER
EOF
# Validate both the normal config and the exact command-line policy we start with.
/usr/sbin/sshd -t
SSHD_OPTS=(
  -o "Port=$SSH_PORT"
  -o "ListenAddress=127.0.0.1"
  -o "PermitRootLogin=no"
  -o "PubkeyAuthentication=yes"
  -o "PasswordAuthentication=no"
  -o "PermitEmptyPasswords=no"
  -o "AuthorizedKeysFile=.ssh/authorized_keys"
  -o "StrictModes=yes"
  -o "AllowUsers=$SSH_USER"
)
/usr/sbin/sshd -t "${SSHD_OPTS[@]}"
# Notebook runtimes are ephemeral; restarting sshd here gives deterministic state.
pkill -x sshd 2>/dev/null || true
/usr/sbin/sshd "${SSHD_OPTS[@]}"
sleep 1
printf 'Listener:\n'
ss -ltnp | grep ":$SSH_PORT" || die "sshd is not listening on port $SSH_PORT."
printf '\nHost ED25519 fingerprint:\n'
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
section "LOCAL SSH SELF-CHECK"
# This proves that sshd is reachable on loopback. Authentication itself is
# checked from a local launcher using the private key.
KEYSCAN_TMP="$(mktemp)"
trap 'rm -f "$KEYSCAN_TMP"' EXIT
ssh-keyscan -T 5 -p "$SSH_PORT" 127.0.0.1 \
  >"$KEYSCAN_TMP" 2>/dev/null || true
if [[ -s "$KEYSCAN_TMP" ]]; then
  ssh-keygen -lf "$KEYSCAN_TMP" || true
else
  die "ssh-keyscan could not read the local sshd on port $SSH_PORT."
fi
section "INSTALL / REFRESH TUNNEL CLIENT"
INSTALL_URL="${TUNNEL_SERVER_URL%/}/${INSTALL_UUID}-install"
curl -fsSL "$INSTALL_URL" | bash
section "TUNNEL READINESS"
CLIENT_DIR="${HOME}/.tunnel-client"
PID_FILE="$CLIENT_DIR/client.pid"
READY_FILE="$CLIENT_DIR/client.ready"
LOG_FILE="$CLIENT_DIR/client.log"
[[ -s "$PID_FILE" ]] || die "Missing $PID_FILE."
[[ -s "$READY_FILE" ]] || die "Missing $READY_FILE."
CLIENT_PID="$(cat "$PID_FILE")"
READY_PID="$(cat "$READY_FILE")"
[[ "$CLIENT_PID" == "$READY_PID" ]] \
  || die "client.pid ($CLIENT_PID) != client.ready ($READY_PID)."
kill -0 "$CLIENT_PID" 2>/dev/null \
  || die "Tunnel client PID $CLIENT_PID is not alive."
printf 'Tunnel client PID: %s\n' "$CLIENT_PID"
ps -fp "$CLIENT_PID"
printf '\nRecent tunnel log:\n'
tail -n 30 "$LOG_FILE"
if ! grep -Fq "tunnel_id=$TUNNEL_ID" "$LOG_FILE"; then
  die "Tunnel log does not confirm tunnel_id=$TUNNEL_ID."
fi
if ! grep -Eq "\\[standard\\] \\[client\\] connected([[:space:]]|$)" "$LOG_FILE"; then
  die "Tunnel log does not contain an exact client connected state."
fi
section "FINAL"
cat <<EOF
SSH_TARGET_READY=PASS
TUNNEL_ID=$TUNNEL_ID
SSH_USER=$SSH_USER
SSH_TARGET=127.0.0.1:$SSH_PORT
Local route examples:
  kaggle-1 -> local port 22001
  colab-1  -> local port 22002
Windows example:
  scripts\\ssh-via-nodejs-wss-service-bridge.bat "%USERPROFILE%\\.ssh\\id_ed25519" "$TUNNEL_ID"
Linux / Codespaces example:
  ./scripts/ssh-via-nodejs-wss-service-bridge.sh "$HOME/.ssh/id_ed25519" "$TUNNEL_ID"
EOF
