# 02 SettingsStatusMonitor dispose 后无重启 API（关窗→重开不刷新潜伏 bug）

Status: needs-triage
Type: task

## 背景

S76 空闲 CPU 修复采用方案 A（interval tick + ScheduleApplyUiState 加 settings_window_alive 总闸），保留 OnceLock 单例与 dispose 链不动。但 dispose 链本身不对称：

- `SettingsStatusMonitor::dispose()`（settings_status_monitor.rs:109-114）abort 定时器 + cancel 订阅后，**没有任何重启 API**（refresh_timer take 成 None 即永久）。
- cleanup 挂在 on_window_should_close 钩子（app_window_manager.rs:432-436）。若该钩子在某个关窗路径触发，监视链永久死亡——重开设置窗后状态页不再刷新（5s 轮询死、订阅死）。
- S76 dump 证据表明当前实例钩子未触发（定时器仍活跃），故此 bug 未被用户观测；但这是潜伏地雷：哪天钩子可达性修复（关闭路径全覆盖），本 bug 立即显形。

## 修法方向（C# 语义对照）

C# 侧 VM 每窗新建、Dispose 与构造天然成对。Rust 单例化后需补对称 `start()`：重建 interval 任务 + 新 child_token 重挂订阅；开窗闭包（open_settings_window_cmd 建窗成功处）调 resume。注意与 S76 存活总闸的叠加语义（dispose 后 start 前守卫恒 false 无害）。

## 验收条件

1. 开设置窗→关窗（触发 cleanup）→重开：状态页 5s 内恢复刷新（ping/状态/网络盘列表非冻结）。
2. 空闲 CPU 保持 ~0%（S76 修复不回退）。

## Comments
