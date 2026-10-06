# 02 No restart API after SettingsStatusMonitor dispose (latent bug: close window → reopen does not refresh)

Status: needs-triage
Type: task

## Background

The S76 idle CPU fix adopted Option A (interval tick + ScheduleApplyUiState with a settings_window_alive master gate), keeping the OnceLock singleton and the dispose chain untouched. But the dispose chain itself is asymmetric:

- `SettingsStatusMonitor::dispose()` (settings_status_monitor.rs:109-114) aborts the timer and cancels the subscription, after which **there is no restart API at all** (once refresh_timer is taken to None, it is gone permanently).
- cleanup is hung on the on_window_should_close hook (app_window_manager.rs:432-436). If that hook fires on some window-close path, the monitor chain dies permanently — after reopening the settings window, the status page no longer refreshes (the 5s polling is dead, the subscription is dead).
- S76 dump evidence shows the hook did not fire on the current instance (the timer is still alive), so this bug has not been observed by users; but it is a latent landmine: the day the hook's reachability gets fixed (full coverage of close paths), this bug manifests immediately.

## Fix approach (C# semantics comparison)

On the C# side the VM is created per window, so Dispose and construction are naturally paired. After the Rust singleton, a symmetric `start()` must be added: rebuild the interval task + re-attach the subscription with a new child_token; the window-open closure (at the point where open_settings_window_cmd succeeds in creating the window) calls resume. Mind the stacking semantics with the S76 liveness master gate (between dispose and start the guard is always false, which is harmless).

## Acceptance criteria

1. Open the settings window → close it (triggering cleanup) → reopen: the status page resumes refreshing within 5s (ping/status/network-drive list not frozen).
2. Idle CPU stays at ~0% (no regression of the S76 fix).

## Comments
