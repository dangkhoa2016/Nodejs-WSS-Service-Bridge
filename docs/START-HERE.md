# Start Here — Self-host Nodejs-WSS-Service-Bridge

> 🌐 Language / Ngôn ngữ: **English** | [Tiếng Việt](START-HERE.vi.md)

This guide is for people who want to clone this repository and deploy their own tunnel without first learning the internal protocol.

Nodejs-WSS-Service-Bridge has **two transport capabilities** and **three common user-facing use cases**:

| Use case | What you expose | Transport used internally | Start with |
|---|---|---|---|
| HTTP application | Rails, Node.js, FastAPI, Gradio, web UI, REST API | HTTP over the tunnel WebSocket | [HTTP application guide](use-case-http.md) |
| TCP service | Redis, PostgreSQL, MySQL, database/service TCP endpoints | Generic raw TCP tunnel | [TCP service guide](use-case-tcp.md) |
| SSH / SCP / SFTP | Remote shell and file transfer | Generic raw TCP tunnel | [SSH guide](use-case-ssh.md) |

SSH is not a separate wire protocol inside this project. It is an important, well-tested application of the generic TCP tunnel.

---

## 1. Understand the three machines

A beginner-friendly deployment is easiest to understand as three roles:

```text
A. Tunnel server / relay
   Publicly reachable Nodejs-WSS-Service-Bridge server

B. Target / service machine
   Runs the thing you want to reach:
   - Rails / Node.js app
   - Redis / PostgreSQL
   - sshd
   Runs the tunnel client and connects OUT to A

C. Consumer machine
   Browser, application, database client, or SSH user
   Connects either directly to A or through a local tcp-agent
```

A and C can be the same machine in development. B can be Kaggle, Colab, a home computer, a private VM, or any environment that can make outbound WebSocket connections.

The important property is that **B does not need an inbound public port**.

---

## 2. Choose where to deploy the public tunnel server

There are two server deployment profiles.

### Profile A — single-public-port hosting

Use this for Northflank, Render, Railway, Fly.io, Codespaces-style environments, or any host that exposes only one HTTP/HTTPS port.

Use:

```text
.env.example.single-port
```

Capabilities:

- HTTP application tunnel: yes
- TCP services: yes, through the TCP agent
- SSH: yes, through the TCP agent
- direct public Redis/PostgreSQL/SSH ports on the relay: no

This is the simplest profile for most users.

### Profile B — VPS / dedicated server

Use this when you control the VM/firewall and may bind additional TCP ports.

Use:

```text
.env.example.vps
```

Capabilities:

- HTTP application tunnel: yes
- TCP services: direct TCP or TCP-agent mode
- SSH: direct TCP or TCP-agent mode

Direct TCP is simpler, but every exposed port must be protected by firewall rules and `TCP_TUNNEL_ALLOWED_IPS`.

---

## 3. Clone and install the server

Requirements:

- Linux is recommended
- Node.js 20 or newer
- Git
- Corepack/Yarn
- a public HTTPS endpoint for Internet use

Clone:

```bash
git clone https://github.com/dangkhoa2016/Nodejs-WSS-Service-Bridge.git
cd Nodejs-WSS-Service-Bridge
corepack enable
yarn install --immutable
```

Build the standalone client and tcp-agent bundles:

```bash
yarn build:client
```

A successful build creates:

```text
dist/client.js
dist/tcp-agent.js
```

Do not skip this step when starting from a fresh Git clone. The production server serves these generated bundles to target machines and application hosts.

---

## 4. Create stable credentials and an installation UUID

Generate a UUID once:

```bash
node -e "console.log(require('node:crypto').randomUUID())"
```

Generate a strong password:

```bash
node -e "console.log(require('node:crypto').randomBytes(32).toString('hex'))"
```

Keep these values private:

```text
INSTALL_UUID
TUNNEL_USERNAME
TUNNEL_PASSWORD
TCP_AGENT_USERNAME / TCP_AGENT_PASSWORD (if separately configured)
ADMIN_SECRET (if enabled)
```

**Pin `INSTALL_UUID`.** Do not generate a new value on every restart. Client and agent download URLs contain this UUID.

---

## 5. Configure the server

### Single-port example

```bash
cp .env.example.single-port .env
```

Minimum values to review:

```env
PORT=7860
SERVER_HOST=https://tunnel.example.com
INSTALL_UUID=<your-stable-uuid>

TUNNEL_USERNAME=<your-user>
TUNNEL_PASSWORD=<your-long-random-password>

MAX_TUNNEL_CLIENTS=1
STREAM_IDLE_TIMEOUT_MS=120000

TCP_TUNNEL_PORTS=
TCP_AGENT_ALLOWED_PORTS=6379,5432,2222
```

Only include TCP ports you actually intend to use.

For long-lived SSH sessions, use:

```env
STREAM_IDLE_TIMEOUT_MS=0
```

### VPS example

```bash
cp .env.example.vps .env
```

For direct Redis and PostgreSQL forwarding:

```env
TCP_TUNNEL_PORTS=6379,5432
TCP_TUNNEL_BIND_HOST=0.0.0.0
TCP_TUNNEL_ALLOWED_IPS=<trusted-client-ip-or-cidr>
```

