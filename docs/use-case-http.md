# Use Case 1 — Expose an HTTP Application

> 🌐 Language / Ngôn ngữ: **English** | [Tiếng Việt](use-case-http.vi.md)

Use this guide when a private machine runs an HTTP application such as Rails, Node.js, FastAPI, Gradio, a REST API, or a web UI and you want Internet users to reach it through your own Nodejs-WSS-Service-Bridge relay.

If you have not deployed the relay yet, start with [START-HERE.md](START-HERE.md).

---

## 1. What this use case does

Example target:

```text
Rails:   http://127.0.0.1:3000
Node.js: http://127.0.0.1:4000
FastAPI: http://127.0.0.1:8000
```

The target machine does not need a public inbound port.

```text
Browser / API client
       |
       | HTTPS
       v
https://tunnel.example.com
       |
       v
Nodejs-WSS-Service-Bridge relay
       |
       | authenticated WSS /tunnel
       v
target client
       |
       | local HTTP
       v
http://127.0.0.1:3000
```

The public HTTP request reaches the relay. The relay sends the request through the connected tunnel client, and the tunnel client forwards it to `TARGET_ORIGIN`.

---

## 2. Prerequisites

### Relay server

You already have:

- Nodejs-WSS-Service-Bridge running;
- a public HTTPS URL, for example `https://tunnel.example.com`;
- a pinned `INSTALL_UUID`;
- `TUNNEL_USERNAME` and `TUNNEL_PASSWORD`;
- `/__health` returning `ok`.

For a beginner deployment keep:

```env
MAX_TUNNEL_CLIENTS=1
```

Generic HTTP routing does not use `TUNNEL_ID` to select a specific target when several clients are connected.

### Target machine

The target needs:

- Node.js 20 or newer;
- `curl`;
- npm;
- GNU `mv -T` support for the official installer;
- an HTTP application listening on a local address.

Linux is the recommended target platform.

---

## 3. Confirm the local application first

Before installing the tunnel, make sure the application itself works locally.

Rails example:

```bash
curl -i http://127.0.0.1:3000/
```

Node.js example:

```bash
curl -i http://127.0.0.1:4000/
```

FastAPI example:

```bash
curl -i http://127.0.0.1:8000/
```

Do not continue until this succeeds.

If the application is not reachable locally, the tunnel cannot make it reachable remotely.

---

## 4. Install the tunnel client on the target machine

Example for Rails on port 3000:

```bash
export TUNNEL_SERVER_URL='https://tunnel.example.com'
export TUNNEL_USERNAME='<same-user-as-server>'
export TUNNEL_PASSWORD='<same-password-as-server>'
export TARGET_ORIGIN='http://127.0.0.1:3000'

curl -fsSL 'https://tunnel.example.com/<INSTALL_UUID>-install' | bash
```

Example for Node.js on port 4000:

```bash
export TUNNEL_SERVER_URL='https://tunnel.example.com'
export TUNNEL_USERNAME='<same-user-as-server>'
export TUNNEL_PASSWORD='<same-password-as-server>'
export TARGET_ORIGIN='http://127.0.0.1:4000'

curl -fsSL 'https://tunnel.example.com/<INSTALL_UUID>-install' | bash
```

The installer converts the public HTTP/HTTPS URL into the correct `ws://` or `wss://` `/tunnel` URL.

---

## 5. Expected successful install

A successful installer ends with output similar to:

```text
[tunnel] Client ready (PID: ...)
[tunnel] Logs: .../.tunnel-client/client.log
```

Verify:

```bash
cat ~/.tunnel-client/client.pid
cat ~/.tunnel-client/client.ready
ps -fp "$(cat ~/.tunnel-client/client.pid)"
tail -n 50 ~/.tunnel-client/client.log
```

Healthy state:

```text
client.pid == client.ready == live client PID
```

The log should show a successful connection rather than repeated authentication or reconnect failures.

---

## 6. Test through the Internet

From another machine:

```bash
curl -i https://tunnel.example.com/
```

Or open:

```text
https://tunnel.example.com/
```

in a browser.

The response should come from your private Rails/Node.js/FastAPI application.

If no tunnel client is connected, the relay root redirects to `/__info` instead.

---

## 7. What happens to request headers

The relay removes the original Host header before sending the request through the tunnel and supplies forwarding information such as:

```text
X-Forwarded-Host
X-Forwarded-For
X-Forwarded-Proto
```

Applications behind a reverse proxy may need to trust/configure forwarded headers according to their framework.

For Rails, review your application's host authorization and proxy settings if the app rejects the public host.

---

## 8. Public access and authentication

The tunnel credentials protect the **target client's WebSocket connection to the relay**.

They do **not** automatically add a login page to your proxied HTTP application.

If:

```text
https://tunnel.example.com/
```

is public, anyone who knows the URL can reach whatever your target application itself exposes.

For private applications, enable authentication in the application or place an authentication-aware reverse proxy/access-control layer in front of the relay.

---

## 9. Important WebSocket limitation

This project's HTTP reverse-proxy path currently rejects downstream HTTP Upgrade requests.

That means browser-to-application WebSocket transports such as some uses of:

- Rails Action Cable;
- Socket.IO WebSocket transport;
- custom WebSocket APIs;

are not automatically proxied through the generic HTTP application path.

Normal HTTP request/response traffic works.

If your application depends on WebSocket Upgrade, test that requirement explicitly before publishing the deployment.

---

## 10. Changing the target application

To move from port 3000 to port 4000, re-run the installer with the new `TARGET_ORIGIN`:

```bash
export TARGET_ORIGIN='http://127.0.0.1:4000'
curl -fsSL 'https://tunnel.example.com/<INSTALL_UUID>-install' | bash
```

The installer uses a transactional release model and readiness gate.

---

## 11. Stop and inspect the client

Follow logs:

```bash
tail -f ~/.tunnel-client/client.log
```

Stop:

```bash
PID="$(cat ~/.tunnel-client/client.pid)"
ps -fp "$PID"
kill "$PID"
```

Always verify the PID before manually killing it.

---

## 12. Kaggle / Colab / notebook lifecycle

The official installer uses `setsid` when available, `nohup`, and stdin from `/dev/null` so the tunnel client can survive the installer/notebook cell ending while the underlying runtime stays alive.

It does not survive a full runtime/container/host restart.

After a Kaggle or Colab runtime restart:

1. start the local HTTP application again;
2. re-run the tunnel installer;
3. verify `client.pid == client.ready == live PID`;
4. test the public URL again.

---

## 13. Troubleshooting

### Public URL shows the info page

Likely cause: no active tunnel client.

Check:

```bash
cat ~/.tunnel-client/client.ready
tail -n 100 ~/.tunnel-client/client.log
```

### Relay returns 503 tunnel_unavailable

The relay has no active target client.

Check credentials, Internet access from the target, and the client log.

### Target client is connected but requests fail

Test the local application directly:

```bash
curl -i http://127.0.0.1:3000/
```

If this fails, fix the local app first.

### Installer says authentication failed or never becomes ready

Confirm:

```text
TUNNEL_USERNAME
TUNNEL_PASSWORD
TUNNEL_SERVER_URL
INSTALL_UUID
```

match the relay configuration.

### Rails rejects the hostname

Review Rails Host Authorization and proxy settings. The public hostname is different from `127.0.0.1:3000`.

---

## 14. Acceptance checklist

Before sharing the URL publicly:

- [ ] `/__health` returns `ok`.
- [ ] local application works with `curl 127.0.0.1:<port>`.
- [ ] installer reports client ready.
- [ ] `client.pid` and `client.ready` match a live PID.
- [ ] public URL returns the target application.
- [ ] authentication/access policy for the HTTP application is intentional.
- [ ] any required WebSocket/Upgrade behavior has been tested separately.

