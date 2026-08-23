# Báo cáo Qualification Live / Resilience Cuối cùng

> 🌐 Language / Ngôn ngữ: [English](final-live-qualification-2026-08-22.md) | **Tiếng Việt**

**Ngày:** 2026-08-22  
**Repository:** `dangkhoa2016/Nodejs-WSS-Service-Bridge`  
**Kết quả:** **PASS**

## 1. Phạm vi

Báo cáo này đóng workstream qualification live sau merge cho bản sửa vòng đời target-client được đưa vào bởi PR #15, `feat(installer): detach target client lifecycle`.

Qualification bao phủ đường đi production-like sau:

```text
local Linux / Codespaces tcp-agent
  127.0.0.1:22001 -> kaggle-1:2222
  127.0.0.1:22002 -> kaggle-2:2222
           |
           | WSS /tcp
           v
      Northflank relay
           |
           | WSS /tunnel
           v
      Kaggle targets
```

Profile live dùng `STREAM_IDLE_TIMEOUT_MS=0`.

Đây là qualification cho implementation đã merge và hành vi vận hành của nó, không phải một thử nghiệm kiến trúc mới.

## 2. Hành vi lifecycle đã qualification

Official installer khởi chạy target client với stdin tách rời và, khi có thể, một session mới:

```bash
if command -v setsid >/dev/null 2>&1; then
  session_launcher=(setsid)
fi

"${session_launcher[@]}" nohup node "${release_path}/client.js" \
  </dev/null \
  > "${WORK_DIR}/client.log" 2>&1 &

CLIENT_PID=$!
printf '%s\n' "$CLIENT_PID" > "${WORK_DIR}/client.pid"
```

Các thuộc tính quan trọng:

- dùng `setsid` nhưng không dùng `-f`;
- vẫn dùng `nohup`;
- stdin được tách bằng `</dev/null`;
- `$!` vẫn là PID thật của client;
- readiness gắn với đúng PID đó;
- contract acceptance là `client.pid == client.ready == live client PID`.

Qualification quan sát được các client đã detach với `PPID=1` và `SID=self` sau khi installer/notebook cell kết thúc.

## 3. Ma trận acceptance

| Qualification | Kết quả |
| --- | --- |
| Northflank public health | PASS |
| Official installer public markers | PASS |
| Kaggle 1 official install | PASS |
| Kaggle 2 official install | PASS |
| K1 PID/readiness equality | PASS |
| K2 PID/readiness equality | PASS |
| K1 detached lifecycle | PASS |
| K2 detached lifecycle | PASS |
| K1 `PPID=1` / `SID=self` | PASS |
| K2 `PPID=1` / `SID=self` | PASS |
| Route `22001 -> kaggle-1:2222` | PASS |
| Route `22002 -> kaggle-2:2222` | PASS |
| Two-target routing isolation | PASS |
| Official lifecycle longevity >10–20 min | PASS |
| R2 true-idle SSH ~9m53s | PASS |
| R3 target reconnect | PASS |
| R3 unaffected second target | PASS |
| R4 local tcp-agent reconnect | PASS |
| Final interactive SSH K1 | PASS |
| Final interactive SSH K2 | PASS |
| Final SCP K1 | PASS |
| Final SCP K2 | PASS |
| Final SHA-256 integrity K1 | PASS |
| Final SHA-256 integrity K2 | PASS |

Tổng thể:

```text
FINAL LIVE / RESILIENCE QUALIFICATION = PASS
```

## 4. R2 — true-idle SSH

Một phiên SSH interactive duy nhất đến Kaggle 1 được để idle khoảng **9 phút 53 giây** rồi tiếp tục hoạt động thành công.

Không dùng `watch`, polling loop, traffic generator hoặc output ứng dụng để giữ phiên hoạt động.

Khoảng này vượt cả ngưỡng lỗi lịch sử ~120 giây và khoảng qualification dự kiến 3–5 phút.

Kết quả: **PASS**.

## 5. R3 — target reconnect

Kaggle 1 được dừng và khởi động lại có chủ đích trong khi Kaggle 2 vẫn kết nối.

Hành vi route quan sát được:

```text
Trước restart:   K1 PASS, K2 PASS
Trong lúc K1 dừng: K1 FAIL, K2 PASS
Sau reconnect:   K1 PASS, K2 PASS
```

