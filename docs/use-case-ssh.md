# Use Case 3 — SSH, SCP, and SFTP Through the Tunnel

> 🌐 Language / Ngôn ngữ: **English** | [Tiếng Việt](use-case-ssh.vi.md)

Use this guide when a private machine runs `sshd` and you want to reach it over SSH without opening an inbound public SSH port on that private machine.

If you have not deployed the relay yet, start with [START-HERE.md](START-HERE.md).

---

## 1. How SSH fits into this project

SSH is carried as generic raw TCP.

There is no SSH-specific protocol implementation inside Nodejs-WSS-Service-Bridge.

```text
ssh / scp / sftp
      |
      | local TCP
      v
tcp-agent
      |
      | WSS /tcp
      v
Nodejs-WSS-Service-Bridge relay
      |
      | WSS /tunnel
      v
target tunnel client
      |
      | TCP 127.0.0.1:2222
      v
sshd
```

Because SCP and SFTP run over SSH, they use the same tunnel path.

---

## 2. Recommended topology

For a relay hosted on a one-public-port PaaS, use:

- relay: public HTTPS/WSS;
- target: `sshd` on loopback, for example `127.0.0.1:2222`;
- local/admin machine: tcp-agent listening on a loopback port;
- SSH client: connects to that local loopback port.

The target machine never needs to expose port 22/2222 to the Internet.

---

## 3. Configure the relay

Example single-target configuration:

```env
INSTALL_UUID=<stable-uuid>

TUNNEL_USERNAME=<tunnel-user>
TUNNEL_PASSWORD=<long-random-secret>

MAX_TUNNEL_CLIENTS=1

TCP_TUNNEL_PORTS=
TCP_TUNNEL_HOST=127.0.0.1
TCP_CLIENT_ALLOWED_HOSTS=127.0.0.1

TCP_AGENT_PATH=/tcp
TCP_AGENT_ALLOWED_PORTS=2222

STREAM_IDLE_TIMEOUT_MS=0
```

For SSH, `STREAM_IDLE_TIMEOUT_MS=0` is recommended when you want truly idle long-lived SSH sessions.

The WebSocket heartbeat still detects dead tunnel connections; this setting disables the application stream idle timeout.

---

## 4. Prepare SSH on the target machine

The exact package command depends on the Linux distribution.

Ubuntu/Debian example:

```bash
sudo apt-get update
sudo apt-get install -y openssh-server
```

Create or use a normal login user. Prefer SSH keys in production.

A simple loopback-only sshd configuration can use:

```text
Port 2222
ListenAddress 127.0.0.1
PasswordAuthentication yes
UsePAM yes
```

For key-only authentication, set the appropriate `PasswordAuthentication no` and configure `authorized_keys`.

Restart or launch sshd according to your distribution.

Verify locally on the target:

```bash
ss -ltn | grep ':2222'
ssh-keyscan -p 2222 127.0.0.1
```

Do not continue until `127.0.0.1:2222` is listening.

---

## 5. Install the tunnel client on the SSH target

For a single target:

```bash
export TUNNEL_SERVER_URL='https://tunnel.example.com'
export TUNNEL_USERNAME='<tunnel-user>'
export TUNNEL_PASSWORD='<long-random-secret>'

curl -fsSL 'https://tunnel.example.com/<INSTALL_UUID>-install' | bash
```

For a named target, add:

```bash
export TUNNEL_ID='kaggle-1'
```

before running the installer.

Verify:

```bash
cat ~/.tunnel-client/client.pid
cat ~/.tunnel-client/client.ready
ps -fp "$(cat ~/.tunnel-client/client.pid)"
tail -n 100 ~/.tunnel-client/client.log
```

Healthy:

```text
client.pid == client.ready == live client PID
```

---

# Part A — Simple single-target SSH

## 6. Install a local tcp-agent

For a single target using the same local and target port, the repository installer is the easiest option.

On the machine where you will run `ssh`:

```bash
export SERVER_HOST='tunnel.example.com'
export INSTALL_UUID='<stable-uuid>'

export AGENT_USERNAME='<agent-user-or-tunnel-user>'
export AGENT_PASSWORD='<agent-secret-or-tunnel-password>'

export AGENT_PORTS='2222'

./scripts/setup-application-host.sh
```

