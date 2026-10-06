# opt-01: GPUI Tray Menu and Settings Window Hang Fix Postmortem

> Distilled and consolidated from the full S59d/S60/S60b series (RUN-NOTES.md).
> Covers: the seven-item tray icon menu, the settings window, the global hotkey (hook) chain, and the AK97-Service pipe.
> Related skills: mattpocock-skills/diagnosing-bugs, gpui-kit (coding-guides).

## 1. Background and Symptoms

User-reported symptoms, in discovery order:

| # | Symptom | First instinct (wrong) |
|---|---------|------------------------|
| 1 | Tray "double-click does nothing" after rebuild and redeploy | New exe is broken (wrong, see root cause 1) |
| 2 | After the settings window pops up: **white screen, hang**; then the **search window hangs too** and the process exits abnormally | Rendering bug (wrong, see root causes 2/3) |
| 3 | Tray right-click menu disappears, left-click unresponsive | Tray registration broke (wrong — it is deadlock aftermath) |
| 4 | Double-Ctrl hotkey does nothing; after ESC hides the window it cannot be re-summoned | Summon logic broke (wrong, see root cause 5) |
| 5 | Clicking "禁用快捷键" (Disable hotkeys) "has no effect" | toggle broken (wrong — the hotkey chain was already dead, nothing to verify) |

Key lesson up front: **five symptoms, five true root causes, all different from one another**. Every first instinct failed;
each step was re-pinned by programmatic evidence (probe_hung / instrumentation chain / single-variable bisection / real-machine control).

## 2. Diagnosis Methodology (the most reusable part of this postmortem)

### 2.1 Feedback loop first (diagnosing-bugs Phase 1)

- `probe_hung.py`: uses ctypes to call `IsHungAppWindow` and enumerate all top-level windows of the process,
  outputting `hung=True/False` + `VERDICT: RED/GREEN`. **One run settles "is the main-thread message
  pump blocked"**, turning "hang" from subjective feel into a programmatic red/green signal.
- Combined with real PIDs from `tasklist` and real dimensions from `GetWindowRect`, one table pins down the scene.
- For nondeterministic bugs the goal is not a clean reproduction but **raising the reproduction rate**: repeated probes plus sampled real-machine operations.

### 2.2 Instrumentation pincer (locate down to the line)

- Place `[DBG-set]`-prefixed probes along the critical path (command pump receives packet → cmd enter → options → open_window
  → inner view → Root → render enter/exit → HWND extraction → slot assignment → cmd exit → pump return).
- Three rounds of convergence: each round adds anchors only inside the bracketed interval, until the true death point is pincered down to **a single statement**
  ("`slot assigned` fired but the registration log did not" → death point = the log line taken while holding the STATE lock).
- Cleanup: in Phase 6 `grep -c DBG-set` confirms the count reached zero, then scripted removal.

### 2.3 Single-variable bisection + real-machine control knife

- The elimination matrix verifies one variable at a time: Render interaction surface (static placeholder) → `VM::new` construction cost
  (timed by a Rust test, 36ms) → app_id → options matched field-by-field against LocalSendSendWindow →
  PopUp/Normal → VM lifecycle (global singleton).
- **Control knife**: mount the already-proven-non-hanging QuickSearchWindow view into the settings-window command chain
  (no slot registration, pure control). One real-machine operation splits "GPUI layer vs view layer" —
  the result was "quick-search look + no hang", pulling suspicion from deep GPUI back to the view/VM differences.
- Each cut means one deploy and one real-machine verification — **never conclude from reading code alone**.

### 2.4 Dumps and tool boundaries

- `probe_dump.py`: uses ctypes to call `MiniDumpWriteDump` to capture a full dump of the hung process
  (921KB, archived at `.scratch/ak97_hang.dmp`).
- The machine has no cdb/WinDbg, so minidump stack-frame analysis lacked tooling — **record this honestly in limitations**
  and let the control knife fill the gap.
- **CUA (computer-use) window-domain restriction**: it can only operate inside window areas; the Shell tray
  (taskbar / overflow panel) lies outside any window — tray-domain automation therefore uses `drive-click/drive-rclick`
  (synthesized via mouse_event; the DOWN/UP gap must be ≥120ms for the Shell to recognize it) + full-screen screenshots + HITL.

### 2.5 HITL (human hand click) is the only reliable verification in the Shell tray domain

- Synthesized left-click hit once (a locating experiment: toggle count 6→7); synthesized right-click went 0/5→1/1
  (after adding the gap). Menu-item clicks missed repeatedly.
- Conclusion: for end-to-end verification of the tray icon/menu, the standard is **coordinate anchor + human hand click + log criteria**;
  synthesized clicks serve only as locating experiments.

