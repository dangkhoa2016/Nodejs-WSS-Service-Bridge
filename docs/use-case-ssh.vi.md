# Use Case 3 — SSH, SCP và SFTP qua Tunnel

> 🌐 Language / Ngôn ngữ: [English](use-case-ssh.md) | **Tiếng Việt**

Dùng guide này khi một máy private chạy `sshd` và bạn muốn SSH tới nó mà không mở inbound public SSH port trên chính target đó.

Nếu chưa deploy relay, hãy bắt đầu từ [START-HERE.vi.md](START-HERE.vi.md).

---

## 1. SSH nằm ở đâu trong kiến trúc

SSH được truyền như generic raw TCP.

Nodejs-WSS-Service-Bridge không có SSH protocol riêng.

```text
ssh / scp / sftp
      |
      | local TCP
      v
tcp-agent
      |
      | WSS /tcp
      v
Nodejs-WSS-Service-Bridge relay
      |
      | WSS /tunnel
      v
target tunnel client
      |
      | TCP 127.0.0.1:2222
      v
sshd
```

SCP và SFTP chạy trên SSH nên dùng cùng tunnel path.

---

## 2. Topology khuyến nghị

Nếu relay nằm trên PaaS chỉ có một public port:

- relay: public HTTPS/WSS;
- target: `sshd` trên loopback, ví dụ `127.0.0.1:2222`;
- máy local/admin: tcp-agent listen loopback;
- SSH client: kết nối vào local loopback port đó.

Target machine không cần expose 22/2222 ra Internet.

---

## 3. Cấu hình relay

Ví dụ single target:

```env
INSTALL_UUID=<stable-uuid>

TUNNEL_USERNAME=<tunnel-user>
TUNNEL_PASSWORD=<long-random-secret>

MAX_TUNNEL_CLIENTS=1

TCP_TUNNEL_PORTS=
TCP_TUNNEL_HOST=127.0.0.1
TCP_CLIENT_ALLOWED_HOSTS=127.0.0.1

TCP_AGENT_PATH=/tcp
TCP_AGENT_ALLOWED_PORTS=2222

STREAM_IDLE_TIMEOUT_MS=0
```

Với SSH, nên dùng `STREAM_IDLE_TIMEOUT_MS=0` khi muốn session có thể idle lâu.

WebSocket heartbeat vẫn phát hiện tunnel connection chết; setting này chỉ tắt application stream idle timeout.

---

## 4. Chuẩn bị SSH trên target machine

Lệnh cài package phụ thuộc distro.

Ubuntu/Debian:

```bash
sudo apt-get update
sudo apt-get install -y openssh-server
```

Tạo hoặc dùng login user bình thường. Production nên ưu tiên SSH key.

Ví dụ cấu hình sshd chỉ listen loopback:

```text
Port 2222
ListenAddress 127.0.0.1
PasswordAuthentication yes
UsePAM yes
```

Nếu dùng key-only, cấu hình `PasswordAuthentication no` phù hợp và thêm `authorized_keys`.

Restart hoặc launch sshd theo distro.

Kiểm tra local trên target:

```bash
ss -ltn | grep ':2222'
ssh-keyscan -p 2222 127.0.0.1
```

Chỉ tiếp tục khi `127.0.0.1:2222` đang listen.

---

## 5. Cài tunnel client trên SSH target

Single target:

```bash
export TUNNEL_SERVER_URL='https://tunnel.example.com'
export TUNNEL_USERNAME='<tunnel-user>'
export TUNNEL_PASSWORD='<long-random-secret>'

curl -fsSL 'https://tunnel.example.com/<INSTALL_UUID>-install' | bash
```

Nếu muốn đặt tên target:

```bash
export TUNNEL_ID='kaggle-1'
```

trước khi chạy installer.

Kiểm tra:

```bash
cat ~/.tunnel-client/client.pid
cat ~/.tunnel-client/client.ready
ps -fp "$(cat ~/.tunnel-client/client.pid)"
tail -n 100 ~/.tunnel-client/client.log
```

Healthy:

```text
client.pid == client.ready == live client PID
```

---

# Phần A — SSH single-target đơn giản

## 6. Cài local tcp-agent

Single target dùng cùng local và target port có thể dùng repository installer.

Trên máy bạn sẽ chạy `ssh`:

```bash
export SERVER_HOST='tunnel.example.com'
export INSTALL_UUID='<stable-uuid>'

export AGENT_USERNAME='<agent-user-hoac-tunnel-user>'
export AGENT_PASSWORD='<agent-secret-hoac-tunnel-password>'

export AGENT_PORTS='2222'

./scripts/setup-application-host.sh
```

Nếu relay không cấu hình `TCP_AGENT_USERNAME` / `TCP_AGENT_PASSWORD` riêng, agent credential fallback về tunnel credential.

Kiểm tra:

```bash
cat ~/.tcp-agent/agent.pid
cat ~/.tcp-agent/agent.ready
ps -fp "$(cat ~/.tcp-agent/agent.pid)"
ss -ltn | grep ':2222'
tail -n 100 ~/.tcp-agent/agent.log
```

---

## 7. Kết nối SSH

```bash
ssh -p 2222 <user>@127.0.0.1
```

TCP flow:

```text
127.0.0.1:2222
  -> tcp-agent
  -> WSS /tcp
  -> relay
  -> WSS /tunnel
  -> target client
  -> 127.0.0.1:2222 sshd
```

---

## 8. Truyền file bằng SCP

Upload:

```bash
scp -P 2222 ./local-file.txt <user>@127.0.0.1:/home/<user>/local-file.txt
```

Download:

```bash
scp -P 2222 <user>@127.0.0.1:/home/<user>/remote-file.txt ./
```

SFTP:

```bash
sftp -P 2222 <user>@127.0.0.1
```

---

# Phần B — Nhiều SSH target với local port mapping

## 9. Vì sao cần `AGENT_ROUTES`

Giả sử hai private target cùng chạy sshd port 2222:

```text
kaggle-1 -> 127.0.0.1:2222
kaggle-2 -> 127.0.0.1:2222
```

Có thể expose local:

```text
127.0.0.1:22001 -> kaggle-1:2222
127.0.0.1:22002 -> kaggle-2:2222
```

Đây chính là topology đã dùng trong final live qualification.

Relay:

```env
MAX_TUNNEL_CLIENTS=2
TCP_AGENT_ALLOWED_PORTS=2222
STREAM_IDLE_TIMEOUT_MS=0
```

Target 1:

```bash
export TUNNEL_ID='kaggle-1'
```

Target 2:

```bash
export TUNNEL_ID='kaggle-2'
```

Mỗi target chạy official tunnel installer với cùng relay credential.

---

## 10. Cài standalone tcp-agent cho route mapping

`scripts/setup-application-host.sh` hiện cấu hình `AGENT_PORTS`, tức local và target port giống nhau.

Nếu cần remap port / nhiều named target, chạy standalone tcp-agent với `AGENT_ROUTES`.

Tạo thư mục:

```bash
mkdir -p ~/.nodejs-wss-service-bridge-agent
cd ~/.nodejs-wss-service-bridge-agent
```

Tải bundle và manifest do relay serve:

```bash
curl -fsSL   'https://tunnel.example.com/<INSTALL_UUID>-tcp-agent.js'   -o tcp-agent.js

curl -fsSL   'https://tunnel.example.com/<INSTALL_UUID>-tcp-agent-package.json'   -o package.json

npm install --omit=dev
```

Set environment:

```bash
export TUNNEL_SERVER_URL='wss://tunnel.example.com/tcp'
export AGENT_USERNAME='<agent-user-hoac-tunnel-user>'
export AGENT_PASSWORD='<agent-secret-hoac-tunnel-password>'

export AGENT_BIND_HOST='127.0.0.1'
export AGENT_ROUTES='22001=kaggle-1:2222,22002=kaggle-2:2222'
```

Start detached trên Linux:

```bash
setsid nohup node ./tcp-agent.js   </dev/null   > ./agent.log 2>&1 &

echo $! > ./agent.pid
```

Kiểm tra:

```bash
PID="$(cat ./agent.pid)"
kill -0 "$PID"
ps -fp "$PID"

ssh-keyscan -p 22001 127.0.0.1
ssh-keyscan -p 22002 127.0.0.1
```

Relay `TCP_AGENT_ALLOWED_PORTS` phải cho **target port** mà route yêu cầu, ở đây là `2222`. Không cần chứa local port 22001/22002.

---

## 11. Kết nối từng target

Target 1:

```bash
ssh -p 22001 <user>@127.0.0.1
```

Target 2:

```bash
ssh -p 22002 <user>@127.0.0.1
```

SCP dùng cùng mapping:

