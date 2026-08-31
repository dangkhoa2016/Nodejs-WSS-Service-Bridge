# Bắt đầu tại đây — Tự host Nodejs-WSS-Service-Bridge

> 🌐 Language / Ngôn ngữ: [English](START-HERE.md) | **Tiếng Việt**

Tài liệu này dành cho người muốn clone repository và tự triển khai tunnel của riêng mình mà không cần hiểu trước giao thức bên trong.

Nodejs-WSS-Service-Bridge có **2 capability truyền tải** nhưng thường được dùng theo **3 use case**:

| Use case | Bạn muốn chia sẻ | Cơ chế bên trong | Đọc trước |
|---|---|---|---|
| Ứng dụng HTTP | Rails, Node.js, FastAPI, Gradio, web UI, REST API | HTTP qua tunnel WebSocket | [Hướng dẫn HTTP](use-case-http.vi.md) |
| Dịch vụ TCP | Redis, PostgreSQL, MySQL, database/service dùng TCP | Generic raw TCP tunnel | [Hướng dẫn TCP](use-case-tcp.vi.md) |
| SSH / SCP / SFTP | Remote shell và truyền file | Generic raw TCP tunnel | [Hướng dẫn SSH](use-case-ssh.vi.md) |

SSH không phải một wire protocol riêng trong dự án. Đây là một use case quan trọng và đã được live-test của generic TCP tunnel.

---

## 1. Hiểu ba vai trò máy

Cách dễ hiểu nhất là xem deployment gồm ba vai trò:

```text
A. Tunnel server / relay
   Nodejs-WSS-Service-Bridge có public Internet

B. Target / service machine
   Chạy thứ bạn muốn truy cập:
   - Rails / Node.js app
   - Redis / PostgreSQL
   - sshd
   Máy này chạy tunnel client và chủ động kết nối RA A

C. Consumer machine
   Browser, ứng dụng, database client hoặc người dùng SSH
   Kết nối trực tiếp tới A hoặc qua tcp-agent local
```

A và C có thể là cùng một máy trong development. B có thể là Kaggle, Colab, máy tính ở nhà, private VM hoặc bất kỳ môi trường nào cho phép outbound WebSocket.

Điểm quan trọng: **B không cần mở inbound public port**.

---

## 2. Chọn nơi deploy public tunnel server

Có hai profile server.

### Profile A — hosting chỉ có một public port

Dùng cho Northflank, Render, Railway, Fly.io, môi trường kiểu Codespaces hoặc host chỉ expose một HTTP/HTTPS port.

Dùng:

```text
.env.example.single-port
```

Khả năng:

- HTTP application tunnel: có
- TCP services: có, qua TCP agent
- SSH: có, qua TCP agent
- mở trực tiếp public Redis/PostgreSQL/SSH port trên relay: không

Đây là profile dễ dùng nhất cho đa số người dùng.

### Profile B — VPS / dedicated server

Dùng khi bạn kiểm soát VM/firewall và có thể bind thêm TCP port.

Dùng:

```text
.env.example.vps
```

Khả năng:

- HTTP application tunnel: có
- TCP services: direct TCP hoặc TCP-agent mode
- SSH: direct TCP hoặc TCP-agent mode

Direct TCP đơn giản hơn nhưng mọi port expose phải được bảo vệ bằng firewall và `TCP_TUNNEL_ALLOWED_IPS`.

---

## 3. Clone và cài server

Yêu cầu:

- Linux được khuyến nghị
- Node.js 20 trở lên
- Git
- Corepack/Yarn
- public HTTPS endpoint nếu dùng qua Internet

Clone:

```bash
git clone https://github.com/dangkhoa2016/Nodejs-WSS-Service-Bridge.git
cd Nodejs-WSS-Service-Bridge
corepack enable
yarn install --immutable
```

Build standalone client và tcp-agent:

```bash
yarn build:client
```

