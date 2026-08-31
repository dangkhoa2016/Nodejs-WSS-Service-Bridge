# Cross-Platform Live Acceptance Report — HTTP, Redis, and PostgreSQL

> 🌐 Language / Ngôn ngữ: **English** | [Tiếng Việt](live-cross-platform-acceptance-2026-08-24.vi.md)

**Date:** 2026-08-24
**Repository:** `dangkhoa2016/Nodejs-WSS-Service-Bridge`
**Result:** **PASS with a documented HTTP multi-target limitation**

## 1. Scope

This report records a live cross-platform acceptance of the two transport capabilities exposed by Nodejs-WSS-Service-Bridge:

- HTTP reverse tunneling;
- generic TCP tunneling through the TCP agent.

The acceptance deliberately used three independent environments:

```text
Google Colab
  Redis      127.0.0.1:6379
  PostgreSQL 127.0.0.1:5432
  TUNNEL_ID=colab-tcp
        |
        | WSS /tunnel
        v
Northflank relay
        ^
        | WSS /tcp
        |
VSCode Linux / Codespaces
  local tcp-agent
  127.0.0.1:16379 -> colab-tcp:6379
  127.0.0.1:15432 -> colab-tcp:5432
```

and, independently for HTTP:

```text
Kaggle
  Node.js HTTP demo
  127.0.0.1:3000
  TUNNEL_ID=kaggle-2
        |
        | WSS /tunnel
        v
Northflank relay
        ^
        | HTTPS
        |
VSCode Linux / Codespaces
```

This acceptance did not use SSH as the application protocol under test.

## 2. Environment identity

Observed runtime identities:

| Role | Platform | Hostname / identity |
| --- | --- | --- |
| TCP target | Google Colab | `d843bab35669` |
| HTTP target | Kaggle | `efd65ee02785` |
| External consumer | VSCode Linux / Codespaces | `codespaces-1ca1ba` |
| Public relay | Northflank | `https://tunnel.example.com` |

The public relay was configured to allow the TCP agent target ports used in this qualification:

```env
TCP_AGENT_ALLOWED_PORTS=6379,5432,2222
```

## 3. Acceptance matrix

| Acceptance | Result |
| --- | --- |
| Northflank public health | PASS |
| Kaggle Node.js demo local HTTP | PASS |
| Kaggle HTTP target client connected | PASS |
| HTTP request from Codespaces through relay to Kaggle | PASS |
| HTTP response identity/marker verification | PASS |
| Colab Redis local service | PASS |
| Colab PostgreSQL local service | PASS |
| Colab target client `TUNNEL_ID=colab-tcp` | PASS |
| Codespaces tcp-agent `16379 -> colab-tcp:6379` | PASS |
| Codespaces tcp-agent `15432 -> colab-tcp:5432` | PASS |
| Redis `PING` through WSS | PASS |
| Redis read/write round trip through WSS | PASS |
| PostgreSQL SELECT through WSS | PASS |
| PostgreSQL INSERT + SELECT round trip through WSS | PASS |
| Target-port allowlist failure correctly identified | PASS |
| Target and agent automatic reconnect after relay redeploy | PASS observed |
| HTTP deterministic routing among multiple `/tunnel` clients | NOT SUPPORTED / confirmed limitation |

Overall:

```text
CROSS-PLATFORM HTTP + TCP LIVE ACCEPTANCE = PASS
```

The PASS result applies to the supported paths listed above. It does not override the HTTP multi-target limitation documented in section 9.

## 4. HTTP acceptance — Kaggle Node.js demo

A minimal Node.js HTTP server ran on the Kaggle target:

```text
127.0.0.1:3000
```

The server returned a runtime-specific JSON marker.

A request issued from Codespaces through the public relay:

```text
Codespaces
  -> HTTPS
  -> Northflank relay
  -> WSS /tunnel
  -> Kaggle efd65ee02785
  -> Node.js 127.0.0.1:3000
```

returned:

```http
HTTP/2 200
content-type: application/json; charset=utf-8
```

with the application payload:

```json
{
  "ok": true,
  "demo": "Nodejs-WSS-Service-Bridge HTTP acceptance",
  "hostname": "efd65ee02785",
  "node": "v24.21.0",
  "method": "GET",
  "url": "/acceptance",
  "marker": "c643941563a362af486e1235cdab8b08073460b64911debda8f7057bc7f85170"
}
```

The hostname and marker matched the private Kaggle process observed before tunneling.

Result: **PASS**.

## 5. Redis acceptance — Colab through generic TCP

Redis ran only on the Colab loopback interface:

```text
127.0.0.1:6379
```

The external Codespaces consumer connected locally to:

```text
127.0.0.1:16379
```

with the route:

```text
16379 -> colab-tcp:6379
```

End-to-end path:

```text
Codespaces :16379
  -> local tcp-agent
  -> WSS /tcp
  -> Northflank relay
  -> WSS /tunnel
  -> Colab colab-tcp
  -> 127.0.0.1:6379
  -> Redis
```

Observed commands and responses:

