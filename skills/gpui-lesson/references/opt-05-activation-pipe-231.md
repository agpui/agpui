# opt-05: Activation-Pipe os-231 Postmortem — the Loudest Error Is Not the Cause; the Silent no-op Is

> Distilled from the two diagnosis rounds S82→S83 (tickets 07 → 22 → 25 → S83, a chain of misdirection spanning 4 tickets).
> Companion pieces: opt-02-PipeServer.md (same-thread Mutex re-entry), opt-04-cpu.md (global singleton lifecycle).
> Debugging discipline: mattpocock-skills/diagnosing-bugs six phases; forensics: app.log timeline + RM-S83 real-machine screenshots.

## 1. Background and Symptoms

When a second instance launches carrying `ak97://localsend/items/<URL-encoded path>`, the LocalSend
send window sporadically fails to open. app.log shows simultaneously:

| Symptom | First-instinct diagnosis (wrong) |
|---|---|
| `[AppPipeService] Named pipe server error: 所有的管道范例都在使用中。 (os error 231)` ("all pipe instances are in use") | forwarding blocked by 231 (wrong — forwarding silently succeeded) |
| Send window fails to open | caused by pipe-forwarding failure (wrong — the true cause is unrelated to 231) |
| 231 appears intermittently (successes at 15:0x / failure at 16:29) | unstable service loop (wrong — the loop self-heals normally) |
| Ticket 07 already fixed "handle inheritance" | the fix was incomplete, something remains (wrong — inheritance was never the root cause) |