## 3. Root-Cause List (five root causes, all pinned down by programmatic evidence)

### Root cause 1: single-instance guard misfire (the truth behind symptom 1)

Double-click does nothing after rebuild and redeploy — **a stale old instance** (window hidden but process alive, holding the mutex);
the new instance sends ACTIVATE and exits. At the time, a pipe race misreporting os error 231 muddied the judgment.
**Verification**: dual PIDs in tasklist + activation-chain logs (Summon toggle/refocus).

### Root cause 2: calling logger while holding the STATE lock → deadlock in the same mutex domain (the death point of symptom 2)

The instrumentation pincer pinned it: `open_settings_window_cmd` holds `STATE.lock()` from entry;
the `HWND registered` log fires inside the lock and triggers `logger::log` → internally `LOG_STATE.lock()`,
while another thread holding LOG_STATE waits on STATE — an ABBA deadlock.
- **Fix**: narrow the lock scope — `drop(state)` after slot assignment, then log;
  logs use lightweight formatting, and inside the lock no actions beyond formatting/file IO are performed.
- **Evidence**: the `slot assigned` probe fired while the registration-log probe was missing; after the drop, the real machine went genuinely green.

### Root cause 3: high-frequency set_menu reentrancy → AppHangB1 (the truth behind symptom 3)

The S59-introduced "`rebuild_menu` after every menu click" (set_menu full replacement) triggered, at high frequency across repeated clicks,
muda's SendMessage reentrancy into the same-thread tray window; WER recorded
`AppHangB1` (twice at 22:06). After the main thread deadlocked, all windows were hung and tray events got no response at all
(symptom 3). Compounded with root cause 2, the process finally exited abnormally.
- **Fix**: remove the after-every-click rebuild; refresh of dynamic items (single-process / LocalSend switches) is down-frequented
  to culture watch (language change) and process restart.

### Root cause 4: slot holding a stale HWND (sub-form of symptom 2: "popup window does not show")

After the user closed the settings window, the slot still held the dead HWND; the subsequent activation sequence called `ShowWindow` on a dead handle, with no effect.
- **Fix**: validate for real with `IsWindow(Some(HWND(...)))`; a dead handle clears the slot and takes the rebuild path.
- windows 0.62 signature detail: `IsWindow(Option<HWND>)` (wrapped in Option).

### Root cause 5: service pipe dead → hook spawn failed for 1107 rounds → hotkey chain fully broken (symptoms 4/5)

- The service process was alive (AK97Service=Running) but the **PipeServer listener was dead**:
  on the App side `SendPipeCommand failed: connect timeout`; on the hook side, spawn attempts failed for 1107 rounds.
- **Root cause 5a (orphan service process)**: `Restart-Service` only replaced the service-session instance
  (7356→11380); **the user-session orphan 9944 survived**, and its pipe/hook session raced the new service:
  the hook single-instance guard reported "Another hook instance is already running" + os error 231.
  After taskkill of 9944, `Dispatching hook event id=IpcMessageId(41)` genuinely fired and hotkeys recovered.
- **Root cause 5b (why the pipe died)**: the service log stopped at 20:14 (the moment the settings window was first created);
  after that, zero PipeServer activity — the time correlation with multi-window / high-frequency operations was never closed out,
  so it is **filed as a separate ticket** (see §7).
- The truth behind "禁用快捷键 has no effect": hotkeys are carried by the hook process; with the hook dead, the hotkey chain as a whole was inert,
  so the App-side toggle flip had no way to manifest — **not a toggle functional defect**.

### Root cause 6 (contract level): all three windows bypassed gpui-kit Root

All three windows (QuickSearch / LocalSend / settings) had been opened directly with `cx.open_window`, **without mounting
`gpui_kit::component::Root` and without calling `gpui_kit::init`**. The gpui-kit coding-guides warn verbatim:
"Bypassing it can produce behavior that looks correct at rest but fails when overlays nest or focus changes quickly" —
a word-for-word match with "normal at rest, hangs when focus flips between windows".
- **Fix**: `gpui_kit::init(cx)` (at startup) +
  switch window creation to the double-build form: `inner view` + a real wrap in `Root::new(view, window, cx)`
  (authoritative source: crates/kit/src/lib.rs:158 equivalent surface; 0.6.1 has no open_window wrapper,
  so build manually per the docs; `cx.open_window` returns `WindowHandle<Root>`).
- **Verification boundary**: the hang still reproduced after Root was mounted, so the missing Root is **contract debt**, not the direct
  root cause of this deadlock; the bisection did simultaneously prove that the Root + arbitrary view form works (control knife).

## 4. Fix List (file: form)

