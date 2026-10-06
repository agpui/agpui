# opt-02: Service PipeServer Hang Deep-Water Root Cause Postmortem — Same-Thread Mutex Reentrancy Self-Deadlock

> Dedicated postmortem for the S60b/S60c/S61 series (service PipeServer hang).
> Companion pieces: opt-01-gpui-tray.md (settings window freeze), opt-03-ctrl.md (hotkey chain and self-heal).
> Debugging discipline: mattpocock-skills/diagnosing-bugs six phases; forensics: WinDbg cdb + minidump.

## 1. Background and Symptoms

| Symptom | First-instinct intuition (wrong) |
|---|---|
| Service process Running, but App connections to the service pipe all `connect timeout` | Service crashed (wrong: process alive) |
| hook process launch fails, round climbs linearly (370→5402) | hook itself broken (wrong: the launch command goes through the dead pipe) |
| Double-Ctrl hotkey dead, cannot summon back after ESC | Summon logic broken (wrong: event chain broken at its source) |
| Clicking "禁用快捷键" (disable hotkeys) has no effect | toggle broken (wrong: the hotkey chain is dead as a whole, nothing left to manifest) |
| Service log ends at `Request received: 9` with zero activity after | Log rotation (wrong: genuinely hung) |

**Watershed**: `Request received: 9` = `SUBSCRIBE_STATUS` (streaming status subscription).
The service stops responding entirely after processing this command — the hang point is inside the stream subscription or downstream of it.

## 2. Causal Chain (Nailed by Three Reproduction Rounds)

```
Settings window opens
→ SettingsViewModel::new → status_monitor
→ ensure_status_subscription → command 9 SUBSCRIBE_STATUS (stream subscription)
→ on the service side, exactly inside SearchEngineInitializer::run (build phase):
     build_drives already holds the UsnIndexer.shared lock (M)
     → set_drive_state → set_drive_state_reset_counts → acquires M again
     → std::Mutex is non-reentrant → permanent same-thread self-deadlock (arm 2)
→ stream task handle_client → get_status → waits on M forever (arm 1, occupies that connection)
→ service command-processing chain starves (every PipeServer command connect timeout)
→ hook launch (command 15 LAUNCH_HOOK) fails → hook never starts → hotkey dead
→ App-side hook-launch infinite loop (round 5402)
```

**Trigger condition** (why it is not deterministic): it fires only when the time window of the
initializer build phase (service startup or drive rebuild) overlaps with the first opening of the
settings window — opening the settings window right after a cold start is the most likely to hit it;
once the service is ready, build_drives has already finished and no longer holds the lock, so it never
reproduces. That is the entire truth behind the "intermittent" label.

## 3. Diagnostic Process (Six Phases Actually Run, Detours Recorded Deliberately)

### Phase 1-2: Feedback Loop

- **probe_hung** (IsHungAppWindow) proved the App process was not hung — narrowing the problem space from
  "process deadlock" (the opt-01 disease) to "a cross-process link inside a live process".
- End-to-end criterion: double-Ctrl → app.log `Dispatching hook event id=ACTIVATE`.
- The reproduction experiment used a **toggle-style design**: clean restart (service + app) →
  baseline genuinely green (hotkey alive) → open the settings window once →
  service log ends at `Request received: 9`, pipe dead, hotkey dead.
  Three reproduction rounds (09:49/10:10/19:55); causality hammered solid.

### Phase 3-4: Hypothesis Notes (Detours on Record; the Value Is the Lessons)

| Hypothesis | Real-machine/tooling evidence | Verdict |
|---|---|---|
| Log-rotation illusion | Service log genuinely ends at command 9 | Ruled out |
| Service crashed | tasklist: process Running | Ruled out (process alive ≠ link alive) |
| Instance count exhausted (max_instances) | create_pipe_instance=254 actually read | Ruled out |
| Listen loop blocked | ListenLoop tokio::spawn per connection, concurrent | Ruled out |
| Stream loop itself deadlocked | signal.acquire wait in a normal shape | Ruled out (hang point further upstream) |
| **dump analysis** | See §4 | **Final pin** |

### Deep-Water Tooling Battle (Methodological Focus)

1. **minidump capture**: a ctypes wrapper over `MiniDumpWriteDump` (probe_dump.py).
   User-session processes can be captured directly; **the service session (Services, session 0) requires administrator** (err=5).