**Full reconstruction of the misdirection structure**: 231 appears at Error level near the moment of
failure and looks like the cause; the real cause (a route-site no-op) has **not a single line of log**.
Two investigation rounds (ticket 07 handle inheritance, S82's initial verdict "231 blocks forwarding")
were both led astray by this loud error.

## 2. Root Cause (two independent defects + one misjudgment amplifier)

### D1: os-231 itself = an inherent transient of max_instances=1 (benign)

The activation pipe uses `max_instances(1)` plus a service loop of "create → connect → read → drop →
create again"; when the client side has not closed yet (the second instance's process exits slowly),
the rebuild necessarily gets ERROR_PIPE_BUSY (231). This is an inherent window of this pipe shape, not
a defect; the server self-heals after backoff, and the client has a 5s retry budget as fallback.

**The defect lies only in the handling**: the old implementation logged at Error level with a 1000ms
backoff — rendering an expected transient as a glaring error and stretching the server's blind window
to a full second.

### D2: The true cause of the send window not opening = a silent no-op at the route site

`uri_router::route_local_send` parses the URL, validates the settings, computes the mode, then:

```rust
// TODO(port)[3]: LocalSendAppEventHandler.OpenSendWindow(...) (...not yet wired...)
let _ = mode;
let _ = (request.files, request.text);
```

The action that opens the send window is a **silent no-op with no log, no error, no effect**. It has
no causal relationship with 231 (hypothesis adjudication: H2 forwarding blocked — ruled out, the
second instance has no Failed log, i.e. the client silently succeeded; H3 service loop dead — ruled
out, continue semantics; H4 mutex check missed — ruled out, no "Pipe servers starting" line).

### Misjudgment amplifier: temporal proximity of the Error log

The 231 appears exactly 9ms after the second instance starts — temporal proximity makes it "look like
the cause". The value of debugging discipline: at the hypothesis-ranking stage, H2/H3/H4 were ruled
out with **existing log evidence**, so there was no third fix in the wrong direction.

## 3. Fix (S83, commit 91e64ba)

| Item | Fix | Regression pin |
|---|---|---|
| D1 | create 231 branch: backoff 1000ms→50ms + log demoted to Debug (expected transient, not an error); other errors keep Error+1000ms | `activation_pipe_rearms_quickly_after_client_lingers`: after a lingering client releases, listening resumes within 300ms — measured **263µs** (the old code necessarily goes red with its full-second failure window) |
| D2 | wire `request_send_window_open_with(files,text)` → the existing SEND_WINDOW_TX command pump (sites AddFiles/ShowTextMode consumed as-is; mode implied by the presence of files/text) | `send_window_channel_contract`: positive (path enters the channel verbatim) / negative (invalid URI produces no request) legs |
| Real machine | `ak97://localsend/items/...` → LocalSend send window opens (RM-S83-01) | max_instances stays 1 (source semantics, zero deviation) |

## 4. Lessons Learned

### Lesson 1: The loudest error is not the cause; the fully unlogged path is the most dangerous

The 231 (Error level, temporally adjacent) misdirected two investigation rounds in a row; the true
cause was a **zero-log silent no-op**. An action site on a command path that is neither wired nor
reporting is indistinguishable from success — this is not a theoretical risk but real damage that made
two rounds of diagnosis wasted.

**Rule**: unwired sites on command/action paths (TODO(port)) must emit a `Warn` log + an explicit
marker; bare `let _ = ...` swallowing payloads is forbidden. Closure means: run one "silent no-op
audit" over dispatch/action-class paths (grep TODO(port) across the dispatch/route/handler surfaces)
and drive it to zero before release.

### Lesson 2: Translation defects cluster on semantic surfaces with no compile-time counterpart, and are entirely invisible to parity tests

The five real-machine defects of S82/S83 (missing Results notification, forward subscription discarded
on the spot, debounce missing Cancel, destructor-order dangling, and this post's no-op) are all
**translation-wiring surfaces** lost when translating C#/WPF semantics → Rust: CollectionChanged, the
CancellationToken.Cancel side effect, event subscription lifecycle, Dispatcher marshaling. They are not
logic errors — golden parity (indexing/sorting/event stream) is all green, unit tests all green; only
real-machine HITL exposes them.

**Rule**: maintain a "wiring checklist" per window/feature (event source → VM notify → window bridge →
view); what headless tests can capture (notification arrival, channel payloads) becomes regression
pins; what they cannot (physical hotkeys, real-window rendering) goes explicitly on the HITL checklist
— a wiring surface not on the checklist counts as never accepted.

### Lesson 3: Discarding an RAII handle with `let _ = _sub` kills the subscription on the spot, and destructor order can produce a segfault

`PropertyChangedSubscription` is a handle that unsubscribes on Drop; `let _ = _sub` discards it at
construction, so the child→parent property-forward chain is born dead. The fix then stepped on a
second layer: **field destructor order** — the subscription-handle field was declared after the
notification-source field, so the source is dropped before the subscription, and the RAII Drop
dereferences a dangling pointer, yielding STATUS_ACCESS_VIOLATION directly.

**Rule**: (1) subscription handles must never be discarded via `let _`; they always go into `_*_subs`
collection fields that live as long as the host; (2) when holding an RAII handle that "points at an
object inside a sibling field", the field holding the handle must be declared before the field it
points into (Rust drops fields in declaration order); (3) each of these two surfaces gets one
structural assertion or a compile-time-visible naming convention.

### Lesson 4: Expected transients must not get Error-level logs, and blind windows need a quantified regression pin

ERROR_PIPE_BUSY (231) is the inherent beat of a max_instances=1 pipe. Error level + 1s backoff let it
(1) pollute the forensics view and (2) stretch the server's blind window 20×.

**Rule**: classify errors by "does it deviate from expectation", not "is the return code nonzero" —
expected transient = Debug + short backoff; and pin the behavior with a quantified pin (blind window
capped at 300ms, measured 263µs). A call "expected to fail" without log-level semantics has no
forensic value.

### Lesson 5: Rank hypotheses using existing log evidence first, to prevent "fixing the first plausible idea"

The three excluded hypotheses this round (H2/H3/H4) each cost exactly one grep (no Failed log from the
second instance / continue semantics / no "Pipe servers starting" line) — cheaper than any blind fix.
Same lesson shape as opt-02/opt-04: falsify first, touch code second.

**Rule**: the 3-5 hypotheses of diagnosing-bugs Phase 3 must each carry an "adjudicable-by-existing-log
criterion" — a hypothesis that existing evidence can rule out is forbidden from entering trial fixes.

## 5. Recurrence-Prevention Checklist (actionable)

1. **Silent no-op audit** (release gate): `grep -rn "TODO(port)" src/App/src --include="*.rs"`, filter
   to the dispatch/route/handler/action surfaces, and confirm item by item whether each "unwired" site
   carries a Warn log; a log-less no-op is a release blocker.
2. **Wiring checklist**: maintain the event→VM→view notify chain tables per functional domain
   (REFERENCES: the per-chapter "unit tables" in docs/spec/lertaro-rsg are ready-made drafts), with
   headless pins and HITL items in two columns.
3. **RAII discipline**: clippy/manual review forbids `let _ = *_sub*`; subscription-handle fields use
   the unified `_forward_subs`-style naming; destructor-order review added to the CODE REVIEW
   checklist.
4. **Log-level semantics**: a binary split between expected transient (Debug + short backoff) and
   unexpected failure (Error + long backoff or abort); every new error branch must declare which side
   it belongs to.
5. **Hypothesis discipline**: every diagnosis must produce a 3-5 hypothesis table + existing-evidence
   criteria, attached to the RUN-NOTES entry (S83 format).

## 6. Related Index

- Tickets: `.scratch/scheme-10-rsg/issues/{07,22,25}-*.md` (07 handle-inheritance audit, 22 os-231 new
  evidence, 25 results echo line)
- Commits: `8bed5b7` (batch), `ac424aa` (S81 pump panic), `d3c5912` (S82 three layers), `91e64ba` (S83,
  this post)
- Screenshots: `docs/09-test/test-01/RM-S8{1,2}-*.png`, `RM-S83-01-send-window.png`
- Ledger: `src/migration/RUN-NOTES.md` S80–S83
- Companion pieces: opt-02 (deadlock), opt-03 (hotkey chain), opt-04 (idle CPU) — all in the same
  "translation-wiring surface" defect family
