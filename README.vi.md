# Nodejs WSS Service Bridge (HTTP-over-WebSocket Reverse Tunnel)

[![CI](https://github.com/dangkhoa2016/Nodejs-WSS-Service-Bridge/actions/workflows/ci.yml/badge.svg)](https://github.com/dangkhoa2016/Nodejs-WSS-Service-Bridge/actions/workflows/ci.yml)
[![Node.js](https://img.shields.io/badge/Node.js-%3E%3D20-339933?logo=node.js&logoColor=white)](https://nodejs.org/)
[![Yarn](https://img.shields.io/badge/Yarn-4.17.1-2C8EBB?logo=yarn&logoColor=white)](https://yarnpkg.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Transport](https://img.shields.io/badge/Transport-HTTP%20%7C%20TCP%20%7C%20SSH-4C8BF5)](docs/START-HERE.vi.md)
[![Tunnel](https://img.shields.io/badge/Tunnel-WebSocket%20%2F%20WSS-6A5ACD)](docs/START-HERE.vi.md)

> 🌐 Language / Ngôn ngữ: [English](README.md) | **Tiếng Việt**

Một reverse tunnel tự host cho **ứng dụng HTTP** và **dịch vụ TCP generic** chạy qua WebSocket.

Dự án phù hợp với những môi trường có thể kết nối outbound ra Internet nhưng khó hoặc không thể nhận inbound connection trực tiếp, ví dụ Kaggle, Google Colab, máy private, development container và máy nằm sau NAT/firewall hạn chế.

Cùng một dự án xử lý ba use case phổ biến:

1. **Chia sẻ ứng dụng HTTP** — Rails, Node.js, FastAPI, Gradio, REST API, web UI.
2. **Chia sẻ dịch vụ TCP** — Redis, PostgreSQL, MySQL, Qdrant gRPC và TCP endpoint khác.
3. **SSH / SCP / SFTP** — remote shell và truyền file qua generic TCP tunnel.

> Mới dùng dự án? **Bắt đầu tại đây:** [Hướng dẫn self-host cho người mới](docs/START-HERE.vi.md)

---

## Vì sao có dự án này

Target machine không cần inbound public port.

Thay vào đó, target chủ động mở authenticated outbound WebSocket connection tới relay do bạn kiểm soát:

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
       | HTTP hoặc WSS /tcp
       |
Browser / app / local tcp-agent
```

Phù hợp cho:

- demo chạy trên Kaggle hoặc Colab;
- máy private/home nằm sau NAT;
- PaaS chỉ expose một public HTTP port;
- truy cập development service tự host;
- cho application host dùng Redis/PostgreSQL private;
- SSH tới target mà không mở SSH trực tiếp ra Internet.

---

## Ba use case

### 1. Ứng dụng HTTP

Ví dụ:

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

**[Use Case 1 — Chia sẻ ứng dụng HTTP](docs/use-case-http.vi.md)**

Target điển hình:

- Rails;
- Node.js / Express;
- FastAPI;
- Gradio;
- web dashboard;
- REST API.

---

### 2. Redis / PostgreSQL / generic TCP

Có hai mode.

**Direct TCP** — phù hợp VPS nơi bạn kiểm soát TCP port:

```text
application -> relay:6379 -> WSS /tunnel -> target -> Redis:6379
```

**TCP-agent mode** — phù hợp PaaS chỉ có một public port:

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

**[Use Case 2 — Chia sẻ Redis, PostgreSQL và dịch vụ TCP](docs/use-case-tcp.vi.md)**

---

### 3. SSH / SCP / SFTP

SSH được truyền bằng generic TCP tunnel.

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

Multi-target topology hỗ trợ route như:

```text
22001 -> kaggle-1:2222
22002 -> kaggle-2:2222
```

Guide:

**[Use Case 3 — SSH, SCP và SFTP](docs/use-case-ssh.vi.md)**

### Script SSH tái sử dụng

Repository có ba helper portable trong `scripts/`:

| Script | Môi trường | Mục đích |
|---|---|---|
| `setup-wss-ssh-target.sh` | Target Kaggle / Colab / Ubuntu-like | Tạo SSH target dùng key-only, tùy chọn passwordless sudo và đăng ký tunnel client có tên |
| `ssh-via-nodejs-wss-service-bridge.sh` | Linux / GitHub Codespaces | Mở local TCP-agent route rồi SSH tới target có tên |
| `ssh-via-nodejs-wss-service-bridge.bat` | Windows | Mở TCP-agent route tương đương bằng Windows OpenSSH |

Các helper không hard-code private relay domain, install UUID, relay credential hoặc đường dẫn SSH key riêng của một máy. Hãy cấu hình các giá trị đó bằng environment variable. Ví dụ dùng đường dẫn chuẩn như `$HOME/.ssh/id_ed25519` và `%USERPROFILE%\.ssh\id_ed25519`.

Ví dụ Linux / Codespaces:

```bash
export RELAY_HOST='tunnel.example.com'
export INSTALL_UUID='<stable-install-uuid>'
export AGENT_USERNAME='<relay-user>'

./scripts/ssh-via-nodejs-wss-service-bridge.sh \
  "$HOME/.ssh/id_ed25519" \
  colab-1
```

Ví dụ Windows:

```bat
set "RELAY_HOST=tunnel.example.com"
set "INSTALL_UUID=<stable-install-uuid>"
set "AGENT_USERNAME=<relay-user>"

scripts\ssh-via-nodejs-wss-service-bridge.bat "%USERPROFILE%\.ssh\id_ed25519" "colab-1"
```

Ví dụ bootstrap target:

```bash
export TUNNEL_SERVER_URL='https://tunnel.example.com'
export TUNNEL_USERNAME='<relay-user>'
export INSTALL_UUID='<stable-install-uuid>'
export TUNNEL_PASSWORD='<relay-password>'
export SSH_PUBLIC_KEY_FILE="$HOME/.ssh/id_ed25519.pub"

sudo -E ./scripts/setup-wss-ssh-target.sh colab-1
```

Live acceptance cho SSH helper:

| Môi trường local | Target Kaggle | Target Colab | Duy trì `tmux` |
|---|---|---|---|
| Windows 10 | PASS | PASS | PASS trên Colab |
| GitHub Codespaces / Linux | Chưa chạy lại trong closeout này | PASS | PASS trên Colab |

Matrix chỉ ghi PASS cho tổ hợp đã được chạy thật trong live acceptance; ô chưa test không được hiểu là failure.

---

## Thực chất dự án implement gì

Ở transport level, dự án có hai capability chính:

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
    └── các TCP protocol khác
```

SSH là use case TCP, không phải custom protocol riêng trong relay.

---

# Quick start — deploy relay của riêng bạn

## Yêu cầu

- Node.js 20 trở lên;
- Git;
- Corepack/Yarn;
- Linux được khuyến nghị;
- HTTPS endpoint nếu deploy public Internet.

Clone:

```bash
git clone https://github.com/dangkhoa2016/Nodejs-WSS-Service-Bridge.git
cd Nodejs-WSS-Service-Bridge

corepack enable
yarn install --immutable
yarn build:client
```

Build tạo standalone bundle dùng để phân phối tới target và agent:

```text
dist/client.js
dist/tcp-agent.js
```

---

## Chọn server profile

### Một public port / PaaS

Dùng:

```bash
cp .env.example.single-port .env
```

Khuyến nghị cho:

- Northflank;
- Render;
- Railway;
- platform kiểu Fly.io;
- host chỉ hỗ trợ HTTP/HTTPS.

HTTP đi trực tiếp qua relay. TCP và SSH dùng TCP agent.

### VPS / dedicated server

Dùng:

```bash
cp .env.example.vps .env
```

VPS có thể dùng cả direct TCP và TCP-agent mode.

---

## Cấu hình tối thiểu

Tạo stable UUID một lần:

```bash
node -e "console.log(require('node:crypto').randomUUID())"
```

Tạo password mạnh:

```bash
node -e "console.log(require('node:crypto').randomBytes(32).toString('hex'))"
```

Ít nhất set:

```env
PORT=7860
SERVER_HOST=https://tunnel.example.com

INSTALL_UUID=<stable-uuid>

TUNNEL_USERNAME=<user-cua-ban>
TUNNEL_PASSWORD=<secret-ngau-nhien-dai>

MAX_TUNNEL_CLIENTS=1
```

Nếu server một port và dùng Redis/PostgreSQL/SSH:

```env
TCP_TUNNEL_PORTS=
TCP_AGENT_ALLOWED_PORTS=6379,5432,2222
```

Với SSH idle lâu:

```env
STREAM_IDLE_TIMEOUT_MS=0
```

---

## Khởi động

Development:

```bash
yarn dev
```

Production từ shell:

```bash
set -a
. ./.env
set +a

yarn build:client
yarn prod
```

> Trong production mode, ứng dụng không tự load `.env`; hãy export variables hoặc cấu hình chúng trong hosting platform.

Docker:

```bash
docker build -t nodejs-wss-service-bridge .

docker run --rm   --env-file .env   -p 7860:7860   nodejs-wss-service-bridge
```

---

## Xác minh relay

```bash
curl -fsS https://tunnel.example.com/__health
```

Mong đợi:

```text
ok
```

Trang thông tin:

```text
https://tunnel.example.com/__info
```

Route quan trọng:

| Route | Mục đích |
|---|---|
| `/tunnel` | target client WebSocket |
| `/tcp` | TCP-agent WebSocket |
| `/__health` | health check |
| `/__info` | thông tin deployment |
| `/<INSTALL_UUID>-install` | target-client installer |
| `/<INSTALL_UUID>-client.js` | target-client bundle |
| `/<INSTALL_UUID>-tcp-agent.js` | TCP-agent bundle |

---

# Cài target client

Relay phục vụ installer cho private target.

Ví dụ HTTP:

```bash
export TUNNEL_SERVER_URL='https://tunnel.example.com'
export TUNNEL_USERNAME='<user-cua-ban>'
export TUNNEL_PASSWORD='<secret-cua-ban>'
export TARGET_ORIGIN='http://127.0.0.1:3000'

curl -fsSL   'https://tunnel.example.com/<INSTALL_UUID>-install'   | bash
```

State nằm tại:

```text
~/.tunnel-client/
```

Healthy:

```text
client.pid == client.ready == live client PID
```

Kiểm tra:

```bash
cat ~/.tunnel-client/client.pid
cat ~/.tunnel-client/client.ready
ps -fp "$(cat ~/.tunnel-client/client.pid)"
tail -n 100 ~/.tunnel-client/client.log
```

Installer dùng transactional release/readiness model và detach target client khỏi installer/notebook-cell lifecycle bằng `setsid` khi có thể, `nohup`, và stdin từ `/dev/null`.

Full runtime/container/host restart là failure domain khác và cần start process lại.

---

# Multi-target TCP routing

Mỗi target có thể đăng ký `TUNNEL_ID` riêng:

```text
kaggle-1
kaggle-2
colab-1
```

Local TCP agent định nghĩa route rõ ràng:

```env
AGENT_ROUTES=22001=kaggle-1:2222,22002=kaggle-2:2222
```

Cú pháp:

```text
localPort=targetTunnelId:targetPort
```

Nhờ vậy một public relay vẫn route TCP chính xác tới nhiều target.

---

# Bảo mật

Dự án có:

- HTTP Basic authentication cho tunnel WebSocket client;
- authentication riêng/fallback cho TCP agent;
- constant-time credential comparison;
- IPv4/CIDR allowlist cho direct TCP listener;
- optional TLS enforcement cho `/tcp`;
- trusted-proxy controls;
- TCP-agent mặc định bind loopback;
- HMAC-signed admin configuration URLs;
- transactional client/agent installer có readiness và rollback.

Nhưng vẫn phải áp dụng security của service:

- giữ Redis/PostgreSQL authentication;
- ưu tiên SSH public key;
- dùng firewall với direct TCP;
- không commit real secret;
- không log SSH/database password;
- dùng HTTPS/WSS khi deploy public.

---

# Giới hạn quan trọng

## HTTP WebSocket Upgrade

Generic HTTP proxy hiện không proxy arbitrary downstream HTTP `Upgrade: websocket`.

HTTP request/response bình thường hoạt động. App phụ thuộc Action Cable, Socket.IO WebSocket transport hoặc custom browser WebSocket endpoint phải test riêng requirement này.

## HTTP với nhiều target client

`TUNNEL_ID` cho deterministic TCP target selection. Generic HTTP proxy chọn một active connected client thay vì route theo `TUNNEL_ID`.

Với HTTP đơn giản, giữ:

```env
MAX_TUNNEL_CLIENTS=1
```

## Process detachment khác host restart

Detached client có thể sống khi installer/notebook cell cha kết thúc miễn runtime còn sống.

Nó không thể sống qua full runtime/container/VM/host restart.

---

# Tài liệu

## Beginner / deployment guides

- **[Bắt đầu tại đây — self-hosting guide](docs/START-HERE.vi.md)**
- **[Use Case 1 — HTTP application](docs/use-case-http.vi.md)**
- **[Use Case 2 — TCP services](docs/use-case-tcp.vi.md)**
- **[Use Case 3 — SSH / SCP / SFTP](docs/use-case-ssh.vi.md)**

## Tài liệu nâng cao

- [TCP tunnel deployment and operations](docs/tcp-tunnel.vi.md)
- [Kết nối ứng dụng ngoài tới TCP services](docs/guide-external-app-to-tcp-services.vi.md)
- [Testing](TESTING.vi.md)
- [Final live / resilience qualification report](docs/final-live-qualification-2026-08-22.vi.md)
- [Cross-platform live acceptance report](docs/live-cross-platform-acceptance-2026-08-24.vi.md)

Bản English nằm cạnh các tài liệu Vietnamese tương ứng.

---

# Trạng thái validation

Final live/resilience qualification đã bao phủ:

- hai target client độc lập;
- official installer lifecycle;
- detached-process longevity;
- multi-target routing;
- true-idle SSH;
- target reconnect và isolation;
- local tcp-agent reconnect;
- final interactive SSH;
- SCP;
- SHA-256 file-integrity verification.

Kết quả:

```text
FINAL LIVE / RESILIENCE QUALIFICATION = PASS
```

Xem [qualification report](docs/final-live-qualification-2026-08-22.vi.md) để biết evidence và tested authority.

Một [báo cáo live acceptance đa nền tảng](docs/live-cross-platform-acceptance-2026-08-24.vi.md) sau đó còn ghi nhận HTTP, Redis và PostgreSQL được tunnel qua các môi trường độc lập (Colab, Kaggle, Codespaces) qua cùng một relay.

---

# Development và testing

Chạy full local checks:

```bash
yarn check
```

Từng command:

```bash
yarn lint
yarn test
yarn build:client
```

Xem [TESTING.vi.md](TESTING.vi.md) để biết chi tiết.

---

# License

MIT — xem [LICENSE](LICENSE).
