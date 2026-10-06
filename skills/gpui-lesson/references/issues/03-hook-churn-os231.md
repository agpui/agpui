# 03 os-231 churn of the hook process after service restart (leftover hook not adopted, 2.5s respawn loop)

Status: needs-triage
Type: task

## Symptom (proven on a real machine 2026-10-03, tail section of the S76 forensics)

When the service restarts (Stop-Service/Start-Service in the deployment flow) while the **old hook process is still alive**, the system enters a steady-state infinite loop:

- The App HookIpcClient connection breaks after ~2.5s → immediately re-spawns the hook via the broker (command 15) → the new hook hits the
  `Global\AK97_Hook_SingleInstance_<sid>` mutex (held by the old hook) and exits on its own → but during its startup it churns the
  same-named pipe with max_instances=1 → the old hook's service loop gets `ERROR_PIPE_BUSY(231)` (hook.log "所有的管道范例都在使用中" — "all pipe instances are in use") → the App connection breaks again → loop.
- Frequency ~23 times/minute; App+Service each burn ~2-4% CPU + log flooding (hook.log accumulates 356 occurrences of 231 in 12 minutes).
- The hook.log histogram is hard evidence: 10:11-15:47 (the old era) saw 0-1 per minute (corresponding to several restarts, all stably adopted);
  from 15:48 onward ~47 per minute, sustained without decay. In the old era, an App restart was a benign adoption for a surviving hook (stable as soon as connected);
  a service restart wipes the broker Process table (the hook_mode_launcher.rs:25-29 comment admits it itself: "属源亦有之缺陷" — "the defect also resides at the source"),
  losing the dedup surface, and the loop begins. The 2026-10-01 deep-water backoff mitigation only covers the "spawn failed" branch; the
  "spawn succeeded but died within seconds" path has no backoff.

## On-site handling (done)

taskkill the leftover hook (AK97-Service.exe --hook of session 2, PID 1756, spawned by the old service at 15:47:00)
→ the next broker spawn takes over cleanly (mutex released) → 231 freezes, hook.log shows a healthy startup, CPU returns to ~0.

## Code fix directions (not implemented)

1. HookIpcClient: add backoff/dedup on the "spawn succeeded but the connection died young (<N seconds)" path (aligned with the 2026-10-01 spawn-failure backoff).
2. broker/service side: before spawning, first probe whether a live instance already exists on the hook pipe (if it can be adopted, do not spawn) — restore the
   old era's adoption semantics, without depending on the Process table that gets wiped on restart.
3. hook mode: when exiting on mutex denial, do not touch pipe instances beforehand (eliminate the churn against a surviving hook), or move the singleton check ahead of
   any pipe creation (hook_mode_launcher.rs:31 is currently the earliest; verify whether any pipe surface exists before HookIpcServer::start).

## Acceptance criteria

1. After restarting the service (hook alive), hook.log shows no growth of 231 and the App connection stays stable >5 minutes.
2. Idle CPU does not climb back due to the hook domain (App <1%).

## Comments
