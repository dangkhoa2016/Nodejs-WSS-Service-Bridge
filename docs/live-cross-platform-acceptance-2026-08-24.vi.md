# Báo cáo Acceptance Live Đa nền tảng — HTTP, Redis và PostgreSQL

> 🌐 Language / Ngôn ngữ: [English](live-cross-platform-acceptance-2026-08-24.md) | **Tiếng Việt**

**Ngày:** 2026-08-24
**Repository:** `dangkhoa2016/Nodejs-WSS-Service-Bridge`
**Kết quả:** **PASS với giới hạn HTTP multi-target đã được ghi rõ**

## 1. Phạm vi

Báo cáo này ghi lại một đợt acceptance live đa nền tảng cho hai capability transport của Nodejs-WSS-Service-Bridge:

- HTTP reverse tunnel;
- generic TCP tunnel qua TCP agent.

Acceptance chủ động sử dụng ba môi trường độc lập:

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

và độc lập cho HTTP:

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

Acceptance lần này không dùng SSH làm application protocol được kiểm thử.

## 2. Danh tính môi trường

Các runtime identity quan sát được:

| Vai trò | Nền tảng | Hostname / identity |
| --- | --- | --- |
| TCP target | Google Colab | `d843bab35669` |
| HTTP target | Kaggle | `efd65ee02785` |
| External consumer | VSCode Linux / Codespaces | `codespaces-1ca1ba` |
| Public relay | Northflank | `https://tunnel.example.com` |

Public relay được cấu hình cho phép các target port TCP agent dùng trong qualification:

```env
TCP_AGENT_ALLOWED_PORTS=6379,5432,2222
```

## 3. Ma trận acceptance

| Acceptance | Kết quả |
| --- | --- |
| Northflank public health | PASS |
| Kaggle Node.js demo local HTTP | PASS |
| Kaggle HTTP target client connected | PASS |
| HTTP request từ Codespaces qua relay tới Kaggle | PASS |
| Xác minh identity/marker HTTP response | PASS |
| Colab Redis local service | PASS |
| Colab PostgreSQL local service | PASS |
| Colab target client `TUNNEL_ID=colab-tcp` | PASS |
| Codespaces tcp-agent `16379 -> colab-tcp:6379` | PASS |
| Codespaces tcp-agent `15432 -> colab-tcp:5432` | PASS |
| Redis `PING` qua WSS | PASS |
| Redis read/write round trip qua WSS | PASS |
| PostgreSQL SELECT qua WSS | PASS |
| PostgreSQL INSERT + SELECT round trip qua WSS | PASS |
| Nhận diện đúng lỗi target-port allowlist | PASS |
| Target và agent tự reconnect sau relay redeploy | PASS observed |
| HTTP deterministic routing giữa nhiều `/tunnel` clients | KHÔNG HỖ TRỢ / limitation đã xác nhận |

Tổng thể:

```text
CROSS-PLATFORM HTTP + TCP LIVE ACCEPTANCE = PASS
```

Kết quả PASS áp dụng cho các path được hỗ trợ liệt kê ở trên. Nó không ghi đè limitation HTTP multi-target ở mục 9.

## 4. HTTP acceptance — Node.js demo trên Kaggle

Một Node.js HTTP server tối giản chạy trên Kaggle target:

```text
127.0.0.1:3000
```

Server trả về JSON marker riêng của runtime.

Request từ Codespaces đi qua public relay:

```text
Codespaces
  -> HTTPS
  -> Northflank relay
  -> WSS /tunnel
  -> Kaggle efd65ee02785
  -> Node.js 127.0.0.1:3000
```

trả về:

```http
HTTP/2 200
content-type: application/json; charset=utf-8
```

với application payload:

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

Hostname và marker khớp với private Kaggle process đã quan sát trước khi tunnel.

Kết quả: **PASS**.

## 5. Redis acceptance — Colab qua generic TCP

Redis chỉ chạy trên loopback của Colab:

```text
127.0.0.1:6379
```

Codespaces consumer bên ngoài kết nối local tới:

```text
127.0.0.1:16379
```

với route:

```text
16379 -> colab-tcp:6379
```

Đường truyền end-to-end:

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

Các command/response quan sát được:

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

Log tcp-agent cuối cùng cho thấy stream registration và connection acknowledgement thành công cho target port `6379` và target ID `colab-tcp`.

Kết quả: **PASS**.

## 6. PostgreSQL acceptance — Colab qua generic TCP

PostgreSQL chạy tại:

```text
127.0.0.1:5432
```

Codespaces consumer bên ngoài dùng `psql` kết nối tới:

```text
127.0.0.1:15432
```

với route:

```text
15432 -> colab-tcp:5432
```

Acceptance trước tiên đọc evidence đã tồn tại trong database trên Colab:

```text
database: tunnel_demo
user:     tunnel_demo

source:
colab-tcp

value:
postgres-through-wss-from-colab
```

Sau đó Codespaces insert thêm row qua tunnel và đọc lại cả hai row thành công:

