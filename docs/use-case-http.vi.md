# Use Case 1 — Chia sẻ ứng dụng HTTP

> 🌐 Language / Ngôn ngữ: [English](use-case-http.md) | **Tiếng Việt**

Dùng guide này khi một máy private đang chạy ứng dụng HTTP như Rails, Node.js, FastAPI, Gradio, REST API hoặc web UI và bạn muốn người dùng Internet truy cập nó qua Nodejs-WSS-Service-Bridge relay của riêng bạn.

Nếu chưa deploy relay, hãy bắt đầu từ [START-HERE.vi.md](START-HERE.vi.md).

---

## 1. Use case này làm gì

Ví dụ target:

```text
Rails:   http://127.0.0.1:3000
Node.js: http://127.0.0.1:4000
FastAPI: http://127.0.0.1:8000
```

Target machine không cần inbound public port.

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

HTTP request public đi vào relay. Relay gửi request qua tunnel client đang connected, và tunnel client forward tới `TARGET_ORIGIN`.

---

## 2. Điều kiện trước khi bắt đầu

### Relay server

Bạn đã có:

- Nodejs-WSS-Service-Bridge đang chạy;
- public HTTPS URL, ví dụ `https://tunnel.example.com`;
- `INSTALL_UUID` đã pin;
- `TUNNEL_USERNAME` và `TUNNEL_PASSWORD`;
- `/__health` trả `ok`.

Đối với deployment đơn giản, giữ:

```env
MAX_TUNNEL_CLIENTS=1
```

Generic HTTP routing không dùng `TUNNEL_ID` để chọn target cụ thể khi có nhiều client connected.

### Target machine

Target cần:

- Node.js 20 trở lên;
- `curl`;
- npm;
- GNU `mv -T` cho official installer;
- một HTTP application đang listen local.

Linux là target platform được khuyến nghị.

---

## 3. Kiểm tra local application trước

Trước khi cài tunnel, phải chắc ứng dụng tự nó chạy local.

Rails:

```bash
curl -i http://127.0.0.1:3000/
```

Node.js:

```bash
curl -i http://127.0.0.1:4000/
```

FastAPI:

```bash
curl -i http://127.0.0.1:8000/
```

Chỉ tiếp tục khi bước này thành công.

Nếu application không truy cập được local thì tunnel cũng không thể làm nó truy cập được từ xa.

---

## 4. Cài tunnel client trên target machine

Ví dụ Rails port 3000:

```bash
export TUNNEL_SERVER_URL='https://tunnel.example.com'
export TUNNEL_USERNAME='<user-giong-server>'
export TUNNEL_PASSWORD='<password-giong-server>'
export TARGET_ORIGIN='http://127.0.0.1:3000'

curl -fsSL 'https://tunnel.example.com/<INSTALL_UUID>-install' | bash
```

Ví dụ Node.js port 4000:

```bash
export TUNNEL_SERVER_URL='https://tunnel.example.com'
export TUNNEL_USERNAME='<user-giong-server>'
export TUNNEL_PASSWORD='<password-giong-server>'
export TARGET_ORIGIN='http://127.0.0.1:4000'

curl -fsSL 'https://tunnel.example.com/<INSTALL_UUID>-install' | bash
```

Installer tự đổi public HTTP/HTTPS URL thành đúng `ws://` hoặc `wss://` với path `/tunnel`.

---

## 5. Kết quả install thành công

Installer thành công kết thúc tương tự:

```text
[tunnel] Client ready (PID: ...)
[tunnel] Logs: .../.tunnel-client/client.log
```

Kiểm tra:

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

Log phải cho thấy kết nối thành công thay vì auth/reconnect failure lặp lại.

---

## 6. Test qua Internet

Từ máy khác:

```bash
curl -i https://tunnel.example.com/
```

Hoặc mở:

```text
https://tunnel.example.com/
```

trong browser.

Response phải đến từ Rails/Node.js/FastAPI private của bạn.

Nếu không có tunnel client connected, root của relay sẽ redirect tới `/__info`.

---

## 7. Request header

Relay loại Host header cũ trước khi gửi request qua tunnel và cung cấp forwarding information như:

```text
X-Forwarded-Host
X-Forwarded-For
X-Forwarded-Proto
```

Framework sau reverse proxy có thể cần cấu hình trust forwarded headers.

Với Rails, kiểm tra Host Authorization và proxy settings nếu app từ chối public hostname.

---

## 8. Public access và authentication

Tunnel credentials bảo vệ **WebSocket connection từ target client tới relay**.

Chúng **không** tự tạo login page cho HTTP application được proxy.

Nếu:

```text
https://tunnel.example.com/
```

là public, bất kỳ ai biết URL đều có thể truy cập phần mà ứng dụng target tự expose.

Nếu ứng dụng cần private access, hãy bật authentication trong application hoặc đặt một reverse proxy/access-control layer có authentication phía trước relay.

---

## 9. Giới hạn WebSocket quan trọng

HTTP reverse-proxy path hiện từ chối downstream HTTP Upgrade request.

Do đó browser-to-application WebSocket như một số trường hợp:

- Rails Action Cable;
- Socket.IO WebSocket transport;
- custom WebSocket API;

không tự động được proxy bằng generic HTTP application path.

HTTP request/response bình thường hoạt động.

Nếu app phụ thuộc WebSocket Upgrade, phải test riêng requirement này trước khi publish.

---

## 10. Đổi target application

Muốn đổi từ port 3000 sang 4000, chạy lại installer với `TARGET_ORIGIN` mới:

```bash
export TARGET_ORIGIN='http://127.0.0.1:4000'
curl -fsSL 'https://tunnel.example.com/<INSTALL_UUID>-install' | bash
```

Installer dùng transactional release model và readiness gate.

---

## 11. Dừng và kiểm tra client

Theo dõi log:

```bash
tail -f ~/.tunnel-client/client.log
```

Dừng:

```bash
PID="$(cat ~/.tunnel-client/client.pid)"
ps -fp "$PID"
kill "$PID"
```

Luôn kiểm tra PID trước khi kill thủ công.

---

## 12. Kaggle / Colab / notebook lifecycle

Official installer dùng `setsid` khi có thể, `nohup`, và stdin từ `/dev/null` để tunnel client sống sau khi installer/notebook cell kết thúc miễn underlying runtime vẫn còn sống.

Nó không sống qua full runtime/container/host restart.

Sau Kaggle hoặc Colab runtime restart:

1. chạy lại local HTTP application;
2. chạy lại tunnel installer;
3. xác minh `client.pid == client.ready == live PID`;
4. test lại public URL.

---

## 13. Troubleshooting

### Public URL hiện info page

Nguyên nhân thường gặp: không có active tunnel client.

Kiểm tra:

```bash
cat ~/.tunnel-client/client.ready
tail -n 100 ~/.tunnel-client/client.log
```

### Relay trả 503 tunnel_unavailable

Relay không có active target client.

Kiểm tra credential, Internet từ target và client log.

### Target client connected nhưng request lỗi

Test application trực tiếp:

```bash
curl -i http://127.0.0.1:3000/
```

Nếu lệnh này lỗi thì sửa local app trước.

### Installer auth failed hoặc không ready

Xác minh:

```text
TUNNEL_USERNAME
TUNNEL_PASSWORD
TUNNEL_SERVER_URL
INSTALL_UUID
```

khớp relay configuration.

### Rails từ chối hostname

Kiểm tra Rails Host Authorization và proxy settings. Public hostname khác `127.0.0.1:3000`.

---

## 14. Acceptance checklist

Trước khi chia sẻ URL:

- [ ] `/__health` trả `ok`.
- [ ] local application chạy với `curl 127.0.0.1:<port>`.
- [ ] installer báo client ready.
- [ ] `client.pid` và `client.ready` khớp live PID.
- [ ] public URL trả đúng target application.
- [ ] chính sách authentication/access của HTTP app là có chủ đích.
- [ ] nếu cần WebSocket/Upgrade thì đã test riêng.

Bằng chứng live HTTP tunneling qua các môi trường độc lập có trong [báo cáo live acceptance đa nền tảng](live-cross-platform-acceptance-2026-08-24.vi.md).
