# Use Case 2 — Share Redis, PostgreSQL, and Other TCP Services

> 🌐 Language / Ngôn ngữ: **English** | [Tiếng Việt](use-case-tcp.vi.md)

Use this guide when a private target machine runs Redis, PostgreSQL, MySQL, or another TCP service and another application must connect to it through your Nodejs-WSS-Service-Bridge relay.

If you have not deployed the relay yet, start with [START-HERE.md](START-HERE.md).

---

## 1. Two TCP deployment modes

Nodejs-WSS-Service-Bridge supports two ways to carry raw TCP traffic.

### Mode A — direct TCP

Use this when the relay runs on a VPS or network where you can publish extra TCP ports.

```text
application
    |
    | TCP server.example.com:6379
    v
Nodejs-WSS-Service-Bridge relay
    |
    | WSS /tunnel
    v
target client
    |
    | 127.0.0.1:6379
    v
Redis
```

The relay itself listens on the service port.

### Mode B — TCP agent

Use this when the relay runs on a one-public-port PaaS such as Northflank/Render/Railway.

```text
application
    |
    | TCP 127.0.0.1:6379
    v
tcp-agent on application host
    |
    | WSS /tcp
    v
Nodejs-WSS-Service-Bridge relay
    |
    | WSS /tunnel
    v
target client
    |
    | 127.0.0.1:6379
    v
Redis
```

No Redis/PostgreSQL port is opened on the public relay.

For most PaaS users, **agent mode is recommended**.

---

## 2. What services can be tunneled

The TCP tunnel does not need to understand the application protocol. It carries a bidirectional TCP byte stream.

Typical examples:

```text
Redis       6379
PostgreSQL  5432
MySQL       3306
SSH         22 or 2222
other TCP services
```

Keep the service's own authentication enabled. The tunnel is transport, not a replacement for database/application authentication.

### Qdrant note

Qdrant exposes both an HTTP REST API and a gRPC API. In a default local setup, the REST API is typically on port `6333` and gRPC on `6334`.

- If your client uses Qdrant REST/HTTP, the [HTTP application guide](use-case-http.md) may be the simpler fit.
- If your client uses Qdrant gRPC, treat it as a TCP service and allow/route port `6334` through the TCP tunnel.

Keep Qdrant's own authentication/security configuration enabled when exposing it beyond the local machine.

---

# Part A — Direct TCP on a VPS

## 3. Configure the relay

Start from:

```bash
cp .env.example.vps .env
```

Example: expose Redis and PostgreSQL:

```env
INSTALL_UUID=<stable-uuid>
TUNNEL_USERNAME=<tunnel-user>
TUNNEL_PASSWORD=<long-random-secret>

MAX_TUNNEL_CLIENTS=1

TCP_TUNNEL_HOST=127.0.0.1
TCP_TUNNEL_PORTS=6379,5432
TCP_TUNNEL_BIND_HOST=0.0.0.0

# Replace this with the real consumer IP/CIDR.
TCP_TUNNEL_ALLOWED_IPS=203.0.113.10

TCP_CLIENT_ALLOWED_HOSTS=127.0.0.1
```

Also restrict these ports in your VPS firewall/security group.

**Do not leave a public Redis/PostgreSQL listener open to the world.**

---

## 4. Verify the services on the target machine

On the private target:

Redis:

```bash
redis-cli -h 127.0.0.1 -p 6379 ping
```

Expected:

```text
PONG
```

PostgreSQL:

```bash
PGPASSWORD='<password>' psql -h 127.0.0.1 -p 5432 -U '<user>' -d '<database>' -c 'SELECT 1'
```

Do not continue until the local service works.

---

## 5. Install the target tunnel client

For the common loopback case:

```bash
export TUNNEL_SERVER_URL='https://tunnel.example.com'
export TUNNEL_USERNAME='<tunnel-user>'
export TUNNEL_PASSWORD='<long-random-secret>'

curl -fsSL 'https://tunnel.example.com/<INSTALL_UUID>-install' | bash
```

The TCP path uses the target's `127.0.0.1:<requested-port>`.

Verify:

```bash
cat ~/.tunnel-client/client.ready
tail -n 100 ~/.tunnel-client/client.log
```

---

## 6. Connect from the allowed consumer machine

Redis:

```bash
REDISCLI_AUTH='<redis-password>' redis-cli -h tunnel.example.com -p 6379 ping
```

PostgreSQL:

```bash
PGPASSWORD='<password>' psql -h tunnel.example.com -p 5432 -U '<user>' -d '<database>' -c 'SELECT 1'
```

Direct mode does not remap ports: relay port 6379 targets port 6379; relay port 5432 targets port 5432.

---

# Part B — TCP agent on a one-port PaaS

## 7. Configure the relay for agent mode

Start from:

```bash
cp .env.example.single-port .env
```

Example:

```env
INSTALL_UUID=<stable-uuid>
TUNNEL_USERNAME=<tunnel-user>
TUNNEL_PASSWORD=<long-random-secret>

MAX_TUNNEL_CLIENTS=1

TCP_TUNNEL_PORTS=
TCP_TUNNEL_HOST=127.0.0.1
TCP_CLIENT_ALLOWED_HOSTS=127.0.0.1

TCP_AGENT_PATH=/tcp
TCP_AGENT_ALLOWED_PORTS=6379,5432

# Optional: separate credentials for agents.
TCP_AGENT_USERNAME=<agent-user>
TCP_AGENT_PASSWORD=<agent-secret>
```

The public platform only needs the normal HTTPS port for the relay.

---

## 8. Install the target/service machine

The target machine owns Redis/PostgreSQL.

