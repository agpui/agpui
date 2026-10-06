# opt-03: Double-Ctrl Hotkey Unresponsive Postmortem — Cross-Process Chain Break and Service-Domain Deep Water

> Distilled from the complete S60b/S60c hotkey-chain diagnostic process. Companion piece: opt-01-gpui-tray.md (settings window freeze and tray).
> Debugging discipline: mattpocock-skills/diagnosing-bugs six phases.

## 1. Background and Symptoms

| Symptom | Key contrast |
|---|---|
| Double-Ctrl does not summon the quick-search window (same after ESC hides it) | **Tray single-click / right-click "显示主窗口" (show main window) genuinely normal** |
| The "禁用快捷键" (disable hotkeys) menu item click "has no effect" | When the hotkey chain is dead, the toggle has nothing to manifest through |
| Process **not frozen** (probe_hung genuinely green, tray chain genuinely alive) | When the settings window freezes, the whole window hangs (detectable) |

Watershed judgment: **healthy process + one functional chain dead = a cross-process IPC chain break**,
a completely different disease from opt-01's "main-thread deadlock, whole window hung".

## 2. Hotkey Chain Anatomy (Normal Chain)

```
User double-clicks Ctrl
→ hook process (low-level keyboard hook, separate process) captures it
   hook.log: "Double-Ctrl detected, sending ACTIVATE."
→ event pipe (named pipe, hook→App one-way)
→ App HookIpcClient read loop (read_message_async)
→ dispatch_event: IpcMessageId::ACTIVATE → on_activated slot
→ handle_global_summon_hotkey() → quick-search window summoned
```

The hook is **launched by the service on the App's behalf** (App sends command 15=LAUNCH_HOOK → service LaunchHookProcessAsync;
elevation is adjudicated on the service side). **The hook's life and death hang on the service pipe's life and death** — this is the key to the whole case file.

## 3. Diagnostic Process (Six Phases Actually Run)

### Phase 1-2 Feedback Loop and Reproduction

- `probe_hung.py` determined the **process was not hung** — ruling out main-thread deadlock (the opt-01 disease),
  narrowing the problem space to "a cross-process link inside a live process".
- End-to-end behavioral criterion: double-Ctrl → whether app.log shows
  `Dispatching hook event id=IpcMessageId::ACTIVATE` (dispatch instrumentation, Debug level).
  **Link health is judged by end-to-end behavior, not by single-process liveness.**

### Phase 3-4 Hypotheses and Evidence (chronological; every step verified on a real machine)

| Breakpoint | Real-machine evidence | Verdict |
|---|---|---|
| hook not detecting? | hook.log `Double-Ctrl detected, sending ACTIVATE` (three times) | hook genuinely detects and genuinely sends |
| ACTIVATE not reaching the App? | app.log (post-rotation window) **zero** Dispatching | **event pipe broken** |
| Why broken? | app.log `Failed to launch hook process (round 5402)` | service pipe dead → **service-proxy launch fails** → hook never (re)starts |
| Is the service dead? | Service process Running; service log ends at `Request received: 9` | **process alive, PipeServer hung** |
| Who sent command 9? | Settings window VM (status_monitor) → `ensure_status_subscription` | **settings window opening → SUBSCRIBE_STATUS stream subscription** |
| Causality confirmed | Settings window toggle → `Request received: 9` → pipe dead (two reproduction rounds: 09:49/10:10) | **causality hammered solid** |

### Causal Experiment (the Key Cut of This Postmortem)

After a clean restart (service + app) the baseline was genuinely green (hook genuinely connected, 41 genuinely delivered, hotkey normal) →
**the user was asked to open the settings window once** → the service log ended at `Request received: 9` (SUBSCRIBE_STATUS)
→ pipe dead (timeout+15), hotkey dead. **Toggling the settings window → pipe dead; causality pinned.**

### Deep-Water Boundary (Honestly Recorded)

On the service side, the `SUBSCRIBE_STATUS` stream loop (`stream_status_updates`: signal.acquire
wait + write_status) looked like a genuine wait at the code level, `ListenLoop` was genuinely concurrent via per-connection tokio::spawn,
and `max_instances=254` was genuinely sufficient — **after eliminating layer by layer, the hang mechanism still lay deeper**
(tokio runtime / driver interaction). A service-process minidump (921KB) was captured; with no cdb/WinDbg available,
**the analysis was honestly left pending** — no conclusions were fabricated.

## 4. Root Cause Structure (Three Independent Root Causes Stacked)

- **Root cause A (service-domain deep water)**: the PipeServer hangs entirely after a SUBSCRIBE_STATUS stream subscription
  (all command pipes connect timeout; the hook-launch command 15 dies the same way).
  Trigger surface: settings window opening (VM construction → status_monitor → subscription). Left open pending dump analysis.
- **Root cause B (service domain)**: an **orphaned user-session service process**. `Restart-Service` replaces only
  the service-session instance (7356→11380); the user-session orphan (9944) survives, and its pipe/hook session
  competes with the new service: hook single-instance guard "Another hook instance is already running"
  + `os error 231` (HookIpcServer Server loop error). After taskkill 9944 the
  whole chain recovered (IpcMessageId(41) genuinely sent).
- **Root cause C (missing App-side resilience)**: hook-launch failure **loops forever with no self-heal** — while the service pipe
  is dead, the proxy launch (command 15) fails forever and round climbs linearly to 5402. The C# source comment admits
  "self-heals once it's reachable" — **the C# has the same disease** (if the service never recovers, it never heals).
- Amplifier: the launch loop retried madly every 2.5s (no backoff), flooding the log and accomplishing nothing.

## 5. Fix (App-Side Self-Heal and Resilience, an Enhancement Beyond the C# — Authorization Anchored in the Code Comment)

