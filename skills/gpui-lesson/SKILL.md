---
name: gpui-lesson
description: >-
  AK97 (Rust+GPUI+Win32 IPC) debugging discipline: a symptom-to-disease triage
  matrix, real-machine forensics methods, and red lines for GPUI/Win32/
  lifecycle/C#-to-Rust translation wiring, distilled from five battle
  postmortems in references/. Use when: GPUI window hung/blank, tray or hotkey
  unresponsive, named-pipe timeout/half-open, service alive but not responding,
  Rust Mutex deadlock, sustained idle CPU burn, background timers or
  subscriptions outliving their window, hook process relaunched in a loop,
  backend data arrived but UI stale, command actions silently no-op, pipe
  os-231 in logs, test STATUS_ACCESS_VIOLATION — or before adding window/pipe/
  hook/lock/background-polling/property-notification/subscription code. Triage
  by the matrix first, then act. No generic diagnosis: only paths and tool
  anchors proven in this project.
---

# gpui-lesson: Battle-Tested Debugging Discipline for This Project

> Published from the AK97 project (Rust + GPUI + Win32 IPC). All skill and
> reference documents are in English; quoted log/UI strings from the app may
> remain in the original language.

The full case details of the five postmortems live in this skill's
`references/` directory; this skill is the executable digest: **triage matrix
+ tool anchors + red lines**. For the full case files, read the source
documents by section (paths in §6).

## 1. Symptom → disease triage matrix (triage first, then act)

| Symptom | First check (true criterion) | Disease class proven in this project |
|---|---|---|
| **All windows hung** (even the tray is unresponsive) | `scripts/probe_hung.ps1` / `.sh` → `VERDICT: RED` | Main-thread deadlock: lock-domain deadlock (holding lock A while calling a facility that takes lock B) or high-frequency set_menu re-entry (WER AppHangB1) → opt-01 §3 |
| **Single feature chain dead** (process not hung; tray/menus normal) | End-to-end behavioral criterion (e.g. double-tap Ctrl → app.log `Dispatching hook event id=ACTIVATE`) | Cross-process chain break: service pipe dead → hook relaunch fails → hotkey dead → opt-03 §2 |
| **Service Running but all pipes time out** | Last line of service.log (e.g. `Request received: 9`) | Service-side lock deadlock: same-thread Mutex re-entrant self-deadlock → opt-02 §4 |
| **Process not stuck but CPU sustained high** (idle burn) | Sampling loop `scripts/ak97_cpu_sample.ps1` (RED/GREEN) → cdb **dual dump diff** `!runaway` | Kernel-mode dominated = syscall polling: global singleton × immortal background chains (timers/subscriptions that do not die with the window) → opt-04 §3-4 |
| **Window pops up but blank / nothing rendered** | wenum size + real `IsWindow` check on the slot handle | GPUI default window has no bounds; dirty slot HWND (dead handle after window close) → opt-01 root cause 4 |
| **Intermittent, unstable reproduction** | Find the time window: build-time lock holding × user operation overlap | "Intermittent = time window", not randomness → opt-02 §7.4 |
| **Launch/retry counter climbing linearly** | grep `round N` | Missing self-heal + dead dependency; the counter is the canary → opt-03 §7.6 |
| **`Hook process launched` flooding** (hotkey works intermittently) | Per-minute histogram of hook.log: `grep -E "Another hook instance\|os error 231" hook.log \| count per minute` | Service restart + surviving leftover hook → os-231 churn (2.5s relaunch loop); killing the leftover hook cures it → opt-04 §7 |
| **Backend data arrived but UI list/state stale** (logs confirm arrival) | Walk the data→VM notify→window bridge→view chain link by link: does the property notification exist, is the forwarding subscription alive | Translation-wiring surface, three defects: CollectionChanged dropped / child→parent forwarding subscription discarded via `let _` / debounce missing Cancel → opt-05 §3 |
| **Command-path action silently ineffective** (no log, no error, no effect) | grep action sites for `TODO(port)` + `let _ =`; a silent no-op is indistinguishable from success | Route/dispatch site never wired (TODO(port)[N] no-op) → opt-05 §3-D2 |
| **Pipe os-231 in logs (activation/launch)** | First classify identity: expected transient (short Debug backoff) or churn symptom (histogram) | Two diseases: churn relaunch loop (→opt-04 §7) or max_instances=1 inherent busy window (**benign transient, do not treat as the root cause** — the real culprit is usually elsewhere; an amplifier of misjudgment) → opt-05 §2 |
| **Test process STATUS_ACCESS_VIOLATION (no RUST_BACKTRACE stack)** | Check struct field declaration order: is the RAII subscription-handle field declared after the notification-source field | Drop order: Rust drops in declaration order; the subscription handle must be declared before the source to be safe → opt-05 §3 |