```bash
scp -P 22001 ./file.txt <user>@127.0.0.1:/home/<user>/file.txt
scp -P 22002 ./file.txt <user>@127.0.0.1:/home/<user>/file.txt
```

---

## 12. Kiểm tra isolation

Khi cả hai target connected:

```bash
ssh-keyscan -p 22001 127.0.0.1
ssh-keyscan -p 22002 127.0.0.1
```

Mỗi route chỉ được tới đúng `TUNNEL_ID` của nó.

Nếu `kaggle-1` disconnect, route 22001 phải fail trong khi route 22002 vẫn có thể healthy.

Hành vi này đã được xác minh trực tiếp trong R3 reconnect test cuối cùng.

---

## 13. SSH host key thay đổi sau ephemeral runtime restart

Kaggle/Colab hoặc OpenSSH cài lại có thể sinh SSH host key mới.

Nếu SSH báo:

```text
WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!
```

không được xóa key cũ một cách mù quáng.

Trước tiên xác minh lý do target thay đổi và kiểm tra fingerprint mới qua trusted path.

Sau đó mới xóa đúng stale entry, ví dụ:

```bash
ssh-keygen -R '[127.0.0.1]:22001'
```

rồi reconnect sau khi verify fingerprint mới.

---

## 14. Runtime restart khác client lifecycle

Target installer đã detach khỏi notebook/cell shell lifecycle.

Nghĩa là installer cell kết thúc không nên kill client miễn runtime còn sống.

Nó **không** sống qua:

- Kaggle runtime restart;
- Colab runtime restart;
- container restart;
- VM reboot;
- host bị hủy.

Sau full target runtime restart:

1. restore/install `sshd`;
2. restore login user/authorized keys nếu environment làm mất;
3. chạy lại official tunnel installer với cùng `TUNNEL_ID`;
4. xác minh `127.0.0.1:2222`;
5. xác minh lại local route.

Sau local tcp-agent host restart, hãy restart tcp-agent. PID file persist có thể stale; kiểm tra bằng `kill -0` và `ps`.

---

## 15. Khuyến nghị bảo mật

Ưu tiên:

- SSH public-key authentication;
- non-root user;
- `sshd` bind `127.0.0.1` trên private target;
- tcp-agent bind `127.0.0.1`;
- WSS/HTTPS cho relay;
- tunnel/agent credential mạnh.

Không đưa SSH password private vào log, tài liệu, script hoặc repository.

Tunnel truyền SSH traffic, nhưng credential SSH yếu vẫn là credential yếu.

---

## 16. Troubleshooting

### `Tunnel target not connected: kaggle-1`

Target client của ID đó chưa đăng ký.

Kiểm tra:

```bash
tail -n 100 ~/.tunnel-client/client.log
```

### `connect ECONNREFUSED 127.0.0.1:2222`

Khác hoàn toàn: tunnel đã tới target nhưng sshd không chạy hoặc không listen.

Trên target:

```bash
ss -ltn | grep ':2222'
ssh-keyscan -p 2222 127.0.0.1
```

### Local `ssh -p 22001` báo connection refused

Kiểm tra local tcp-agent trước:

```bash
ss -ltn | grep ':22001'
ps -fp "$(cat ~/.nodejs-wss-service-bridge-agent/agent.pid)"
tail -n 100 ~/.nodejs-wss-service-bridge-agent/agent.log
```

### SSH bị rớt khi idle

Với profile SSH idle lâu đã test, cấu hình:

```env
STREAM_IDLE_TIMEOUT_MS=0
```

Final live qualification giữ một SSH session thật sự idle khoảng 9 phút 53 giây và vẫn hoạt động.

---

## 17. Acceptance checklist

- [ ] relay `/__health` trả `ok`;
- [ ] sshd listen trên target loopback;
- [ ] target tunnel client ready;
- [ ] local tcp-agent listen đúng loopback port;
- [ ] `ssh-keyscan` thành công qua tunnel;
- [ ] interactive SSH thành công;
- [ ] SCP thành công nếu cần file transfer;
- [ ] multi-target route tới đúng `TUNNEL_ID`;
- [ ] SSH host-key change được verify thay vì chấp nhận mù quáng;
- [ ] full runtime restart được phân biệt với shell/cell lifecycle.

Xem [final live qualification report](final-live-qualification-2026-08-22.vi.md) để biết evidence SSH/SCP hai target đã test thật.