Never publish Redis, PostgreSQL, SSH, or another raw TCP service to `0.0.0.0` without both service authentication and network/IP restrictions.

---

## 6. Start the server

### Development / local verification

```bash
yarn dev
```

### Production from a shell

The application intentionally does not auto-load `.env` when `NODE_ENV=production`. Export the variables first:

```bash
set -a
. ./.env
set +a

yarn build:client
yarn prod
```

### Production on a PaaS

Configure the variables from the selected env template in the platform's environment-variable UI.

Recommended lifecycle:

```text
Build:
  corepack enable
  yarn install --immutable
  yarn build:client

Start:
  yarn prod
```

### Docker

```bash
docker build -t nodejs-wss-service-bridge .
docker run --rm   --env-file .env   -p 7860:7860   nodejs-wss-service-bridge
```

For VPS direct-TCP mode, publish every direct TCP port as well, for example `-p 6379:6379`.

---

## 7. Verify the relay before installing any target

Health check:

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

Important server paths:

```text
/tunnel                         target tunnel-client WebSocket
/tcp                            TCP-agent WebSocket
/__health                       health check
/__info                         deployment information
/<INSTALL_UUID>-install         target client installer
/<INSTALL_UUID>-client.js       standalone target client
/<INSTALL_UUID>-tcp-agent.js    standalone TCP agent
```

The tcp-agent artifact routes are available only when `TCP_AGENT_ALLOWED_PORTS` is non-empty.

---

## 8. Pick one use case

### I want to expose Rails / Node.js / a web API

Read:

**[Use case 1 — HTTP application](use-case-http.md)**

Typical result:

```text
Internet browser
      |
      v
https://tunnel.example.com
      |
      v
Nodejs-WSS-Service-Bridge
      |
   WSS /tunnel
      |
      v
private machine -> http://127.0.0.1:3000
```

### I want another application to use Redis / PostgreSQL

Read:

**[Use case 2 — TCP services](use-case-tcp.md)**

Choose:

- direct TCP when your relay is a VPS that can publish the service port;
- TCP-agent mode when your relay is a one-port PaaS.

### I want SSH / SCP / SFTP

Read:

**[Use case 3 — SSH](use-case-ssh.md)**

For a one-port PaaS the common topology is:

```text
ssh -> local tcp-agent -> WSS /tcp -> relay -> WSS /tunnel -> target -> sshd
```

---

## 9. How to recognize a successful target-client install

The target installer stores state under:

```text
~/.tunnel-client/
```

Check:

```bash
cat ~/.tunnel-client/client.pid
cat ~/.tunnel-client/client.ready
ps -fp "$(cat ~/.tunnel-client/client.pid)"
tail -n 50 ~/.tunnel-client/client.log
```

A healthy connected client satisfies:

```text
client.pid == client.ready == live client PID
```

The official installer detaches the client from the installer/notebook-cell lifecycle using `setsid` when available, `nohup`, and stdin from `/dev/null`.

That protects against the parent shell/cell ending. It does **not** make a process survive a complete runtime, container, VM, or host restart.

After a complete Kaggle/Colab/container restart, re-run the installer and rebuild any operating-system services that the runtime lost.

---

## 10. Important limitations

### HTTP WebSocket upgrade from the public application URL

The HTTP reverse proxy does **not** currently proxy arbitrary downstream HTTP `Upgrade: websocket` requests. Applications that require Socket.IO, Action Cable, or another browser-to-app WebSocket transport may need a different path or future project support.

Normal HTTP request/response traffic uses the HTTP tunnel.

### HTTP routing with several tunnel clients

Generic HTTP requests use an active connected client; `TUNNEL_ID` is designed for deterministic TCP target selection.

For a beginner HTTP deployment, keep:

```env
MAX_TUNNEL_CLIENTS=1
```

unless you specifically understand and need the multi-client behavior.

### TCP security

A tunnel does not replace Redis/PostgreSQL/application authentication.

Keep database authentication enabled. Prefer loopback bindings and the agent mode when practical. If using direct TCP, combine a firewall with `TCP_TUNNEL_ALLOWED_IPS`.

---

## 11. Troubleshooting order

When something fails, test from the relay outward:

```text
1. /__health returns ok?
2. target client is connected and ready?
3. correct TUNNEL_ID selected?
4. local target service is actually listening?
5. local tcp-agent is connected/listening when agent mode is used?
6. application-level credentials are valid?
```

Two errors that must not be confused:

```text
Tunnel target not connected: <id>
```

means the requested tunnel target is not registered.

```text
connect ECONNREFUSED 127.0.0.1:<port>
```

means the tunnel reached the target, but the target-local service is not listening on that host/port.

---

## 12. Advanced references

After the three beginner guides, these documents contain deeper operational detail:

- [TCP tunnel deployment and operations](tcp-tunnel.md)
- [External applications to TCP services](guide-external-app-to-tcp-services.md)
- [Final live / resilience qualification report](final-live-qualification-2026-08-22.md)
- [Cross-platform live acceptance report](live-cross-platform-acceptance-2026-08-24.md)
- [Testing guide](../TESTING.md)