Build thành công tạo:

```text
dist/client.js
dist/tcp-agent.js
```

Không được bỏ qua bước này sau fresh clone. Production server dùng các bundle đã build này để phân phối cho target machine và application host.

---

## 4. Tạo credential và installation UUID ổn định

Tạo UUID một lần:

```bash
node -e "console.log(require('node:crypto').randomUUID())"
```

Tạo password mạnh:

```bash
node -e "console.log(require('node:crypto').randomBytes(32).toString('hex'))"
```

Giữ bí mật các giá trị:

```text
INSTALL_UUID
TUNNEL_USERNAME
TUNNEL_PASSWORD
TCP_AGENT_USERNAME / TCP_AGENT_PASSWORD (nếu cấu hình riêng)
ADMIN_SECRET (nếu bật)
```

**Phải pin `INSTALL_UUID`.** Không tạo UUID mới mỗi lần restart vì URL tải client/agent chứa UUID này.

---

## 5. Cấu hình server

### Ví dụ single-port

```bash
cp .env.example.single-port .env
```

Các giá trị tối thiểu cần kiểm tra:

```env
PORT=7860
SERVER_HOST=https://tunnel.example.com
INSTALL_UUID=<stable-uuid-cua-ban>

TUNNEL_USERNAME=<user-cua-ban>
TUNNEL_PASSWORD=<password-ngau-nhien-dai>

MAX_TUNNEL_CLIENTS=1
STREAM_IDLE_TIMEOUT_MS=120000

TCP_TUNNEL_PORTS=
TCP_AGENT_ALLOWED_PORTS=6379,5432,2222
```

Chỉ thêm những TCP port bạn thực sự định dùng.

Đối với SSH session lâu:

```env
STREAM_IDLE_TIMEOUT_MS=0
```

### Ví dụ VPS

```bash
cp .env.example.vps .env
```

Để forward Redis và PostgreSQL theo direct TCP:

```env
TCP_TUNNEL_PORTS=6379,5432
TCP_TUNNEL_BIND_HOST=0.0.0.0
TCP_TUNNEL_ALLOWED_IPS=<trusted-client-ip-hoac-cidr>
```

Không expose Redis, PostgreSQL, SSH hoặc raw TCP service ra `0.0.0.0` nếu thiếu authentication của service và giới hạn mạng/IP.

---

## 6. Khởi động server

### Development / kiểm tra local

```bash
yarn dev
```

### Production từ shell

Ứng dụng cố ý không tự load `.env` khi `NODE_ENV=production`. Hãy export trước:

```bash
set -a
. ./.env
set +a

yarn build:client
yarn prod
```

### Production trên PaaS

Nhập các biến của env template đã chọn vào giao diện Environment Variables của platform.

Lifecycle khuyến nghị:

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

Nếu dùng VPS direct-TCP mode, publish thêm từng TCP port, ví dụ `-p 6379:6379`.

---

## 7. Xác minh relay trước khi cài target

Health check:

```bash
curl -fsS https://tunnel.example.com/__health
```

Kết quả mong đợi:

```text
ok
```

Trang thông tin:

```text
https://tunnel.example.com/__info
```

Các path quan trọng:

```text
/tunnel                         WebSocket của target tunnel client
/tcp                            WebSocket của TCP agent
/__health                       health check
/__info                         thông tin deployment
/<INSTALL_UUID>-install         target client installer
/<INSTALL_UUID>-client.js       standalone target client
/<INSTALL_UUID>-tcp-agent.js    standalone TCP agent
```

Route artifact tcp-agent chỉ có khi `TCP_AGENT_ALLOWED_PORTS` không rỗng.

---

## 8. Chọn use case

### Tôi muốn expose Rails / Node.js / web API

Đọc:

**[Use case 1 — HTTP application](use-case-http.vi.md)**

Kết quả điển hình:

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