Client K1 sau restart tiếp tục thỏa contract PID/readiness và kiểm tra lifecycle detach.

Kết quả:

- outage tạm thời của K1: **PASS**
- isolation/K2 không bị ảnh hưởng: **PASS**
- K1 tự phục hồi: **PASS**
- lifecycle sau reconnect: **PASS**

## 6. R4 — local tcp-agent reconnect

Local tcp-agent được restart có chủ đích.

Cả hai route local tạm thời unavailable trong outage có kiểm soát và cùng phục hồi sau khi agent mới ready.

Agent thay thế cũng có trạng thái process detach mong đợi (`PPID=1`, `SID=self`).

Kết quả: **PASS**.

## 7. Final SSH, SCP và integrity acceptance

Cả hai route target đều PASS final interactive SSH.

Sau đó một payload chuẩn 39 byte được truyền bằng SCP đến cả hai target:

```text
Nodejs-WSS-Service-Bridge final SCP acceptance
```

SHA-256 chuẩn:

```text
ce2dac1eb72588f3aaf9457ce9053ecd378ffe22269926a219ab6098300a9afc
```

Cùng digest này đã được xác minh từ xa trên cả hai target Kaggle.

Đây là bằng chứng integrity end-to-end cuối cùng cho hai route SSH/SCP.

## 8. Ranh giới failure domain

Điểm vận hành quan trọng nhất được xác lập bởi qualification là:

> Process detachment bảo vệ client khỏi việc bị dừng do installer shell hoặc notebook cell cha kết thúc, nhưng không và không thể làm một process sống qua full runtime, container, host hoặc VM restart.

Hai external restart đã xảy ra trong qualification:

1. một Kaggle runtime restart sau khi trở nên idle;
2. local Codespaces/container restart sau đó.

Cả hai đều được phân loại rõ là external runtime/host restart, không phải tunnel implementation failure.

Một process detach vẫn được kỳ vọng sẽ biến mất sau:

- Kaggle runtime restart,
- Codespaces/container restart,
- host reboot,
- VM/container destruction.

Không nên xem riêng một sự kiện như vậy là bằng chứng PR #15 regression.

## 9. Hướng dẫn recovery

### Sau Kaggle runtime restart

State hệ thống/runtime có thể cần dựng lại dù `/kaggle/working` vẫn tồn tại.

Thứ tự recovery khuyến nghị:

1. Chạy lại official tunnel installer với cùng `TUNNEL_ID`.
2. Khôi phục local service account và SSH runtime nếu notebook image đã mất chúng.
3. Khôi phục `sshd` trên `127.0.0.1:2222`.
4. Xác minh `client.pid == client.ready == live PID`.
5. Xác minh process đã detach sau khi installer cell kết thúc.
6. Xác minh canonical local route bằng `ssh-keyscan` hoặc SSH connection.

### Sau local host/container restart

`agent.pid` và `agent.ready` persist có thể stale.

PID file tự nó không phải process authority. Hãy kiểm tra PID bằng `kill -0` và `ps` trước khi tin cậy.

Nếu process cũ không còn tồn tại, hãy restart tcp-agent từ environment đã persist và đợi cho tới khi readiness PID mới khớp với process mới đang sống.

## 10. Ghi chú diễn giải lỗi

Hai lỗi sau thuộc hai failure domain khác nhau:

- `Tunnel target not connected: <id>` — target được yêu cầu chưa đăng ký với relay.
- `connect ECONNREFUSED 127.0.0.1:2222` — relay đã tới đúng target, nhưng dịch vụ SSH downstream không lắng nghe.

Phân biệt này giúp tránh thay đổi kiến trúc tunnel không cần thiết khi lỗi thực tế nằm ở dịch vụ local của target.

## 11. Kết luận closeout

Không phát hiện thêm tunnel architecture defect nào sau khi lifecycle correction được merge.

Implementation đã kiểm thử PASS:

- official lifecycle qualification trên hai target Kaggle độc lập,
- detached-process longevity,
- true-idle SSH,
- target reconnect và route isolation,
- local tcp-agent reconnect,
- final interactive SSH,
- final SCP transfer,
- SHA-256 integrity verification.

Workstream live/resilience vì vậy được **đóng với kết quả PASS** cho implementation đã kiểm thử được liệt kê ở trên.

Chỉ nên mở lại architecture investigation khi có bằng chứng mới mâu thuẫn với qualification này.