| File | Fix |
|------|-----|
| `App/src/services/app_window/app_window_manager.rs` | Command marshaling channel (force race fix); `open_settings_window_cmd` (stale-slot guard + gpui-kit double build + HWND extraction + lock-scope narrowing); marshaling for both show/show_entry entries |
| `App/src/app_startup.rs` | Settings-window command pump (take after force) + Root contract enablement path |
| `App/src/views/settings/settings_window.rs` | Current = static placeholder render("设置(完整界面随渲染波次迁移)") (Settings — full UI migrates in with the render wave) + cooperation with the dead-handle guard; VM global singleton wired in |
| `App/src/views/settings/settings_view_model.rs` | `global_instance()` (OnceLock singleton, decoupled from window lifetime) + vm_new timing test |
| `App/src/views/local_send/local_send_app_event_handler.rs` | `open_send_window()` public surface (tray Send wired to the GPUI send window) |
| `App/src/services/tray/tray_icon_service.rs` | ACTIVATE branch wired to the summon chain; take force; VM singleton; removed high-frequency rebuild |
| `App/src/services/tray/tray_menu_controller.rs` | Exit→request_quit; menu-title Chinese-ization (title_for: TranslationManager→zh fallback); menu_groups made a pure function |
| `App/src/services/tray/tray_clean_exit_helper.rs` | request_shutdown→request_quit (stop service + real exit chain) |
| `App/src/services/tray/tray_icon_renderer.rs` | Build-time RGBA embedding + real-alpha recoloring + channel-order correction |
| `assets/`+`scripts/` | tray_icon_16.rgba, tray_translations_zh.json, convert/extract scripts |

## 5. Real-Machine Final Verification Results (user hand clicks, HITL)

| Menu item / behavior | Result | Criterion |
|----------------------|--------|-----------|
| Settings toggle, three consecutive cycles | ✅ | User confirmed "displays normally, no hang" |
| 显示主窗口 (Show main window) | ✅ | QuickSearch window focused with the real image |
| 发送到其他设备... (Send to other devices...) | ✅ | HWND registered count 1→2 increment |
| 干净退出 (Clean exit) | ✅ | Process 0 + service Stopped, both stopped (real log) |
| 退出 (Exit) | ✅ | Process gone (18:03) |
| Left-click toggle | ✅ | Synthesized + hand click, dual channel |
| Double-Ctrl / ESC re-summon | ✅ (after recovery) | hook IpcMessageId(41) genuinely fired + user confirmation |
| 禁用快捷键 (Disable hotkeys) | ⏳ | To be verified the same way once the hotkey chain is restored |
| Settings window X close button | ❌ open item | System-chrome close message unhandled; closing via the taskbar works around it |

## 6. Lessons and Discipline Consolidated

1. **Lock-scope discipline**: while holding a cross-domain lock (STATE), **calling any facility that may itself take a lock is forbidden**
   (logger / component APIs); callbacks and logging always happen outside the lock. The instrumentation pincer is the fastest way
   to locate a lock-domain deadlock.
2. **Count the frequency of event-driven rebuilds**: set_menu/rebuild triggered on every user interaction will, at high frequency,
   hit driver-layer reentrancy. Choose **low-frequency trigger points** for dynamic refresh (language change / lifecycle),
   not every interaction.
3. **Channel races**: LazyLock lazy first-use + take-style consumption = if first use happens after the take, the value is silently
   lost. Force instantiation on the take side with `LazyLock::force`.
4. **Window-slot lifecycle**: windows can be closed by the user; a handle in a slot must pass a real `IsWindow` check
   before it can be reused; a dead handle means clear the slot and rebuild.
5. **gpui-kit contract**: `init` + a real wrap in `Root::new(view, window, cx)` is the mandatory form for every window;
   the failure mode of bypassing it is **conditional** (normal at rest, breaks the moment focus/overlay changes quickly),
   which static code review can hardly catch — **real-machine multi-window focus flipping must enter the regression suite**.
6. **Symptom ≠ root cause**: five symptoms, five root causes; every root cause needs its own independent evidence chain.
   Once every instinct has failed, the programmatic feedback loop is what produces results.
7. **Synthesized-driver boundary**: the Shell tray (taskbar / overflow panel) is unreliable under mouse_event synthesized
   clicks (DOWN/UP needs a gap; menu-item clicks miss); HITL + log criteria are the standard.
8. **Logging infrastructure**: a logger doing single-line file writes (append) carries deadlock and performance risks on both
   fronts in high-frequency / lock-held scenarios; consider lock-free / async redesign (separate improvement).

## 7. Remaining Open Items (separate tickets)