2. **PID reuse trap (one of this postmortem's biggest lessons)**: the first "capture 13200 as administrator" yielded
   App process stacks — after the service self-heal restart, the **new App reused PID 13200**. A dump's authenticity must
   be double-verified by **image name + stack signature** (`service_dispatcher`/`run_as_service` present means a
   real service; `QuickSearchWindow`/GPUI stacks mean the App).
3. **cdb real analysis**: `cdb -z dump -y <pdb-dir> -c "~*k 60; qd"`,
   symbols from `src/shared-target/release/*.pdb` (same build batch as the exe, version matched digit for digit).

## 4. Deep-Water Root Cause Final Pin (cdb Real Stacks, Both Arms)

### Arm 1 (stream task, waiting on the lock)

```
UsnServicePipeServer::handle_client (SUBSCRIBE_STATUS closure)
→ SearchEngine::get_status
→ std::sync::mutex::futex::Mutex::lock_contended
→ KERNELBASE!WaitOnAddress / ntdll!RtlWaitOnAddress   ← waits on M forever
```

### Arm 2 (initializer thread, the lock holder self-deadlocks)

```
SearchEngineInitializer::run
→ UsnIndexerBuildExtensions::build_drives        ← L49: already holds M (shared.lock)
   → set_drive_state("indexing")                 ← L68: called while holding the lock
      → set_drive_state_reset_counts
         → shared.lock()                          ← same-thread reentry on a non-reentrant Mutex
→ permanent self-deadlock (M never released; this thread waits on the very lock it holds)
```

**Root cause classification**: not the classic ABBA of two threads waiting on each other, but a **same-thread
Mutex reentrancy self-deadlock** (std::sync::Mutex is not reentrant; reentry is undefined behavior/deadlock).
Arm 1 is merely the victim — every subsequent service path that needs M starves, and PipeServer is simply
the first one the user can see.

### Code Locations

- `Core/src/indexer/usn/usn_indexer_build_extensions.rs`:
  `build_drives` holds the lock at L49; calls `set_drive_state` while holding the lock at L68;
  the same file has one more same-shaped callback injection at L95 (`set_drive_state: &|...|`) — a reentry risk surface.
- `Core/src/indexer/usn/usn_indexer.rs`:
  `set_drive_state` → `set_drive_state_reset_counts` → `shared.lock()`.

## 5. The Real Fix

```rust
// usn_indexer.rs: lock-already-held internal variant (pub(crate), split out with the same semantics)
pub(crate) fn set_drive_state_locked(shared: &mut UsnIndexerShared, drive: &str, state: &str)

// usn_indexer_build_extensions.rs: the reentry point now calls this (while holding M)
UsnIndexer::set_drive_state_locked(&mut shared, drive, "indexing");
```

- Gate: core 376 passed/0 failed + clippy 0; md5 identical across the three deployment sites; commit cb231a5.
- **Remaining risk surface (open item)**: the L95 callback injection inside build_extensions and the other
  `set_drive_state*` call sites need a same-pattern audit in a later wave (this fix only removed the empirically confirmed trigger point).

## 6. Verification

- After deployment: the service log no longer stops at command 9 (keeps rolling); repeated opening/closing of the settings window causes no hang;
- The App self-heal (20 rounds of service restarts) is demoted to a pure fallback and should no longer trigger in the normal state
  (zero new `self-heal` log entries = behavioral-level evidence the fix works);
- Hotkey chain: hook genuinely connected + 41 genuinely delivered; double-Ctrl normal (confirmed by the user on a real machine).

## 7. Lessons and Discipline Distilled

1. **std::Mutex is not reentrant** — while holding the lock, calling any method that "may acquire the same lock again" (even
   a semantically convenient method wrapped three layers deep) is a self-deadlock. Three countermeasures, pick one:
   (1) split out a `_locked` internal variant (this fix); (2) pass only `&mut Shared` to callbacks/closures;
   (3) switch to ReentrantMutex (reentrancy counting has a cost; use with care). **Design the "lock-already-held
   variant" into the public surface at API design time**, not as a patch after the deadlock.
2. **Held-lock segment review rule**: every method call appearing inside a `lock()` scope must be proven
   not to touch the same lock through its transitively passed closures — the compiler does not check this; only review discipline or
   lints like `#![warn(unused_lock)]` can help.
3. **Double verification for dump forensics**: verify authenticity by image name + stack signature; the service session requires administrator; before capturing,
   record the target PID's start time (guards against PID-reuse misjudgment).
4. **Intermittent = time window**: it fires only when the build-phase lock holding overlaps with a user action (opening the settings window).
   When no deterministic path can be found, ask "who holds which lock at which phase".
5. **The service log's "last line" is the golden clue**: zero activity after `Request received: 9` puts the
   hang point on command 9's processing chain — the log's stop point is the investigation's starting point.
6. **Cross-process symptoms, single-process root cause**: the dead hotkey / pipe timeouts all manifest on the App/hook side,
   while the root cause is one lock inside the service process — **do not hunt for the root cause inside the victim process**.

## 8. Related

- opt-01-gpui-tray.md: App-side lock-domain deadlock (STATE×LOG_STATE) — same pattern, different site;
  both deadlocks in this project are "holding lock A while calling a path that takes lock B"; the discipline is the same.
- opt-03-ctrl.md: hotkey-chain self-heal (half-open timeout + service-restart fallback) — after this fix the fallback
  is demoted to pure insurance.
- RUN-NOTES S60b/S60c/S61; commit cb231a5; dumps archived at `.scratch/*.dmp`.