**Three watershed questions**: ① Is the process hung? (probe_hung answers with
one run.) ② Which chain does the symptom live on? (end-to-end behavioral
criterion.) ③ Is the process idle or busy? (CPU sampling loop — if busy, the
dual dump diff catches the hot stack red-handed; no instrumentation, no
reasoning.) These three questions divert 80% of wrong directions.

## 2. Diagnostic toolbox (all archived and reusable)

Scripts come in pairs per platform: Windows uses PowerShell (.ps1), Linux
uses bash (.sh). The Windows side is the path proven in this project; the
Linux side is the same-shaped cross-platform counterpart (X11 / /proc
tooling), not proven on this project's real machine — each script's header
comment states its verdict caliber.

| Tool | Purpose | Real invocation form |
|---|---|---|
| `probe_hung` | IsHungAppWindow enumeration to verdict hung (red/green; Linux has no GUI-hang API, degrades to process liveness + D-state thread detection) | Windows: `powershell -ExecutionPolicy Bypass -File scripts/probe_hung.ps1 [process-name]`; Linux: `bash scripts/probe_hung.sh [process-name]` |
| `probe_dump` | MiniDumpWriteDump / gcore dump capture | Windows: `powershell -ExecutionPolicy Bypass -File scripts/probe_dump.ps1 <pid> [out.dmp]`; **service session (Services) requires admin**, err=5 means permissions; Linux: `bash scripts/probe_dump.sh <pid> [prefix]` (gcore, mind ptrace_scope) |
| cdb (WinDbg) | Dump capture + stack analysis | Capture: `"/c/Tools/Program/WinDbg/WinDbg(x64)/cdb.exe" -p <pid> -c ".dump /ma <out>.dmp; qd"` (**dual dumps 5-10s apart, diff to localize the hot thread**); analyze: `cdb -z <dmp> -y "F:\...\src\shared-target\release" -c "!runaway 7; ~*k 60; qd"`; symbols = the .pdb from the same release batch (**reconcile md5 against the deployed exe — mandatory in the strip=true era**) |
| CPU sampling loop | Idle CPU red/green criterion | Windows: `scripts/ak97_cpu_sample.ps1 -Samples 5 -Interval 2` (process names built in: AK97/AK97-Service/lff); Linux: `bash scripts/ak97_cpu_sample.sh -n 5 -i 2 <name>...`; caliber: `\Process` / jiffies counters are "per-core sums", **divide by logical core count** to match Task Manager / top; multi-instance: PID-wise TotalProcessorTime diff (wildcard counters take max, not sum) |
| URI remote control | Tray-free HITL window-open verification | `Start-Process 'ak97://settings'` (uri_router route_settings); pair with `scripts/ak97_capture.ps1`/`.sh` for screenshot reading + `scripts/ak97_wenum.ps1`/`.sh` for visible-window enumeration (wmctrl/xdotool) |
| `[DBG-xx]` instrumentation pincer | Pin the dead point to a line | Place anchors along the critical path → trigger on the real machine → see between which two anchors it died → densify one round; **must clean up at the end** (`scripts/cleanup_dbg.ps1` / `.sh`, grep count back to zero) |
| Single-variable bisection + control knife | View layer vs framework layer | Each cut changes exactly one variable; the control knife hangs a view already proven innocent into the suspect chain |
| wenum / screenshots | Window true state / coordinates | AK97 source repo `docs/09-test/test-01/drive-*.ps1` (not shipped with this skill); tray synthetic right-click needs DOWN/UP ≥120ms apart |

**Dump authenticity double-check** (PID reuse trap, stepped on in practice):
`service_dispatcher`/`run_as_service` in the stack = the real service;
GPUI/QuickSearchWindow stacks = the App. Record the target PID's start time
before capturing.

## 3. Red lines (read before writing code; every line paid for empirically)

### Locks (two deadlocks of the same pattern in this project: holding lock A while calling a path that takes a lock)

- **std::Mutex is not re-entrant**: within a lock-held scope, every method
  call must be proven not to touch the same lock through its transitive
  closure. Semantic convenience methods (set_drive_state→...→lock) die
  through three layers of wrapping all the same.
- Countermeasures: ① split out a `_locked` already-locked internal form
  (project precedent: `UsnIndexer::set_drive_state_locked`); ② callbacks take
  only `&mut Shared`; ③ provide already-locked variants at API design time —
  no after-death patches.
