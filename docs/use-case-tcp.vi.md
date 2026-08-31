# Use Case 2 — Chia sẻ Redis, PostgreSQL và dịch vụ TCP

> 🌐 Language / Ngôn ngữ: [English](use-case-tcp.md) | **Tiếng Việt**

Dùng guide này khi một target machine private chạy Redis, PostgreSQL, MySQL hoặc TCP service khác và một ứng dụng khác cần kết nối tới service đó qua Nodejs-WSS-Service-Bridge relay của bạn.

Nếu chưa deploy relay, hãy bắt đầu từ [START-HERE.vi.md](START-HERE.vi.md).

---

## 1. Hai mode TCP

Nodejs-WSS-Service-Bridge hỗ trợ hai cách truyền raw TCP.

### Mode A — direct TCP

Dùng khi relay chạy trên VPS/network cho phép publish thêm TCP port.

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

Relay tự listen service port.

### Mode B — TCP agent

Dùng khi relay chạy trên PaaS chỉ có một public port như Northflank/Render/Railway.

```text
application
    |
    | TCP 127.0.0.1:6379
    v
tcp-agent trên application host
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

Không cần mở Redis/PostgreSQL port trên public relay.

Với đa số PaaS, **agent mode được khuyến nghị**.

---

## 2. Có thể tunnel service nào

TCP tunnel không cần hiểu application protocol. Nó truyền bidirectional TCP byte stream.

Ví dụ:

```text
Redis       6379
PostgreSQL  5432
MySQL       3306
SSH         22 hoặc 2222
các TCP service khác
```

Luôn giữ authentication riêng của service. Tunnel là transport, không thay thế database/application authentication.

### Ghi chú về Qdrant

Qdrant có cả HTTP REST API và gRPC API. Với local setup mặc định, REST thường dùng port `6333` và gRPC dùng port `6334`.

- Nếu client dùng Qdrant REST/HTTP, [HTTP application guide](use-case-http.vi.md) có thể đơn giản hơn.
- Nếu client dùng Qdrant gRPC, hãy xem nó như một TCP service và allow/route port `6334` qua TCP tunnel.

Vẫn phải giữ authentication/security riêng của Qdrant khi expose ra ngoài máy local.

---

# Phần A — Direct TCP trên VPS

## 3. Cấu hình relay

Bắt đầu từ:

```bash
cp .env.example.vps .env
```

Ví dụ expose Redis và PostgreSQL:

```env
INSTALL_UUID=<stable-uuid>
TUNNEL_USERNAME=<tunnel-user>
TUNNEL_PASSWORD=<long-random-secret>

MAX_TUNNEL_CLIENTS=1

TCP_TUNNEL_HOST=127.0.0.1
TCP_TUNNEL_PORTS=6379,5432
TCP_TUNNEL_BIND_HOST=0.0.0.0

# Thay bằng consumer IP/CIDR thật.
TCP_TUNNEL_ALLOWED_IPS=203.0.113.10

TCP_CLIENT_ALLOWED_HOSTS=127.0.0.1
```

Đồng thời giới hạn các port này trong firewall/security group của VPS.

**Không để public Redis/PostgreSQL listener mở cho toàn Internet.**

---

## 4. Kiểm tra service trên target machine

Redis:

```bash
redis-cli -h 127.0.0.1 -p 6379 ping
```

Mong đợi:

```text
PONG
```

PostgreSQL:

```bash
PGPASSWORD='<password>' psql -h 127.0.0.1 -p 5432 -U '<user>' -d '<database>' -c 'SELECT 1'
```

Chỉ tiếp tục khi local service hoạt động.

---

## 5. Cài target tunnel client

Cho trường hợp loopback thông thường:

```bash
export TUNNEL_SERVER_URL='https://tunnel.example.com'
export TUNNEL_USERNAME='<tunnel-user>'
export TUNNEL_PASSWORD='<long-random-secret>'

curl -fsSL 'https://tunnel.example.com/<INSTALL_UUID>-install' | bash
```

TCP path sẽ dùng `127.0.0.1:<requested-port>` trên target.

Kiểm tra:

```bash
cat ~/.tunnel-client/client.ready
tail -n 100 ~/.tunnel-client/client.log
```

---

## 6. Kết nối từ consumer được phép

Redis:

```bash
REDISCLI_AUTH='<redis-password>' redis-cli -h tunnel.example.com -p 6379 ping
```

PostgreSQL:

```bash
PGPASSWORD='<password>' psql -h tunnel.example.com -p 5432 -U '<user>' -d '<database>' -c 'SELECT 1'
```

Direct mode không remap port: relay 6379 tới target 6379; relay 5432 tới target 5432.

---

# Phần B — TCP agent trên PaaS một public port

## 7. Cấu hình relay cho agent mode

Bắt đầu từ:

```bash
cp .env.example.single-port .env
```

Ví dụ:

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

# Tùy chọn: credential riêng cho agent.
TCP_AGENT_USERNAME=<agent-user>
TCP_AGENT_PASSWORD=<agent-secret>
```

Platform public chỉ cần HTTPS port bình thường của relay.

---

## 8. Cài target/service machine

Target machine là nơi chạy Redis/PostgreSQL.

Installer generic đơn giản:

```bash
export TUNNEL_SERVER_URL='https://tunnel.example.com'
export TUNNEL_USERNAME='<tunnel-user>'
export TUNNEL_PASSWORD='<long-random-secret>'

curl -fsSL 'https://tunnel.example.com/<INSTALL_UUID>-install' | bash
```

Đối với production Linux service-host workflow, repository còn có:

```text
scripts/setup-service-host.sh
```

Script này có transactional upgrade, rollback, release retention và process-safety checks mạnh hơn. Xem [advanced external-app guide](guide-external-app-to-tcp-services.vi.md).

---

## 9. Cài tcp-agent trên application machine

Application machine là nơi Rails/Node.js/consumer khác chạy.

Với transactional installer hiện có, clone repository hoặc copy script từ trusted release rồi chạy:

```bash
export SERVER_HOST='tunnel.example.com'
export INSTALL_UUID='<stable-uuid>'

export AGENT_USERNAME='<agent-user>'
export AGENT_PASSWORD='<agent-secret>'

export AGENT_PORTS='6379,5432'

./scripts/setup-application-host.sh
```

Agent mặc định chỉ listen loopback.

Local listener mong đợi:

```text
127.0.0.1:6379
127.0.0.1:5432
```

Kiểm tra agent:

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

## 10. Cho application kết nối loopback

Trong agent mode, consumer **không** kết nối tới `tunnel.example.com:6379`.

Nó kết nối tcp-agent local.

Redis URL:

```text
redis://<user>:<password>@127.0.0.1:6379
```

PostgreSQL URL:

```text
postgresql://<user>:<password>@127.0.0.1:5432/<database>
```

Ví dụ:

```bash
REDISCLI_AUTH='<redis-password>' redis-cli -h 127.0.0.1 -p 6379 ping

PGPASSWORD='<password>' psql -h 127.0.0.1 -p 5432 -U '<user>' -d '<database>' -c 'SELECT 1'
```

tcp-agent gửi connection qua `WSS /tcp` tới relay.

---

## 11. Nhiều application host

Có thể cài tcp-agent độc lập trên B, C, D...

Mỗi máy có thể dùng cùng local port vì chúng có loopback riêng:

```text
B -> 127.0.0.1:6379
C -> 127.0.0.1:6379
D -> 127.0.0.1:6379
```

Tất cả đều có thể tới cùng Redis target qua relay.

Khi cần per-consumer authorization/revocation, hãy dùng Redis ACL user/PostgreSQL role riêng cho từng consumer.

---

## 12. Nhiều tunnel target

Khi có nhiều target tunnel client:

```env
MAX_TUNNEL_CLIENTS=2
```

mỗi target nên có `TUNNEL_ID` duy nhất.

TCP-agent request phải chỉ target; nếu không relay từ chối vì ambiguous.

Standalone tcp-agent hỗ trợ:

```env
TARGET_TUNNEL_ID=kaggle-1
```

với `AGENT_PORTS`, hoặc explicit route:

```env
AGENT_ROUTES=16379=kaggle-1:6379,26379=kaggle-2:6379
```

`AGENT_PORTS` và `AGENT_ROUTES` loại trừ lẫn nhau.

Cú pháp:

```text
localPort=targetTunnelId:targetPort
```

Đây là cấu hình nâng cao; hãy làm single target trước.

---

## 13. Quy tắc bảo mật

### Direct mode

Dùng đồng thời:

- authentication của database/service;
- `TCP_TUNNEL_ALLOWED_IPS`;
- firewall/security group;
- TLS ở database/application layer khi cần.

Direct relay listener là raw TCP; nó không tự thêm TLS cho Redis/PostgreSQL.

### Agent mode

Ưu tiên:

```env
AGENT_BIND_HOST=127.0.0.1
```

Agent từ chối non-loopback bind trừ khi set `ALLOW_REMOTE_AGENT_BIND=1`.

Dùng WSS cho public relay.

---

## 14. Troubleshooting

### `Tunnel target not connected: ...`

`TUNNEL_ID` yêu cầu hiện chưa đăng ký.

Kiểm tra target client log và target ID.

### `Target tunnel ID is required when multiple tunnel clients are connected`

Có nhiều target active nhưng tcp-agent chưa chọn target.

Dùng `TARGET_TUNNEL_ID` hoặc `AGENT_ROUTES`.

### `connect ECONNREFUSED 127.0.0.1:6379`

Relay đã tới đúng target nhưng Redis không listen ở đó.

Trên target:

```bash
ss -ltn | grep ':6379'
redis-cli -h 127.0.0.1 -p 6379 ping
```

### tcp-agent không ready

Kiểm tra:

```bash
tail -n 100 ~/.tcp-agent/agent.log
```

Nguyên nhân thường gặp:

- agent credential sai;
- local port đang bị process khác dùng;
- relay `TCP_AGENT_ALLOWED_PORTS` không cho target port;
- `/tcp` disabled;
- TLS/trusted-proxy policy không khớp.

### Redis/PostgreSQL authentication fail

Tunnel đã đi đủ xa để tới service. Hãy sửa Redis ACL/PostgreSQL credential thay vì đổi tunnel routing.

---

## 15. Acceptance checklist

- [ ] relay `/__health` trả `ok`;
- [ ] Redis/PostgreSQL trên target chạy local;
- [ ] target tunnel client ready;
- [ ] agent ready nếu dùng agent mode;
- [ ] chọn đúng target nếu có nhiều tunnel client;
- [ ] Redis `PING` hoặc PostgreSQL `SELECT 1` thành công qua tunnel;
- [ ] database authentication vẫn bật;
- [ ] direct-mode firewall/IP allowlist đủ chặt.

Bằng chứng live Redis và PostgreSQL tunneling qua các môi trường độc lập có trong [báo cáo live acceptance đa nền tảng](live-cross-platform-acceptance-2026-08-24.vi.md).