| Fix | File:form |
|---|---|
| **Self-heal service restart**: 20 consecutive failed launch rounds (~100s) → `sc.exe stop/start AK97Service` (the verified user was already granted START/STOP at install time, no elevation; same surface as tray_clean_exit) → round resets to zero | hook_ipc_client.rs None branch + `self_heal_restart_service()` |
| **Half-open self-heal**: 60s of silence on the event pipe (when the hook side dies, read silently hangs for real, no Err) → the timeout is converted to LoopError and enters the existing reconnect path | event loop wrapped in `tokio::time::timeout(60s, read_message_async)` |
| **Exponential backoff**: on launch failure 5s→10s→20s→40s (cap 60s), breaking the mad retry | backoff in the None branch |

**Semantic boundary (honest)**: self-heal is a **fallback** — the true root cause of the service PipeServer hang is in
the service domain (A); self-heal only guarantees the hotkey auto-recovers within ~100s and does not fix the service itself.

## 6. Final Real-Machine Verification (user confirmed)

| Item | Result |
|---|---|
| Double-Ctrl after a clean restart (service + app) | ✅ summons (hook initialized successfully + both pipes genuinely connected + 41 genuinely delivered) |
| Tray single-click / right-click show main window | ✅ (control surface, genuinely normal) |
| ESC hide / summon back | ✅ |
| Hotkey auto-recovers after service restart (self-heal) | ✅ fallback path (long-cycle verification pending) |

## 7. Lessons and Discipline Distilled

1. **"Process alive ≠ link alive"**: for every functional chain in a multi-process architecture (service/hook/App),
   health must be judged at the **end-to-end behavioral level** (hotkey = the double-Ctrl behavior); single-process hung probing
   can only rule out one class of disease.
2. **Feature toggles are natural segmented test points**: the causality between the settings-window toggle and the pipe death was
   nailed with one hammer by the three-segment experiment "baseline (closed) → action (open) → retest" — design reproduction
   experiments around toggle-style operations first.
3. **The dual-session pit in the service lifecycle**: a Windows service (session 0) coexists with service instances launched in the
   user session, and `Restart-Service` does not clear user-session orphans — mutual competition / single-instance false rejections /
   pipe misalignment all arise from this.
4. **Half-open connections die silently**: a dead named-pipe peer does not always produce a read error — **the read loop
   must have timeout + reconnect self-heal**; never trust the completeness of read's error notifications.
5. **Layered self-heal**: (1) in-process reconnect (half-open timeout); (2) restart of the dependent service (cross-process self-heal);
   (3) root-cause fix of the service itself (ticket) — missing any of the three layers leaves a hole in the resilience.
6. **The round counter is a canary**: the single number `round 5402` exposed two problems at once, "missing self-heal +
   service-domain death" — counters for persistent failure must exist, and crossing a threshold must trigger an action.

## 8. Open Items

1. The service PipeServer hang mechanism (inside the SUBSCRIBE_STATUS stream) — `ak97_hang.dmp`
   + WinDbg `!analyze -v` / thread stacks; or a service-domain code walkthrough (the stream loop's lock surface).
2. How orphaned user-session service processes arise, and a mechanism to sweep them.
3. Long-term verification of the App-side self-heal (self-heal trigger frequency / user perception of service-restart churn).
4. Final verification of "禁用快捷键" (disable hotkeys) (per the original criterion, once the hotkey chain is healthy).

## 9. Related

- opt-01-gpui-tray.md: settings window freeze (lock-domain deadlock / dirty slots / Root contract) — same window, different disease.
- RUN-NOTES S60 series; `.scratch/single-instance-activate/issues/`.
- Tooling: `.scratch/probe_hung.py`/`probe_dump.py`; drive-*.ps1 (synthetic + HITL).

## 10. Final Chapter (S61): Service PipeServer Hang Deep-Water Root Cause Final Pin and Final Fix (WinDbg-Verified)

### 10.1 Key Lessons from Dump Forensics

- **PID reuse trap**: the first "capture 13200 as administrator" yielded App process stacks — after the service self-heal
  restart, the new App reused PID 13200. A dump must be double-verified by **image name + stack signature**
  (`service_dispatcher`/`run_as_service` present = real service).
- **Dumping a service-session (Services, session 0) process requires administrator** (err=5).

### 10.2 Real Stacks, Both Arms (cdb real analysis, AK97-Service.pdb symbols)

- **Arm 1 (stream task)**: `UsnServicePipeServer::handle_client` (SUBSCRIBE_STATUS)
  → `SearchEngine::get_status` → `Mutex::lock_contended` → `RtlWaitOnAddress`
  (waiting on lock M forever).
- **Arm 2 (initializer thread)**: `SearchEngineInitializer::run` → `build_drives`
  (L49 already holds M) → `set_drive_state` → `set_drive_state_reset_counts`
  → acquires M again (same-thread reentry on a non-reentrant std Mutex) → **permanent self-deadlock**.

### 10.3 The Real Fix

`UsnIndexer::set_drive_state_locked(&mut UsnIndexerShared, drive, state)`
(a pub(crate) lock-already-held internal variant); the reentry point in build_drives now calls it; a full-repo scan found no same-shaped pattern.
Gate: core 376/0 + clippy 0; md5 identical across the three deployment sites; commit cb231a5.

### 10.4 Causal Chain Full Closure

Settings window opens → VM status_monitor → command 9 SUBSCRIBE_STATUS stream subscription →
the initializer (build phase) happens to hold M and self-deadlocks → get_status waits on M forever (the stream task occupies the connection)
→ the service PipeServer command chain starves → hook launch (command 15) fails → hotkey dead.
The App self-heal (20 rounds of service restarts) is the fallback; after this fix the initializer no longer self-deadlocks and the service no longer hangs.