- **No calls inside a lock**: logger (LOG_STATE global lock), component APIs,
  any `lock()`. Logging/callbacks always move out of the lock domain (log
  after `drop(guard)`).

### Lifecycle / background chains (the price of global singletons, opt-04 evidence)

- **When C#'s "new per window + Dispose" is translated into OnceLock global
  singletons, every background chain (timer/subscription/polling) must get an
  equivalent lifecycle gate**: an aliveness guard (precedent:
  `settings_window_alive()` master switch, pre-checked at **both** the
  interval tick and the dispatch CAS) or symmetric start/dispose APIs. A fix
  that only touches the loop body without checking the trigger source's
  lifecycle is wrong — a "break when drained" loop cannot defend against
  "someone keeps feeding".
- **Dispose must not be "can only die, never reborn"**: after abort/cancel,
  if there is no restart API, the window-close hook becomes permanently mute
  once reachable (precedent: status_monitor disposed, reopening the settings
  window no longer refreshes — a buried landmine).
- Handle/window-slot aliveness is always a real `IsWindow` check, **never
  `is_some`** (dead-handle family); query functions only snapshot inside the
  lock, Win32 calls stay outside.
- Source-code gate tests (include_str! slices): anchors get pre-hit by **the
  test's own literals** — anchor on real signatures (including `&self`), not
  hand-typed forms from the test.
- Brief idle-CPU spikes: check the business fingerprint first (service.log
  USN "Applying USN records" density) before judging regression —
  **legitimate business self-heal ≠ defect relapse**.

### Translation-wiring surface (WPF/C#→Rust semantics-loss family — opt-05 evidence, S82/S83 five defects)

Parity (indexing/sorting/event flow) and all-green unit tests **cannot stop**
this family of defects: they are wiring surfaces lost in C#/WPF semantic
translation, exposed only by real-machine HITL. Each is encoded as
trigger / first-line fix / fallback:

- **Property notification / CollectionChanged lost** (precedent:
  replace_results mutates the collection but never notifies("Results")).
  Trigger: backend data arrived, view stale. First-line fix: add
  `property_changed.notify("property name")` at the mutation point. Fallback:
  the silent no-op audit surface from item 5 of this section (single source
  of truth against drift).
