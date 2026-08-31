# Nodejs WSS Service Bridge (HTTP-over-WebSocket Reverse Tunnel)

[![CI](https://github.com/dangkhoa2016/Nodejs-WSS-Service-Bridge/actions/workflows/ci.yml/badge.svg)](https://github.com/dangkhoa2016/Nodejs-WSS-Service-Bridge/actions/workflows/ci.yml)
[![Node.js](https://img.shields.io/badge/Node.js-%3E%3D20-339933?logo=node.js&logoColor=white)](https://nodejs.org/)
[![Yarn](https://img.shields.io/badge/Yarn-4.17.1-2C8EBB?logo=yarn&logoColor=white)](https://yarnpkg.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Transport](https://img.shields.io/badge/Transport-HTTP%20%7C%20TCP%20%7C%20SSH-4C8BF5)](docs/START-HERE.md)
[![Tunnel](https://img.shields.io/badge/Tunnel-WebSocket%20%2F%20WSS-6A5ACD)](docs/START-HERE.md)

> 🌐 Language / Ngôn ngữ: **English** | [Tiếng Việt](README.vi.md)

A self-hosted reverse tunnel for **HTTP applications** and **generic TCP services** over WebSocket.

It is designed for environments that can make outbound Internet connections but cannot easily accept inbound connections, such as Kaggle, Google Colab, private machines, development containers, and hosts behind restrictive NAT/firewalls.

The same project covers three common user-facing use cases:

1. **Expose an HTTP application** — Rails, Node.js, FastAPI, Gradio, REST APIs, web UIs.
2. **Share TCP services** — Redis, PostgreSQL, MySQL, Qdrant gRPC, and other TCP endpoints.
3. **SSH / SCP / SFTP** — remote shell and file transfer through the generic TCP tunnel.

> New to the project? **Start here:** [Self-hosting guide for beginners](docs/START-HERE.md)

---

## Why this project

A target machine does not need a public inbound port.

Instead, the target opens an authenticated outbound WebSocket connection to a relay that you control:

```text
Private target
(Rails / Redis / sshd)
       |
       | outbound WSS /tunnel
       v
+---------------------------+
| Nodejs-WSS-Service-Bridge relay   |
| public HTTPS/WSS endpoint |
+---------------------------+
       ^
       |
       | HTTP or WSS /tcp
       |
Browser / app / local tcp-agent
```

This makes the project useful for:

- demos running on Kaggle or Colab;
- private/home machines behind NAT;
- PaaS environments that expose only one public HTTP port;
- self-hosted access to development services;
- connecting an application host to a private Redis/PostgreSQL service;
- SSH access without opening SSH directly on the target machine.

---

## Three use cases

### 1. HTTP applications

Example:

```text
Internet
   |
https://tunnel.example.com
   |
Nodejs-WSS-Service-Bridge
   |
WSS /tunnel
   |
private machine
   |
http://127.0.0.1:3000
   |
Rails
```

Guide:

**[Use Case 1 — Expose an HTTP Application](docs/use-case-http.md)**

Typical targets:

- Rails;
- Node.js / Express;
- FastAPI;
- Gradio;
- web dashboards;
- REST APIs.

---

### 2. Redis / PostgreSQL / generic TCP

Two modes are available.

**Direct TCP** — best on a VPS where you control TCP ports:

```text
application -> relay:6379 -> WSS /tunnel -> target -> Redis:6379
```

**TCP-agent mode** — best on one-port PaaS hosting:

```text
application
   -> 127.0.0.1:6379
   -> tcp-agent
   -> WSS /tcp
   -> relay
   -> WSS /tunnel
   -> target
   -> Redis:6379
```

Guide:

**[Use Case 2 — Share Redis, PostgreSQL, and Other TCP Services](docs/use-case-tcp.md)**

---

### 3. SSH / SCP / SFTP

SSH is transported by the same generic TCP tunnel.

```text
ssh -p 22001 user@127.0.0.1
       |
       v
local tcp-agent
       |
    WSS /tcp
       |
       v
relay
       |
  WSS /tunnel
       |
       v
kaggle-1 -> 127.0.0.1:2222 sshd
```

The multi-target topology supports routes such as:

```text
22001 -> kaggle-1:2222
22002 -> kaggle-2:2222
```

Guide:

**[Use Case 3 — SSH, SCP, and SFTP](docs/use-case-ssh.md)**

### Reusable SSH helper scripts

The repository includes three portable helpers under `scripts/`:

| Script | Environment | Purpose |
|---|---|---|
| `setup-wss-ssh-target.sh` | Kaggle / Colab / Ubuntu-like target | Create the key-only SSH target, optional passwordless sudo, and register a named tunnel client |
| `ssh-via-nodejs-wss-service-bridge.sh` | Linux / GitHub Codespaces | Start a local TCP agent route and open SSH to a named target |
| `ssh-via-nodejs-wss-service-bridge.bat` | Windows | Start the equivalent local TCP agent route with Windows OpenSSH |

The helpers do not hard-code a private relay domain, install UUID, relay credentials, or machine-specific SSH-key path. Configure those values in the environment. Standard key paths such as `$HOME/.ssh/id_ed25519` and `%USERPROFILE%\.ssh\id_ed25519` are used in examples.

Linux / Codespaces example:

```bash
export RELAY_HOST='tunnel.example.com'
export INSTALL_UUID='<stable-install-uuid>'
export AGENT_USERNAME='<relay-user>'

./scripts/ssh-via-nodejs-wss-service-bridge.sh \
  "$HOME/.ssh/id_ed25519" \
  colab-1
```

Windows example:

```bat
set "RELAY_HOST=tunnel.example.com"
set "INSTALL_UUID=<stable-install-uuid>"
set "AGENT_USERNAME=<relay-user>"

scripts\ssh-via-nodejs-wss-service-bridge.bat "%USERPROFILE%\.ssh\id_ed25519" "colab-1"
```

Target bootstrap example:

```bash
export TUNNEL_SERVER_URL='https://tunnel.example.com'
export TUNNEL_USERNAME='<relay-user>'
export INSTALL_UUID='<stable-install-uuid>'
export TUNNEL_PASSWORD='<relay-password>'
export SSH_PUBLIC_KEY_FILE="$HOME/.ssh/id_ed25519.pub"

sudo -E ./scripts/setup-wss-ssh-target.sh colab-1
```

Live SSH helper acceptance:

| Local environment | Kaggle target | Colab target | `tmux` continuity |
|---|---|---|---|
| Windows 10 | PASS | PASS | PASS on Colab |
| GitHub Codespaces / Linux | Not re-run in this closeout | PASS | PASS on Colab |

The matrix reports only combinations exercised in the recorded live acceptance; an untested cell is not presented as a failure.

---

## What is actually implemented

At the transport level, the project has two main capabilities:

```text
Nodejs-WSS-Service-Bridge
│
├── HTTP reverse tunnel
│   └── HTTP apps / REST APIs / web UIs
│
└── Generic TCP tunnel
    ├── Redis
    ├── PostgreSQL
    ├── MySQL
    ├── SSH
    ├── SCP / SFTP
    └── other TCP protocols
```

SSH is a TCP use case, not a separate custom protocol in the relay.

---

# Quick start — deploy your own relay

## Requirements

- Node.js 20 or newer;
- Git;
- Corepack/Yarn;
- Linux recommended;
- HTTPS endpoint for public Internet deployments.

Clone:

```bash
git clone https://github.com/dangkhoa2016/Nodejs-WSS-Service-Bridge.git
cd Nodejs-WSS-Service-Bridge

corepack enable
yarn install --immutable
yarn build:client
```

The build step creates the standalone bundles served to targets and agents:

```text
dist/client.js
dist/tcp-agent.js
```

---

## Choose a server profile

### One public port / PaaS

Use:

```bash
cp .env.example.single-port .env
```

Recommended for:

- Northflank;
- Render;
- Railway;
- Fly.io-style platforms;
- other HTTP/HTTPS-only hosts.

HTTP works directly through the relay. TCP and SSH use the TCP agent.

### VPS / dedicated server

Use:

```bash
cp .env.example.vps .env
```

A VPS can use both direct TCP and TCP-agent mode.

---

## Minimum configuration

Generate a stable UUID once:

```bash
node -e "console.log(require('node:crypto').randomUUID())"
```

Generate a strong password:

```bash
node -e "console.log(require('node:crypto').randomBytes(32).toString('hex'))"
```

Set at least:

```env
PORT=7860
SERVER_HOST=https://tunnel.example.com

INSTALL_UUID=<stable-uuid>

TUNNEL_USERNAME=<your-user>
TUNNEL_PASSWORD=<long-random-secret>

MAX_TUNNEL_CLIENTS=1
```

For a one-port server using Redis/PostgreSQL/SSH:

```env
TCP_TUNNEL_PORTS=
TCP_AGENT_ALLOWED_PORTS=6379,5432,2222
```

For long-idle SSH:

```env
STREAM_IDLE_TIMEOUT_MS=0
```

---

## Start

Development:

```bash
yarn dev
```

Production from a shell:

```bash
set -a
. ./.env
set +a

yarn build:client
yarn prod
```

> In production mode, the application does not automatically load `.env`; export variables or configure them in your hosting platform.

Docker:

```bash
docker build -t nodejs-wss-service-bridge .

docker run --rm   --env-file .env   -p 7860:7860   nodejs-wss-service-bridge
```

---

## Verify the relay

```bash
curl -fsS https://tunnel.example.com/__health
```

Expected:

```text
ok
```

Information page:

```text
https://tunnel.example.com/__info
```

Important routes:

| Route | Purpose |
|---|---|
| `/tunnel` | target client WebSocket |
| `/tcp` | TCP-agent WebSocket |
| `/__health` | health check |
| `/__info` | deployment information |
| `/<INSTALL_UUID>-install` | target-client installer |
| `/<INSTALL_UUID>-client.js` | target-client bundle |
| `/<INSTALL_UUID>-tcp-agent.js` | TCP-agent bundle |

---

# Target-client installation

The relay serves an installer for the private target.

HTTP example:

```bash
export TUNNEL_SERVER_URL='https://tunnel.example.com'
export TUNNEL_USERNAME='<your-user>'
export TUNNEL_PASSWORD='<your-secret>'
export TARGET_ORIGIN='http://127.0.0.1:3000'

curl -fsSL   'https://tunnel.example.com/<INSTALL_UUID>-install'   | bash
```

State is stored under:

```text
~/.tunnel-client/
```

Healthy state:

```text
client.pid == client.ready == live client PID
```

Inspect:

```bash
cat ~/.tunnel-client/client.pid
cat ~/.tunnel-client/client.ready
ps -fp "$(cat ~/.tunnel-client/client.pid)"
tail -n 100 ~/.tunnel-client/client.log
```

The installer uses a transactional release/readiness model and detaches the target client from the installer/notebook-cell lifecycle using `setsid` when available, `nohup`, and stdin from `/dev/null`.

A full runtime/container/host restart is a different failure domain and requires the process to be started again.

---

# Multi-target TCP routing

Each target can register a unique `TUNNEL_ID`:

```text
kaggle-1
kaggle-2
colab-1
```

A local TCP agent can then define explicit routes:

```env
AGENT_ROUTES=22001=kaggle-1:2222,22002=kaggle-2:2222
```

Syntax:

```text
localPort=targetTunnelId:targetPort
```

This enables deterministic routing through one public relay.

---

# Security

The project includes:

- HTTP Basic authentication for tunnel WebSocket clients;
- separate/fallback authentication for TCP agents;
- constant-time credential comparison;
- IPv4/CIDR allowlists for direct TCP listeners;
- optional TLS enforcement for `/tcp`;
- trusted-proxy controls;
- loopback-by-default TCP-agent binding;
- HMAC-signed admin configuration URLs;
- transactional client/agent installers with readiness and rollback.

Still follow normal service security practices:

- keep Redis/PostgreSQL authentication enabled;
- prefer SSH public keys;
- use firewall rules for direct TCP;
- do not commit real secrets;
- do not log SSH/database passwords;
- use HTTPS/WSS on public deployments.

---

# Important limitations

## HTTP WebSocket Upgrade

The generic HTTP proxy currently does not proxy arbitrary downstream HTTP `Upgrade: websocket` requests.

Normal HTTP request/response traffic works. Applications depending on Action Cable, Socket.IO WebSocket transport, or custom browser WebSocket endpoints must test that requirement separately.

## HTTP with several target clients

`TUNNEL_ID` provides deterministic TCP target selection. Generic HTTP proxying selects an active connected client rather than routing by `TUNNEL_ID`.

For a simple HTTP deployment, keep:

```env
MAX_TUNNEL_CLIENTS=1
```

## Process detachment vs host restart

A detached client can survive its parent installer/notebook cell ending while the runtime remains alive.

It cannot survive a full runtime/container/VM/host restart.

---

# Documentation

## Beginner / deployment guides

- **[Start Here — self-hosting guide](docs/START-HERE.md)**
- **[Use Case 1 — HTTP application](docs/use-case-http.md)**
- **[Use Case 2 — TCP services](docs/use-case-tcp.md)**
- **[Use Case 3 — SSH / SCP / SFTP](docs/use-case-ssh.md)**

## Advanced references

- [TCP tunnel deployment and operations](docs/tcp-tunnel.md)
- [Connect external applications to TCP services](docs/guide-external-app-to-tcp-services.md)
- [Testing](TESTING.md)
- [Final live / resilience qualification report](docs/final-live-qualification-2026-08-22.md)
- [Cross-platform live acceptance report](docs/live-cross-platform-acceptance-2026-08-24.md)

Vietnamese versions are provided alongside the English documentation.

---

# Validation status

The final live/resilience qualification covered:

- two independent target clients;
- official installer lifecycle;
- detached-process longevity;
- multi-target routing;
- true-idle SSH;
- target reconnect and isolation;
- local tcp-agent reconnect;
- final interactive SSH;
- SCP;
- SHA-256 file-integrity verification.

Result:

```text
FINAL LIVE / RESILIENCE QUALIFICATION = PASS
```

See [the qualification report](docs/final-live-qualification-2026-08-22.md) for the evidence and tested authority.

A later [cross-platform live acceptance report](docs/live-cross-platform-acceptance-2026-08-24.md) additionally records HTTP, Redis, and PostgreSQL tunneled across independent environments (Colab, Kaggle, Codespaces) through the same relay.

---

# Development and testing

Run the full local checks:

```bash
yarn check
```

Individual commands:

```bash
yarn lint
yarn test
yarn build:client
```

See [TESTING.md](TESTING.md) for detailed test documentation.

---

# License

MIT — see [LICENSE](LICENSE).