### Tôi muốn ứng dụng khác dùng Redis / PostgreSQL

Đọc:

**[Use case 2 — TCP services](use-case-tcp.vi.md)**

Chọn:

- direct TCP nếu relay là VPS cho phép publish service port;
- TCP-agent mode nếu relay là PaaS một public port.

### Tôi muốn SSH / SCP / SFTP

Đọc:

**[Use case 3 — SSH](use-case-ssh.vi.md)**

Topology phổ biến trên PaaS một port:

```text
ssh -> local tcp-agent -> WSS /tcp -> relay -> WSS /tunnel -> target -> sshd
```

---

## 9. Nhận biết target-client install thành công

Target installer lưu state ở:

```text
~/.tunnel-client/
```

Kiểm tra:

```bash
cat ~/.tunnel-client/client.pid
cat ~/.tunnel-client/client.ready
ps -fp "$(cat ~/.tunnel-client/client.pid)"
tail -n 50 ~/.tunnel-client/client.log
```

Client healthy và đang connected thỏa:

```text
client.pid == client.ready == live client PID
```

Official installer tách client khỏi installer/notebook-cell lifecycle bằng `setsid` khi có thể, `nohup`, và stdin từ `/dev/null`.

Điều này bảo vệ client khi parent shell/cell kết thúc. Nó **không** làm process sống qua full runtime, container, VM hoặc host restart.

Sau full Kaggle/Colab/container restart, hãy chạy lại installer và dựng lại các operating-system service mà runtime đã mất.

---

## 10. Giới hạn quan trọng

### HTTP WebSocket upgrade từ public application URL

HTTP reverse proxy hiện **không** proxy arbitrary downstream HTTP `Upgrade: websocket`.

Ứng dụng cần Socket.IO, Action Cable hoặc browser-to-app WebSocket khác có thể cần đường triển khai khác hoặc hỗ trợ trong phiên bản tương lai.

HTTP request/response bình thường dùng HTTP tunnel.

### HTTP routing khi có nhiều tunnel client

HTTP request generic chọn một active connected client; `TUNNEL_ID` được thiết kế cho deterministic TCP target selection.

Đối với deployment HTTP cho người mới, giữ:

```env
MAX_TUNNEL_CLIENTS=1
```

trừ khi bạn hiểu rõ và thực sự cần multi-client behavior.

### Bảo mật TCP

Tunnel không thay thế Redis/PostgreSQL/application authentication.

Giữ database authentication. Ưu tiên loopback và agent mode khi phù hợp. Nếu dùng direct TCP, kết hợp firewall với `TCP_TUNNEL_ALLOWED_IPS`.

---

## 11. Thứ tự troubleshooting

Khi lỗi, kiểm tra từ relay đi ra:

```text
1. /__health có trả ok?
2. target client có connected và ready?
3. có chọn đúng TUNNEL_ID?
4. local target service có thật sự listen?
5. tcp-agent local có connected/listening nếu dùng agent mode?
6. credential của service/application có đúng?
```

Hai lỗi không được nhầm lẫn:

```text
Tunnel target not connected: <id>
```

nghĩa là target tunnel đó chưa đăng ký với relay.

```text
connect ECONNREFUSED 127.0.0.1:<port>
```

nghĩa là tunnel đã tới target nhưng service local trên target không listen ở host/port đó.

---

## 12. Tài liệu nâng cao

Sau ba guide cho người mới, các tài liệu sau chứa chi tiết vận hành sâu hơn:

- [TCP tunnel deployment and operations](tcp-tunnel.vi.md)
- [External applications to TCP services](guide-external-app-to-tcp-services.vi.md)
- [Báo cáo qualification live / resilience cuối cùng](final-live-qualification-2026-08-22.vi.md)
- [Báo cáo live acceptance đa nền tảng](live-cross-platform-acceptance-2026-08-24.vi.md)
- [Testing guide](../TESTING.vi.md)
