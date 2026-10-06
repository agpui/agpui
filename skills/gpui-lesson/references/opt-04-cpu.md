# opt-04: AK97 Idle CPU at 1.5 Cores Postmortem — Lifecycle Deviation After Global Singletonization and the windbg Forensics Chain

> Distilled from the full single-round diagnosis of S76. Companion piece: opt-03-ctrl.md (hotkey
> chain breakage — a different presentation of the same status_monitor). Debugging discipline:
> mattpocock-skills/diagnosing-bugs six phases; forensics per ak97-rm-drive (cdb command-line surface).

## 1. Background and Symptoms

| Symptom | Key Contrast |
|---|---|
| User reports ak97.exe CPU sustained above 40%, "actually no business at all" | Task Manager's metric (machine-wide normalized) |
| Measured: idle burn 7.47s per 5s = **1.49 cores** (18.7% of 8 logical cores), 4941s CPU accumulated | 151% under the per-core-sum metric |
| **Zero visible windows** (wenum IsWindowVisible=0), no indexing/query work | The "no business" premise holds |
| AK97-Service.exe also burning ~1 core (12.7%) | Both processes abnormal simultaneously |
| Processes are **not stuck** (windows open, features work) | An entirely different disease from opt-01/opt-03's "hang/freeze" |

Watershed judgment: **healthy process + sustained high burn = something spinning in the background**.
Not a broken chain (opt-03's disease) but an immortal polling chain.

## 2. Anatomy of the Forensics Chain

```
Feedback loop: .scratch/ak97_cpu_sample.ps1
  (Get-Counter \Process(X)\% Processor Time, normalized = CookedValue/logical-core count;
   note this counter's metric is a "per-core sum"; divide by core count to match Task Manager)
→ cdb double dump (.dump /ma, ~10s apart) + !runaway 7 diff
→ Hot thread stacks (symbols=src/shared-target/release/*.pdb, md5 matching all three deployment copies)
→ Stack surface ↔ code surface cross-verification
```

**!runaway morphology**: 33 threads, kernel-mode time overwhelmingly dominating user-mode across the
board (thread 28: user 8:15 + kernel 20:54). Kernel-mode dominance = syscall-dense polling (the
CreateFileW/read_dir family), not a user-mode infinite loop. The double-dump diff beats a single-frame
snapshot: the burn is spread across many threads, a single frame only catches two culprits in the act,
the diff proves all of them are burning continuously.

## 3. Diagnostic Process (Six Phases, Actually Run)

### Phase 1-2 Feedback Loop and Reproduction

- The loop is one command: sample 5×2s, assert idle CPU>40% → RED/GREEN. Deterministic, second-scale,
  agent-runnable. The same loop turning green after the fix = final verification criterion.
- Reproduction normalized: zero visible windows + no work = stable RED, no action needed.

### Phase 3-4 Hypotheses and Evidence (stack→code, file:line at every step)

| Evidence | Real-machine/code verification | Conclusion |
|---|---|---|
| Thread 28 in-act stack | ZwCreateFile→CreateFileW→fs::stat→`LocalDriveSettingsViewModel::update_status`→`SettingsViewModel::apply_ui_state`→(symbol attribution `new`)→**`NetworkDriveSettingsViewModel::spawn_refresh_loop` closure** | the apply path stats local drives every round |
| Thread 30 in-act stack | ZwOpenFile→FindFirstFileExW→read_dir→`get_cached_drives`→**same spawn_refresh_loop closure** | the gather path scans the indexes directory every round |
| Why the loop never stops | The design is "drain pending then break" (network_drive_settings_view_model.rs:559-602); the only feeder is `apply_ui_state` (settings_view_model.rs:546) | **someone keeps feeding, the loop faithfully drains** |
| Who feeds (trigger source 1) | monitor 5s interval tick (settings_status_monitor.rs:71-83); exit condition is only Weak::upgrade failure — the VM is a OnceLock singleton **never dropped** | the timer lives forever |
| Who feeds (trigger source 2) | USN status-stream subscription thread, every frame→schedule_apply_ui_state (monitor.rs:179-184); server pushes throttled at 100ms ≈ up to 10 frames/sec | the frame stream is the burn's dominant frequency; the 5s tick is the lower bound |
| Why a single round is expensive | Each round = per-drive GetVolumeInformationW+Path::exists + WNet enumeration + read_dir+per-.idx CreateFileW header read + WSL registry + user_settings deep copy + full-row INPC | frequency×full-scope×multi-thread=1.5 cores |
| Self-feedback loop? | apply_gathered_data with unchanged structure goes in_place, no re-trigger; all 4 fast_refresh sites sit on user-action paths | **ruled out** (hypothesis falsification record) |

### C# Source Semantic Comparison (the decisive cut for adjudicating "migration deviation")

- Line-by-line isomorphic surface: ApplyUiState/RefreshNetworkDrives/RunRefreshLoopAsync have no guard
  difference between the two sides — **with the window open both sides burn identically; this part is
  a faithful port**.
- Where the deviation lies: the C# VM is **created per window and Disposed on close**
  (SettingsViewModel.cs:44/111, SettingsStatusMonitor.cs:58-60) → the monitor chain does not exist while
  idle; Rust switched to a OnceLock global singleton to fix AppHang (comment at
  app_window_manager.rs:358-361), with cleanup hooked on on_window_should_close (:432-436) but **that
  hook is unreachable / does not cover every window-close path** (the dump proves the timer still alive)
  → the chain lives forever.
- Verdict: **a lifecycle deviation introduced by the port**, not a design flaw shared by both sides.

## 4. Root-Cause Structure

In one sentence: **OnceLock singletonization turned a monitor chain that lives and dies with its window
into an immortal monitor chain, while the cleanup chain (cleanup→dispose) carries no reachability
guarantee** — two layers stacked: lost lifecycle semantics (root) + unreachable close-path hook
(trigger). Fixing either one stops the bleeding; fixing one but not the other leaves a latent problem
(see §8 open item 02).

## 5. Fix (Option A: Single-Point Master Gate, Surgical)

- `app_window_manager.rs` adds `settings_window_alive()`: slot snapshot (inside the lock) + `IsWindow`
  liveness check (outside the lock — lock-scope-narrowing discipline); dead-handle protection reuses the
  2026-09-30 shape (slot not cleared after window close; `is_some` as the liveness test is a known
  defect family).
- `settings_status_monitor.rs` puts guards in front of both trigger points: interval tick before
  refresh_lists (with no window, not even ping/IPC runs), schedule_apply_ui_state before the CAS (frames
  discarded on arrival). With no window the whole chain stands still = equivalent restoration of the
  source lifecycle; the OnceLock singleton and dispose chain untouched (the AppHang fix is preserved).
- Two regression tests: `settings_window_alive_rejects_slot_without_live_hwnd` (rejects empty slot /
  dead handle; behavior surface) + `idle_dispatch_is_gated_on_settings_window_alive` (source gate test:
  both gate sites exist and the guards precede the business calls).
- **include_str! self-inclusion trap**: the gate test uses include_str to read a slice of its own
  source, so literals inside the test code also hit as anchor candidates (the first run failed on
  "dispatch guard missing") — anchors must use the real signature
  (`fn schedule_apply_ui_state(&self)`) rather than a hand-typed shape inside the test.
- Gate: ak97-app full suite **428/0/1** + clippy 0 errors; release rebuild 4m11s; md5 identical across
  all three deployment copies.

## 6. Real-Machine Final Verification

| Cross-section | Before fix | After fix |
|---|---|---|
| AK97.exe idle | 18.7% (1.49 cores) | **0.1~0.3%** |
| AK97-Service.exe idle | 12.7% (~1 core) | **0.0~0.1%** |
| Open-window monitor surface | —— | service panel "运行正常/已就绪" (Running normally / Ready) (guard passes, ping truly arrives, not in error state) |
| After window close | continuous burn | drops immediately |

- Window opening is driven by the `ak97://settings` URI (uri_router.rs:74 route_settings) — **the
  activation pipe doubles as an automation remote for the settings window**, removing the need for
  tray-based HITL.
- The transient 13% peak during final verification = the USN indexer draining that day's build write
  backlog; **legitimate work, self-heals**, not a regression — criterion: the density and
  self-termination of "Applying USN records" in service.log.

## 7. Secondary Finding: hook-domain os-231 churn (independent defect, not introduced by this fix)

Mid-verification, app.log exposed a second loop: `command: 15 → Hook process launched → Connected`,
one round every ~2.5s, forever. Mechanism: service restart (unavoidable during deployment) while the
old hook process survives (Stop-Service does not kill what it spawned) → the new hook hits the session
mutex and exits by itself → churns the same-named max_instances=1 pipe → the old hook's service loop
gets ERROR_PIPE_BUSY (231) → the App's connection breaks within a second and re-pulls. hook.log
histogram as hard evidence: old era 0-1 per minute (restarts were all benignly adopted); from the 15:48
service restart, 47 per minute; 356 total 231s in 12 minutes.

On-site handling: taskkill the leftover hook (`AK97-Service.exe --hook` in session 2) → the next pull
starts a clean takeover, 231 freezes, CPU returns to 0. Three code-fix directions (adoption semantics /
early-death backoff / do not touch the pipe before the mutex rejection) filed as issue 03. **Same
origin as opt-03 §10**: both are state mismatches in the hook/broker domain under the "service restart
transaction"; opt-03 fixed the hung service, this one is the leftover stump.

## 8. Lessons and Discipline Distillation

1. **Idle-CPU diagnosis routine**: first build a perf counter feedback loop (mind the per-core-sum
   metric; divide by logical core count), then cdb double-dump diff `!runaway` — kernel-mode dominance
   = syscall polling; catch the culprits directly by their stacks, no instrumentation needed.
2. **Symbol pre-check**: in the strip=true era, PDBs and deployed exes must be explicitly reconciled
   (md5 identical across all three copies), otherwise stacks are unreadable; point cdb `-y` at the same
   directory as the build.
3. **A "drain-then-break" loop design cannot defend against "someone keeps feeding"** — when
   investigating a busy CPU, check the trigger sources' lifecycle first, then the loop body.
4. **Ported lifecycle deviation is a defect class**: when translating C#'s "create-per-window +
   Dispose" into a global singleton, every background chain must be given an equivalent liveness guard
   or a symmetric start/dispose API; the Rust counterpart of Dispose must not be "can only die, cannot
   be born" (open item 02).
5. **Dispatch discipline for architect deep-dives**: the main session only does forensics
   (loop/dumps/stacks/call-site location); root-cause reasoning and fix design are dispatched to
   subagents (reports must carry file:line evidence and separate proven from conjectured); when the
   vendor is unavailable, degrade to general-purpose with the same prompt rather than blocking.
6. Pitfall archive: in Git Bash, inline PowerShell's `$_`/`$n` get expanded — always drop into a .ps1
   file; the `\Process(X*)\` wildcard takes max rather than sum across multiple instances; per-PID
   TotalProcessorTime deltas are the accurate method.

## 9. Remaining Open Items

`.scratch/ak97-idle-cpu/issues/`:

1. **01 Service-side idle core burn**: old-era evidence is lost to log rotation; currently measured
   0.0% (suspected to be forced busy by the App's subscription); reproduction conditions and
   independent forensics still to be established.
2. **02 dispose has no restart API**: once should_close becomes reachable, cleanup permanently kills
   the monitor chain → reopening the window no longer refreshes; fix = Option B (symmetric
   start/dispose + resume on window open).
3. **03 hook os-231 churn**: mechanism/handling/three directions in §7; code fix pending.

## 10. Related

- opt-03-ctrl.md: a different presentation of **the same status_monitor** — in opt-03 it fires
  SUBSCRIBE_STATUS (command 9) the moment the window opens, crushing the service initializer; in this
  post it keeps polling and burning CPU after the window closes. The lifecycle of the settings-domain
  background chain is the shared weak point.
- RUN-NOTES S76; `.scratch/ak97-idle-cpu/issues/01~03`.
- Tools: `.scratch/ak97_cpu_sample.ps1`/`ak97_cpu_by_pid.ps1` (feedback loop),
  `ak97_cpu_d1/d2.dmp`+`ak97_d2_stacks.txt` (forensics), `ak97_capture.ps1`/`ak97_wenum.ps1`
  (real-machine surface).