If separate `TCP_AGENT_USERNAME` / `TCP_AGENT_PASSWORD` are not configured on the relay, agent credentials fall back to the tunnel credentials.

Verify:

```bash
cat ~/.tcp-agent/agent.pid
cat ~/.tcp-agent/agent.ready
ps -fp "$(cat ~/.tcp-agent/agent.pid)"
ss -ltn | grep ':2222'
tail -n 100 ~/.tcp-agent/agent.log
```

---

## 7. Connect with SSH

```bash
ssh -p 2222 <user>@127.0.0.1
```

The TCP flow is:

```text
127.0.0.1:2222
  -> tcp-agent
  -> WSS /tcp
  -> relay
  -> WSS /tunnel
  -> target client
  -> 127.0.0.1:2222 sshd
```

---

## 8. Copy files with SCP

Upload:

```bash
scp -P 2222 ./local-file.txt <user>@127.0.0.1:/home/<user>/local-file.txt
```

Download:

```bash
scp -P 2222 <user>@127.0.0.1:/home/<user>/remote-file.txt ./
```

SFTP:

```bash
sftp -P 2222 <user>@127.0.0.1
```

---

# Part B — Multiple SSH targets with local port mapping

## 9. Why `AGENT_ROUTES` is useful

Suppose two private targets both run sshd on port 2222:

```text
kaggle-1 -> 127.0.0.1:2222
kaggle-2 -> 127.0.0.1:2222
```

You can expose them locally as:

```text
127.0.0.1:22001 -> kaggle-1:2222
127.0.0.1:22002 -> kaggle-2:2222
```

This is the topology used in the final live qualification.

Relay:

```env
MAX_TUNNEL_CLIENTS=2
TCP_AGENT_ALLOWED_PORTS=2222
STREAM_IDLE_TIMEOUT_MS=0
```

Target 1:

```bash
export TUNNEL_ID='kaggle-1'
```

Target 2:

```bash
export TUNNEL_ID='kaggle-2'
```

Each target runs the official tunnel installer with the same relay credentials.

---

## 10. Install the standalone tcp-agent for route mapping

`scripts/setup-application-host.sh` currently configures `AGENT_PORTS`, which uses the same local and target port.

For explicit port remapping / multiple named targets, run the standalone tcp-agent with `AGENT_ROUTES`.

Create a working directory:

```bash
mkdir -p ~/.nodejs-wss-service-bridge-agent
cd ~/.nodejs-wss-service-bridge-agent
```

Download the served bundle and manifest:

```bash
curl -fsSL   'https://tunnel.example.com/<INSTALL_UUID>-tcp-agent.js'   -o tcp-agent.js

curl -fsSL   'https://tunnel.example.com/<INSTALL_UUID>-tcp-agent-package.json'   -o package.json

npm install --omit=dev
```

Set environment:

```bash
export TUNNEL_SERVER_URL='wss://tunnel.example.com/tcp'
export AGENT_USERNAME='<agent-user-or-tunnel-user>'
export AGENT_PASSWORD='<agent-secret-or-tunnel-password>'

export AGENT_BIND_HOST='127.0.0.1'
export AGENT_ROUTES='22001=kaggle-1:2222,22002=kaggle-2:2222'
```

Start it detached on Linux:

```bash
setsid nohup node ./tcp-agent.js   </dev/null   > ./agent.log 2>&1 &

echo $! > ./agent.pid
```

Verify:

```bash
PID="$(cat ./agent.pid)"
kill -0 "$PID"
ps -fp "$PID"

ssh-keyscan -p 22001 127.0.0.1
ssh-keyscan -p 22002 127.0.0.1
```

The relay's `TCP_AGENT_ALLOWED_PORTS` must allow the **target port** requested by the route, here `2222`. It does not need to contain local ports 22001/22002.

---

## 11. Connect to each target

Target 1:

```bash
ssh -p 22001 <user>@127.0.0.1
```

Target 2:

```bash
ssh -p 22002 <user>@127.0.0.1
```

SCP follows the same mapping:

```bash
scp -P 22001 ./file.txt <user>@127.0.0.1:/home/<user>/file.txt
scp -P 22002 ./file.txt <user>@127.0.0.1:/home/<user>/file.txt
```

---

## 12. Verify target isolation

With both targets connected:

```bash
ssh-keyscan -p 22001 127.0.0.1
ssh-keyscan -p 22002 127.0.0.1
```

Each route should reach only its configured `TUNNEL_ID`.

If `kaggle-1` disconnects, route 22001 should fail while route 22002 can remain healthy.

This behavior was explicitly validated in the final R3 reconnect test.

---

## 13. Host-key changes after an ephemeral runtime restart

Kaggle/Colab or rebuilt OpenSSH installations may generate new SSH host keys.

If SSH reports:

```text
WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!
```

do not blindly remove the old key.

First verify why the target changed and obtain/verify the new expected fingerprint through a trusted path.

Then remove only the specific stale local entry, for example:

```bash
ssh-keygen -R '[127.0.0.1]:22001'
```

and reconnect after verifying the new fingerprint.

---

## 14. Runtime restart vs. client lifecycle

The target installer is detached from the notebook/cell shell lifecycle.

This means closing/finishing the installer cell should not kill the client while the runtime is still alive.

It does **not** survive:

- Kaggle runtime restart;
- Colab runtime restart;
- container restart;
- VM reboot;
- host destruction.

After a full target runtime restart:

1. restore/install `sshd`;
2. restore the login user/authorized keys if the environment lost them;
3. re-run the official tunnel installer with the same `TUNNEL_ID`;
4. verify `127.0.0.1:2222`;
5. verify the local route again.

After a local tcp-agent host restart, restart the tcp-agent. A persisted PID file may be stale; verify it with `kill -0` and `ps`.

---

## 15. Security recommendations

Prefer:

- SSH public-key authentication;
- a non-root user;
- `sshd` bound to `127.0.0.1` on the private target;
- tcp-agent bound to `127.0.0.1`;
- WSS/HTTPS for the relay;
- strong tunnel/agent credentials.

Do not publish the private SSH password in logs, documentation, scripts, or repository files.

The tunnel transports SSH securely as SSH traffic, but weak SSH credentials remain weak credentials.

---

## 16. Troubleshooting

### `Tunnel target not connected: kaggle-1`

The target client for that ID is not registered.

Check:

```bash
tail -n 100 ~/.tunnel-client/client.log
```

### `connect ECONNREFUSED 127.0.0.1:2222`

This is different: the tunnel reached the target, but sshd is missing or not listening.

Check on the target:

```bash
ss -ltn | grep ':2222'
ssh-keyscan -p 2222 127.0.0.1
```

### Local `ssh -p 22001` says connection refused

Check the local tcp-agent first:

```bash
ss -ltn | grep ':22001'
ps -fp "$(cat ~/.nodejs-wss-service-bridge-agent/agent.pid)"
tail -n 100 ~/.nodejs-wss-service-bridge-agent/agent.log
```

### SSH hangs or drops after idle time

For the tested long-idle SSH profile, configure the relay/client stream policy with:

```env
STREAM_IDLE_TIMEOUT_MS=0
```

The final live qualification kept a truly idle SSH session healthy for about 9 minutes 53 seconds.

---

## 17. Acceptance checklist

- [ ] relay `/__health` returns `ok`;
- [ ] sshd listens on target loopback;
- [ ] target tunnel client is ready;
- [ ] local tcp-agent listens on the expected loopback port;
- [ ] `ssh-keyscan` succeeds through the tunnel;
- [ ] interactive SSH succeeds;
- [ ] SCP succeeds when file transfer is required;
- [ ] multi-target routes reach the correct `TUNNEL_ID`;
- [ ] SSH host-key changes are verified rather than blindly accepted;
- [ ] full runtime restart is treated separately from shell/cell lifecycle.

See the [final live qualification report](final-live-qualification-2026-08-22.md) for the tested two-target SSH/SCP evidence.