- **Child→parent property forwarding subscription discarded at construction
  via `let _ = _sub`** (RAII unsubscribe handle; Drop = unsubscribe;
  precedent: search_vm/monitor_vm forwarding subscriptions in
  QuickSearchViewModel::new's two-stage assembly). Trigger: no child VM
  property propagates upward. First-line fix: collect handles into a
  `_*_subs` field that lives with the host. Fallback: clippy/review ban on
  `let _ = *_sub*`.
- **Subscription-handle field drop order** (precedent: handle field declared
  after the notification-source field → source dropped before subscription →
  RAII Drop dereferences a dangling pointer → STATUS_ACCESS_VIOLATION).
  Trigger: stackless segfault in tests/runtime. First-line fix: handle field
  declared **before** the source field it points to (Rust drops in
  declaration order). Fallback: when adding an RAII handle "pointing at a
  sibling field", re-verify declaration order (REVIEW checklist item).
- **Debounce/lifecycle token missing Cancel** (precedent: queue_search
  replaces the token slot without cancelling the old token — the source
  `_debounceCts?.Cancel()` was lost). Trigger: rapid-fire prefix tasks all
  fire together out of order on expiry; survivors dropped by stale guards.
  First-line fix: explicitly `previous.cancel()` before replacing the slot.
  Fallback: regression pin counting "only the last one executes" (old code
  count = number of bursts, necessarily red).
- **Silent no-op ban at action sites** (precedent: route_local_send opening
  the send window is TODO(port)[3], swallowing the payload with no log —
  zero causal relation to os-231, yet it misled two rounds of investigation
  in a row). Trigger: command-path action with no log, no error, no effect.
  First-line fix: wire to the existing command pump/channel. Fallback:
  unwired sites must Warn-log with an explicit marker; bare
  `let _ = ...` payload swallowing is banned; grep-audit the
  dispatch/route/handler surface before release.

### GPUI (gpui-kit 0.6.1)

- Hard form per window: `gpui_kit::init(cx)` + double-build (inner view
  Entity + true wrapping via `Root::new(view, window, cx)`). Failures from
  bypassing Root are **conditionally triggered** (fine at rest, crashes on
  fast focus/overlay changes) — static reading will not find it;
  **multi-window focus switching must go into real-machine regression**.
- `WindowOptions` must set `window_bounds` explicitly (default window
  size/position anomalies); `IsWindow(Option<HWND>)` (windows 0.62,
  Option-wrapped — different signature from IsWindowVisible's bare HWND).
- Window slots (cached HWNDs) must pass a real `IsWindow` check before
  reuse; close windows via `on_window_should_close` (cancellable) +
  `cx.on_window_closed` (cleanup by WindowId); for tray-reopenable apps,
  closing the last window **must not force quit**.

### Pipes / IPC

- **Half-open connections die silently**: peer death does not always produce
  a read error — read loops must be wrapped in `tokio::time::timeout`
  (project precedent: the event pipe reconnects after 60s of silence).
- **LazyLock channel race**: lazy first-use TX + take-style consumption; if
  first use lands later than the take, silent loss — `LazyLock::force` on
  the take side.
- **Three layers of self-heal** (missing any leaves a hole): in-endpoint
  reconnect (half-open timeout) → dependency restart (hook relaunch restarts
  the service after 20 failed rounds, precedent
  `self_heal_restart_service`) → root-cause ticket.
- Streaming commands (SUBSCRIBE_STATUS etc.) own a dedicated connection;
  separation from the command connection is by design; the service log
  stopping at a command number = the hang point is on that command's
  processing chain.

### Shell / tray (HITL boundary)

- Synthetic clicks on the Shell tray are **unreliable** (right-click needs
  spacing, menu items do not land) — end-to-end verification defers to
  **human clicks + log criteria**; synthesis only for localization
  experiments.
- muda 0.20 has no per-item `set_visible`; dynamic show/hide is carried by
  rebuild/set_menu, and **must not be triggered on every interaction**
  (high-frequency re-entry hits AppHangB1; low-frequency points like
  language-switch changes only).

## 4. Health criteria (regression checklist)

- Process level: probe_hung all False.
- Behavioral: double-tap Ctrl summons (app.log 41 truly arrives); tray seven
  items, item by item; settings window toggled three times; service log keeps
  rolling (never stops at any `Request received: N`).
- Self-heal degradation evidence: zero new `self-heal` log lines = the
  behavioral criterion that the service-side root cause is truly fixed.
- Idle CPU: sampling loop PEAK <1% (18.7% before the opt-04 fix); hook.log
  `os error 231` zero growth (the criterion that churn is cured).
- Wiring surface: activation pipe re-arm <300ms (regression pin
  `rearm_tests`, measured 263µs); send-window channel contract pins green on
  both positive/negative legs; `grep -rn "TODO(port)" src/App/src` over the
  dispatch/route/handler surface, each entry Warn-marked (silent no-op audit,
  opt-05 §5).
- Multi-window focus-switch regression (the conditional trigger surface of
  the Root contract).

## 5. Channel discipline (three pitfalls stepped on across this diagnostic series)

Tool echoes can be forged (fake Edit success / fake grep output / fake
TaskOutput). Criteria: compiler + `git -C <root>` real output as the only
ground truth; minimal read-back after write + compile verification; **pin the
cwd with an explicit cd on every command** (two-level drift between repo root
and src/ is the main source of fake paths); when find/grep hits zero, suspect
the cwd before suspecting the file does not exist.

## 6. Source documents (take sections as needed for the full case files)

English translations of the original case files; quoted log/UI strings stay
in the original language.

- `references/opt-01-gpui-tray.md` — settings window hang, six root causes /
  instrumentation pincer to the line / control knife / tray Chinese-ization &
  Send wiring / coordinate anchors.
- `references/opt-02-PipeServer.md` — service self-deadlock causal chain /
  cdb dual-arm real stacks / PID reuse trap / lock API design lessons.
- `references/opt-03-ctrl.md` — hotkey chain anatomy / dual-session service
  orphan pit / half-open self-heal / three-layer self-heal stratification.
- `references/opt-04-cpu.md` — idle CPU 1.5-core windbg forensics chain /
  dual dump diff / lifecycle guard dual preconditions / hook os-231 churn.
- `references/opt-05-activation-pipe-231.md` — os-231 benign transient
  characterization / route-site no-op root cause / translation-wiring
  five-defect family / misjudgment amplifier (Error temporal adjacency) /
  hypothesis-evidence adjudication table.
- `references/issues/01~03` — Service idle-CPU forensics ticket /
  dispose-no-restart ticket / hook churn three fix directions.
- Archived in the AK97 source repo (not shipped with this skill): RUN-NOTES
  S58-S61,S76,S80-S83 (src/migration/RUN-NOTES.md); drive-*.ps1 real-machine
  driving scripts; commit chain
  50f922c/cb231a5/2a5eeb6/69eabe2/8bed5b7/ac424aa/d3c5912/91e64ba/684d710.