The simplest generic installer:

```bash
export TUNNEL_SERVER_URL='https://tunnel.example.com'
export TUNNEL_USERNAME='<tunnel-user>'
export TUNNEL_PASSWORD='<long-random-secret>'

curl -fsSL 'https://tunnel.example.com/<INSTALL_UUID>-install' | bash
```

For a production Linux service-host workflow, the repository also includes:

```text
scripts/setup-service-host.sh
```

It provides transactional upgrades, rollback, release retention, and stronger process-safety checks. See [the advanced external-app guide](guide-external-app-to-tcp-services.md).

---

## 9. Install the tcp-agent on the application machine

The application machine is where Rails/Node.js/another consumer runs.

For the existing transactional installer, clone the repository or copy the script from a trusted release, then:

```bash
export SERVER_HOST='tunnel.example.com'
export INSTALL_UUID='<stable-uuid>'

export AGENT_USERNAME='<agent-user>'
export AGENT_PASSWORD='<agent-secret>'

export AGENT_PORTS='6379,5432'

./scripts/setup-application-host.sh
```

The agent listens only on loopback by default.

Expected local listeners:

```text
127.0.0.1:6379
127.0.0.1:5432
```

Verify agent state:

```bash
cat ~/.tcp-agent/agent.pid
cat ~/.tcp-agent/agent.ready
ps -fp "$(cat ~/.tcp-agent/agent.pid)"
tail -n 100 ~/.tcp-agent/agent.log
```

Healthy agent:

```text
agent.pid == agent.ready == live agent PID
```

---

## 10. Point your application at loopback

In agent mode, the consumer does **not** connect to `tunnel.example.com:6379`.

It connects to its own local tcp-agent.

Redis URL:

```text
redis://<user>:<password>@127.0.0.1:6379
```

PostgreSQL URL:

```text
postgresql://<user>:<password>@127.0.0.1:5432/<database>
```

Examples:

```bash
REDISCLI_AUTH='<redis-password>' redis-cli -h 127.0.0.1 -p 6379 ping

PGPASSWORD='<password>' psql -h 127.0.0.1 -p 5432 -U '<user>' -d '<database>' -c 'SELECT 1'
```

The tcp-agent sends those connections through `WSS /tcp` to the relay.

---

## 11. Multiple application hosts

You can install an independent tcp-agent on application machines B, C, D, etc.

Each machine may listen on the same local ports because each has its own loopback interface:

```text
B -> 127.0.0.1:6379
C -> 127.0.0.1:6379
D -> 127.0.0.1:6379
```

All can reach the same Redis target through the relay.

Use separate Redis ACL users/PostgreSQL roles for different consumers when you need per-consumer authorization and revocation.

---

## 12. Multiple tunnel targets

When more than one target tunnel client is connected:

```env
MAX_TUNNEL_CLIENTS=2
```

each target should register a unique `TUNNEL_ID`.

A TCP-agent request must identify the target; otherwise the relay rejects an ambiguous request.

The standalone tcp-agent supports:

```env
TARGET_TUNNEL_ID=kaggle-1
```

with `AGENT_PORTS`, or explicit route mapping:

```env
AGENT_ROUTES=16379=kaggle-1:6379,26379=kaggle-2:6379
```

`AGENT_PORTS` and `AGENT_ROUTES` are mutually exclusive.

The route syntax is:

```text
localPort=targetTunnelId:targetPort
```

This is advanced configuration; start with a single target first.

---

## 13. Security rules

### Direct mode

Use all of:

- database/service authentication;
- `TCP_TUNNEL_ALLOWED_IPS`;
- host firewall/security group;
- TLS at the database/application layer when required.

The direct relay listener is raw TCP; it does not automatically add TLS to Redis/PostgreSQL.

### Agent mode

Prefer:

```env
AGENT_BIND_HOST=127.0.0.1
```

The agent refuses non-loopback binding unless `ALLOW_REMOTE_AGENT_BIND=1` is explicitly set.

Use WSS for the public relay.

---

## 14. Troubleshooting

### `Tunnel target not connected: ...`

The requested `TUNNEL_ID` is not currently registered.

Check the target client's log and target ID.

### `Target tunnel ID is required when multiple tunnel clients are connected`

More than one target is active and the tcp-agent did not select one.

Use `TARGET_TUNNEL_ID` or `AGENT_ROUTES`.

### `connect ECONNREFUSED 127.0.0.1:6379`

The relay reached the correct target, but Redis is not listening there.

On the target:

```bash
ss -ltn | grep ':6379'
redis-cli -h 127.0.0.1 -p 6379 ping
```

### tcp-agent is not ready

Check:

```bash
tail -n 100 ~/.tcp-agent/agent.log
```

Typical causes:

- wrong agent credentials;
- local port already in use;
- relay `TCP_AGENT_ALLOWED_PORTS` does not include the requested target port;
- `/tcp` is disabled;
- TLS/trusted-proxy policy mismatch.

### Redis/PostgreSQL authentication fails

The tunnel worked far enough to reach the service. Fix Redis ACL/PostgreSQL credentials rather than changing tunnel routing.

---

## 15. Acceptance checklist

- [ ] relay `/__health` returns `ok`;
- [ ] target Redis/PostgreSQL works locally;
- [ ] target tunnel client is ready;
- [ ] agent is ready when using agent mode;
- [ ] correct target is selected when multiple tunnel clients exist;
- [ ] Redis `PING` or PostgreSQL `SELECT 1` succeeds through the tunnel;
- [ ] database authentication remains enabled;
- [ ] direct-mode firewall/IP allowlist is restrictive.