```text
1 | colab-tcp  | postgres-through-wss-from-colab
2 | codespaces | postgres-roundtrip-through-wss
```

Log tcp-agent ghi nhận connection acknowledgement thành công cho target port `5432` và target ID `colab-tcp`.

Kết quả: **PASS**.

## 7. Bằng chứng failure domain — target-port allowlist

Trước khi relay allowlist được cập nhật, cùng các request Redis và PostgreSQL đã tới tcp-agent nhưng bị relay từ chối với:

```text
Port not allowed
```

Chuỗi quan sát được:

```text
local_connect_received
tcp_connect_sent
connect_rejected ... message=Port not allowed
```

Cùng lúc đó:

- Colab target client vẫn connected;
- Redis local vẫn trả `PONG`;
- PostgreSQL local vẫn trả `SELECT 1`.

Do đó lỗi được phân loại chính xác là relay policy, không phải target-service failure và cũng không phải tunnel architecture defect.

Sau khi cập nhật relay thành:

```env
TCP_AGENT_ALLOWED_PORTS=6379,5432,2222
```

và redeploy, cả hai database route đều PASS mà không phải thay đổi Redis, PostgreSQL, topology Colab target hoặc thiết kế tcp-agent routing.

## 8. Quan sát relay redeploy và automatic reconnect

Trong lúc Northflank redeploy, các client đang connected trước tiên nhận orderly shutdown:

```text
disconnected code=1001 reason=Server shutting down
```

Trong lúc service khởi động, các reconnect attempt tạm thời nhận HTTP `503`.

Các client và tcp-agent áp dụng retry/backoff rồi tự phục hồi:

```text
connected
```

Quan sát này xảy ra với:

- Colab target client;
- Kaggle HTTP target client;
- Codespaces tcp-agent.

Không cần manual process restart cho các reconnect đó.

Đây là resilience observation từ acceptance run, không thay thế dedicated live/resilience qualification report.

## 9. Limitation đã xác nhận — generic HTTP với nhiều target client

Acceptance cũng tái hiện limitation HTTP multi-target đã được tài liệu hóa.

Khi đồng thời có hai target client connected:

```text
colab-tcp
kaggle-2
```

generic HTTP path không chọn target theo `TUNNEL_ID`.

Vì vậy request tới `/acceptance` có thể được giao cho Colab target, trong khi HTTP `TARGET_ORIGIN` của Colab trong TCP-only test này cố ý trỏ tới một local port không dùng. Kết quả quan sát được:

```text
HTTP 502
```

Sau khi dừng Colab target client để Kaggle trở thành HTTP-capable target duy nhất, cùng public request lập tức trả:

```text
HTTP/2 200
```

và đúng Kaggle application payload.

Điều này xác nhận operational guidance hiện tại:

- `TUNNEL_ID` cung cấp deterministic target selection cho generic TCP path;
- generic HTTP path chọn một active connected client thay vì route HTTP theo `TUNNEL_ID`;
- deployment HTTP đơn giản nên giữ một active target client, ví dụ bằng `MAX_TUNNEL_CLIENTS=1`, trừ khi tương lai bổ sung explicit HTTP target routing.

Không được mô tả hành vi hiện tại như deterministic multi-target HTTP support.

## 10. Ghi chú security và test-only

Các test service vẫn bind loopback trên target host.

PostgreSQL demo dùng một test-only local authentication arrangement cho dedicated acceptance role. Cách này phù hợp với qualification có kiểm soát và chỉ loopback, nhưng không phải production guidance.

Production deployment vẫn nên dùng:

- PostgreSQL authentication bình thường;
- Redis authentication/ACL khi phù hợp;
- loopback binding khi dùng tunnel client;
- tunnel credential mạnh;
- HTTPS/WSS cho public relay;
- tập `TCP_AGENT_ALLOWED_PORTS` nhỏ nhất thực tế cần dùng.

Tunnel không cần expose service password; nó vận chuyển byte stream của protocol bên dưới.

## 11. Kết luận

Live acceptance này chứng minh Nodejs-WSS-Service-Bridge không chỉ giới hạn ở các ví dụ SSH.

Cùng một project đã vận chuyển thành công:

- một HTTP application thật từ Kaggle;
- Redis TCP traffic từ Google Colab;
- PostgreSQL TCP traffic từ Google Colab;
- application traffic được consume từ một Linux/Codespaces host độc lập.

Các capability đã xác minh vì vậy là:

```text
HTTP reverse tunnel
+
generic Redis TCP
+
generic PostgreSQL TCP
+
deterministic TCP target selection bằng TUNNEL_ID
+
cross-platform WSS transport
```

Run này cũng tạo ra negative evidence hữu ích:

- target-port policy failure có thể phân biệt với target/service failure;
- HTTP multi-target routing không deterministic theo `TUNNEL_ID` và vẫn là một limitation đã được ghi rõ.

Với topology và các supported path đã kiểm thử:

```text
CROSS-PLATFORM LIVE ACCEPTANCE = PASS
```
