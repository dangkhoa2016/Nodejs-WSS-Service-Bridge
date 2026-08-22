# Final Live / Resilience Qualification Report

> 🌐 Language / Ngôn ngữ: **English** | [Tiếng Việt](final-live-qualification-2026-08-22.vi.md)

**Date:** 2026-08-22  
**Repository:** `dangkhoa2016/Nodejs-WSS-Service-Bridge`  
**Result:** **PASS**

## 1. Scope

This report closes the post-merge live qualification of the target-client lifecycle correction introduced by PR #15, `feat(installer): detach target client lifecycle`.

The qualification covered the production-like path below:

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

The live profile used `STREAM_IDLE_TIMEOUT_MS=0`.

This was a qualification of the merged implementation and its operational behavior. It was not a new architecture experiment.

## 2. Lifecycle behavior under qualification

The official installer launches the target client with a detached stdin and, when available, a new session:

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

Important properties:

- `setsid` is used without `-f`.
- `nohup` remains part of the launch path.
- stdin is detached with `</dev/null`.
- `$!` remains the real client PID.
- readiness is bound to that same PID.
- the acceptance contract is `client.pid == client.ready == live client PID`.

The qualification observed detached clients with `PPID=1` and `SID=self` after the installer/notebook cell exited.

## 3. Acceptance matrix

| Qualification | Result |
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

Overall:

```text
FINAL LIVE / RESILIENCE QUALIFICATION = PASS
```

## 4. R2 — true-idle SSH

A single interactive SSH session to Kaggle 1 remained idle for approximately **9 minutes 53 seconds** and then resumed successfully.

No `watch`, polling loop, traffic generator, or application output was used to keep the session active.

This exceeded both the earlier ~120-second failure threshold and the planned 3–5 minute qualification interval.

Result: **PASS**.

## 5. R3 — target reconnect

Kaggle 1 was deliberately stopped and restarted while Kaggle 2 remained connected.

Observed route behavior:

```text
Before restart:  K1 PASS, K2 PASS
During K1 stop:  K1 FAIL, K2 PASS
After reconnect: K1 PASS, K2 PASS
```

The restarted K1 client again satisfied the PID/readiness contract and detached lifecycle checks.

Result:

- K1 temporary outage: **PASS**
- K2 isolation/unaffected route: **PASS**
- K1 automatic recovery: **PASS**
- post-reconnect lifecycle: **PASS**

## 6. R4 — local tcp-agent reconnect

The local tcp-agent was deliberately restarted.

Both local routes were temporarily unavailable during the controlled outage and recovered together after the new agent became ready.

The replacement agent also showed the expected detached process state (`PPID=1`, `SID=self`).

Result: **PASS**.

## 7. Final SSH, SCP, and integrity acceptance

Both target routes passed final interactive SSH.

A canonical 39-byte payload was then transferred over SCP to both targets:

```text
Nodejs-WSS-Service-Bridge final SCP acceptance
```

Canonical SHA-256:

```text
ce2dac1eb72588f3aaf9457ce9053ecd378ffe22269926a219ab6098300a9afc
```

The same digest was verified remotely on both Kaggle targets.

This is the final end-to-end data-path integrity proof for the two SSH/SCP routes.

## 8. Failure-domain boundary

The most important operational distinction established by the qualification is:

> Process detachment protects the client from termination caused by its parent installer shell or notebook cell ending, but it does not and cannot make a process survive a full runtime, container, host, or VM restart.

Two external restarts occurred during qualification:

1. a Kaggle runtime restarted after becoming idle;
2. the local Codespaces/container restarted later.

Both were positively classified as external runtime/host restarts rather than tunnel implementation failures.

A detached process is expected to disappear after:

- Kaggle runtime restart,
- Codespaces/container restart,
- host reboot,
- VM/container destruction.

Do not treat such an event by itself as evidence that PR #15 regressed.

## 9. Recovery guidance

### After a Kaggle runtime restart

System/runtime state may need rebuilding even when `/kaggle/working` persists.

Recommended recovery order:

1. Re-run the official tunnel installer with the same `TUNNEL_ID`.
2. Restore the local service account and SSH runtime if the notebook image lost them.
3. Restore `sshd` on `127.0.0.1:2222`.
4. Verify `client.pid == client.ready == live PID`.
5. Verify process detachment after the installer cell exits.
6. Verify the canonical local route with `ssh-keyscan` or an SSH connection.

### After a local host/container restart

Persisted `agent.pid` and `agent.ready` may be stale.

A PID file is not process authority by itself. Validate the PID with `kill -0` and `ps` before trusting it.

If the old process no longer exists, restart the tcp-agent from the persisted environment and wait until the new readiness PID matches the new live process.

## 10. Failure interpretation notes

These two errors identify different failure domains:

- `Tunnel target not connected: <id>` — the requested target is not registered with the relay.
- `connect ECONNREFUSED 127.0.0.1:2222` — the relay reached the correct target, but the downstream SSH service is not listening.

Keeping this distinction avoids unnecessary tunnel architecture changes when the actual failure is a target-local service issue.

## 11. Closeout conclusion

No new tunnel architecture defect was discovered after the lifecycle correction was merged.

The tested implementation passed:

- official lifecycle qualification on two independent Kaggle targets,
- detached-process longevity,
- true-idle SSH,
- target reconnect and route isolation,
- local tcp-agent reconnect,
- final interactive SSH,
- final SCP transfer,
- SHA-256 integrity verification.

The live/resilience workstream is therefore **closed as PASS** for the tested implementation listed above.

Future work should reopen architecture investigation only when new evidence contradicts this qualification.
