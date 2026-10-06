# 01 AK97-Service.exe burns 1 core at idle (independent of the App-side fix)

Status: needs-triage
Type: task

## Symptom

2026-10-03 idle CPU forensics (windbg double dump; the App-side root cause is already cracked, see RUN-NOTES S76): AK97-Service.exe (the Windows service instance, not the RDP copy) steadily burns ~1 core at idle (perf counter peak 12.7%/8 cores ≈ 1.0 core). The App-side AK97.exe 1.5-core idle burn has already been fixed by the settings_status_monitor liveness master gate.

## Suspect locations (not yet deep-dived)

- The App's status frames come from the Service engine's `publish_status_changed` (usn_indexer.rs:375-385) / `notify_progress_changed` (:392-399, 100ms throttle); the push consumption lives in usn_service_pipe_server.rs:231-274.
- Service self-busy suspicion: the USN journal watch loop and its status snapshot/publish loop under src/Core/src/drive_monitoring/.
- Forensics before touching code: capture a double dump of the Service and diff with `!runaway`, locate the hot thread stacks, then cross-reference the code.

## Acceptance criteria

1. Service idle CPU drops back to ~0% (same 5s sampling loop as the App side; just change the process name in the script .scratch/ak97_cpu_sample.ps1).
2. Business paths (indexing/query) are unaffected.

## Comments