```text
PING
=> PONG

GET tunnel:acceptance
=> redis-through-wss-from-colab

SET tunnel:roundtrip codespaces-through-wss
=> OK

GET tunnel:roundtrip
=> codespaces-through-wss
```

The final tcp-agent log showed successful stream registration and connection acknowledgements for target port `6379` and target ID `colab-tcp`.

Result: **PASS**.

## 6. PostgreSQL acceptance — Colab through generic TCP

PostgreSQL ran on:

```text
127.0.0.1:5432
```

The external Codespaces consumer connected with `psql` to:

```text
127.0.0.1:15432
```

with the route:

```text
15432 -> colab-tcp:5432
```

The acceptance first read evidence that already existed on the Colab database:

```text
database: tunnel_demo
user:     tunnel_demo

source:
colab-tcp

value:
postgres-through-wss-from-colab
```

Codespaces then inserted a second row through the tunnel and read both rows back:

```text
1 | colab-tcp  | postgres-through-wss-from-colab
2 | codespaces | postgres-roundtrip-through-wss
```

The tcp-agent log recorded a successful connection acknowledgement for target port `5432` and target ID `colab-tcp`.

Result: **PASS**.

## 7. Failure-domain proof — target-port allowlist

Before the relay allowlist was updated, the same Redis and PostgreSQL requests reached the tcp-agent and were rejected by the relay with:

```text
Port not allowed
```

The observed sequence was:

```text
local_connect_received
tcp_connect_sent
connect_rejected ... message=Port not allowed
```

At the same time:

- the Colab target client remained connected;
- Redis still returned local `PONG`;
- PostgreSQL still returned local `SELECT 1`.

The issue was therefore correctly classified as relay policy, not a target-service failure and not a tunnel architecture defect.

After updating the relay to:

```env
TCP_AGENT_ALLOWED_PORTS=6379,5432,2222
```

and redeploying, both database routes passed without changes to Redis, PostgreSQL, the Colab target topology, or the tcp-agent routing design.

## 8. Relay redeploy and automatic reconnect observation

During the Northflank redeploy, the connected clients observed an orderly shutdown first:

```text
disconnected code=1001 reason=Server shutting down
```

During service startup, reconnect attempts temporarily received HTTP `503`.

The clients and tcp-agent applied retry/backoff behavior and later recovered automatically:

```text
connected
```

This was observed for:

- the Colab target client;
- the Kaggle HTTP target client;
- the Codespaces tcp-agent.

No manual process restart was required for those reconnects.

This is an observed resilience result from the acceptance run, not a replacement for the dedicated live/resilience qualification report.

## 9. Confirmed limitation — generic HTTP with multiple target clients

The acceptance also reproduced the documented HTTP multi-target limitation.

When both of these target clients were connected simultaneously:

```text
colab-tcp
kaggle-2
```

the generic HTTP path did not select a target by `TUNNEL_ID`.

A request to `/acceptance` could therefore be assigned to the Colab target, whose HTTP `TARGET_ORIGIN` for this TCP-only test intentionally pointed to an unused local port. The observed result was:

```text
HTTP 502
```

After stopping the Colab target client so that Kaggle was the only active HTTP-capable target, the same public request immediately returned:

```text
HTTP/2 200
```

and the expected Kaggle application payload.

This confirms the existing operational guidance:

- `TUNNEL_ID` provides deterministic target selection for the generic TCP path;
- the generic HTTP path selects an active connected client rather than routing HTTP by `TUNNEL_ID`;
- a simple HTTP deployment should keep a single active target client, for example with `MAX_TUNNEL_CLIENTS=1`, unless explicit HTTP target routing is added in the future.

This behavior must not be presented as deterministic multi-target HTTP support.

## 10. Security and test-only notes

The test services remained loopback-bound on the target hosts.

The PostgreSQL demo used a test-only local authentication arrangement for the dedicated acceptance role. This was acceptable for the controlled loopback-only qualification, but it is not production guidance.

Production deployments should continue to use:

- normal PostgreSQL authentication;
- Redis authentication/ACLs where appropriate;
- loopback binding when using the tunnel client;
- strong tunnel credentials;
- HTTPS/WSS for the public relay;
- the smallest practical `TCP_AGENT_ALLOWED_PORTS` set.

No service password needs to be exposed by the tunnel itself; the tunnel transports the underlying protocol byte stream.

## 11. Conclusion

This live acceptance proved that Nodejs-WSS-Service-Bridge is not limited to SSH transport examples.

The same project successfully carried:

- a real HTTP application from Kaggle;
- Redis TCP traffic from Google Colab;
- PostgreSQL TCP traffic from Google Colab;
- application traffic consumed from an independent Linux/Codespaces host.

The validated capabilities are therefore:

```text
HTTP reverse tunnel
+
generic Redis TCP
+
generic PostgreSQL TCP
+
deterministic TCP target selection by TUNNEL_ID
+
cross-platform WSS transport
```

The run also produced useful negative evidence:

- target-port policy failures are distinguishable from target/service failures;
- HTTP multi-target routing is not deterministic by `TUNNEL_ID` and remains a documented limitation.

For the tested topology and supported paths:

```text
CROSS-PLATFORM LIVE ACCEPTANCE = PASS
```