1. **Service PipeServer listener failure**: service alive while the pipe is dead (after multi-window / high-frequency operations);
   the root cause of the fully broken hotkey chain. Zero service-log activity after 20:14. Needs deep digging in the service domain.
2. **Orphan user-session service process**: Restart-Service does not clean up the user-session instance (9944),
   which races the new service. Needs true analysis of the service lifecycle.
3. **hook infinite-loop root cause**: the loop strategy and backoff when spawn fails.
4. **Settings window 12-page content rendering**: per-page controls, GPUI-domain wave (viewport≠bounds,
   unresponsive system chrome X, and the PopUp/Normal form choice are all folded in here).
5. **Tray icon productionization**: placeholder RGBA → theme-icon pipeline, DPI surface (SM_CXSMICON).

## 8. Tools and Scripts Archived (`.scratch/`)

| Script | Purpose |
|--------|---------|
| `probe_hung.py` | IsHungAppWindow enumeration to detect hung (red/green verdict device) |
| `probe_dump.py` | MiniDumpWriteDump dump capture |
| `probe_localsend.py` / `probe_set_localsend.py` | Deployment-config read/write probes |
| `scripts/convert_tray_icon.py` | tray.png→16×16 RGBA (one-time, at build time) |
| `scripts/extract_tray_translations.py` | zh-CN strings → embedded asset (single source) |
| `docs/09-test/test-01/drive-*.ps1` | Synthesized clicks / screenshots / window enumeration (HITL aids) |

Dump archived: `.scratch/ak97_hang.dmp` (921KB, AppHang scene, pending WinDbg analysis).

## 9. Addendum (S60c): AppHang Final Root Cause Settled and Causal Experiments

### 9.1 Instrumentation pincer, final pin

After three rounds of densified instrumentation the death point was settled (timestamp chain; the 08:20:19 and 08:25:01 rounds had the same shape):

```
cmd enter → options → open_window → inner view(107ms)→ SettingsWindow::new(0ms)
→ Root → render enter/exit(1ms)→ open_window Ok → HWND extracted
→ match enter → slot assigned → [cut]
```

Death point = after `slot assigned`, before the registration log — i.e. **calling `logger::log`
while holding the STATE lock** (internally `LOG_STATE.lock()`). Fix: `drop(state)` after slot assignment,
then log. Real machine genuinely green (user: "displays normally, no hang").

### 9.2 Root contract recheck

The bisected placeholder view (holding no VM) still hung → missing Root **downgraded to contract debt**, not the direct root cause
of this deadlock. The control knife (QuickSearchWindow mounted into the settings chain) proved the GPUI second-window layer clean.

### 9.3 Causal experiment on the dead service pipe (the truth of the hotkey chain)

After toggling the settings window, the service log ended at `Request received: 9` (= `SUBSCRIBE_STATUS`
streaming subscription); after that every command hit connect timeout, the hook spawn (command 15) failed,
and hotkeys died; the event pipe (IpcMessageId 41) survived independently. Reproduced twice (09:49/10:10, same command 9).

**Causal chain**: settings window opens → VM (status_monitor) → `ensure_status_subscription`
→ command 9 stream subscription → service-side `stream_status_updates` hangs → command pipe fully dead →
hook spawn (15) fails → hotkeys dead.

- After ruling out, one by one, the service-side ListenLoop / max_instances (254) / stream loop (waiting on signal.acquire),
  the hang mechanism lies deeper — **the dmp is archived pending WinDbg analysis** (tooling missing, recorded honestly as an open item).
- Temporary workaround: restarting the service (Restart-Service) restores hotkeys; the orphan user-session service process
  (9944) needs taskkill cleanup.
- Long term: an isolation surface between SUBSCRIBE_STATUS and command connections (the dual-pipe design already notes
  "subscriptions/commands must be two separate connections" — the true breakpoint is inside the subscription stream, to be settled by the dump).

### 9.4 close-and-clean-up contract landed (multi-window documentation)

- `on_window_should_close`: the settings window explicitly subscribes (return true passes through) —
  Alt+F4 real close verified ✅ (contract hook works); the X button still does not close (the tao layer swallows
  `WM_SYSCOMMAND(SC_CLOSE)`; filed under the tao/GPUI chrome wave).
- `cx.on_window_closed`: app-level subscription, cleanup keyed by WindowId (mutually closing the loop with the settings-window
  slot's IsWindow fallback); the cleanup chain (prewarmer / icon cache / working set) is filed under the window-domain wave.
- **Tray policy** (landing the verbatim quote): "If your app can reopen a window from the dock or tray, choose that policy
  instead of quitting" — the QuickSearch window stays resident (ESC=Hide), last-window-close is rare, and exit semantics
  keep C# parity (OnLastWindowClose).
