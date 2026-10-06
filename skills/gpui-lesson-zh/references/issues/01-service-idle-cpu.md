# 01 AK97-Service.exe 空闲烧 1 核（独立于 App 侧修复）

Status: needs-triage
Type: task

## 现象

2026-10-03 空闲 CPU 取证（windbg 双 dump，App 侧根因已破，见 RUN-NOTES S76）：AK97-Service.exe（Windows 服务实例，非 RDP 副本）空闲时稳定烧 ~1 核（perf counter 峰值 12.7%/8 核 ≈ 1.0 核）。App 侧 AK97.exe 的 1.5 核空烧已由 settings_status_monitor 存活总闸修复。

## 嫌疑位置（未深挖）

- App 的状态帧来自 Service 引擎 `publish_status_changed`（usn_indexer.rs:375-385）/`notify_progress_changed`（:392-399，100ms 节流）；推送消费在 usn_service_pipe_server.rs:231-274。
- Service 自忙嫌疑：src/Core/src/drive_monitoring/ 的 USN journal 监视循环与其状态快照/发布循环。
- 先取证再动码：Service 抓双 dump 差分 `!runaway`，定位热点线程栈后对照代码。

## 验收条件

1. Service 空闲 CPU 回落到 ~0%（与 App 侧同款 5s 采样回路，脚本 .scratch/ak97_cpu_sample.ps1 改进程名即可）。
2. 业务路径（索引/查询）不受影响。

## Comments
