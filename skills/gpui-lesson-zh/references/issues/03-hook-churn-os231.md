# 03 服务重启后 hook 进程 os-231 churn（遗留 hook 未被收养，2.5s 循环拉起）

Status: needs-triage
Type: task

## 现象（2026-10-03 真机实证，S76 取证尾段）

服务重启（部署流程 Stop-Service/Start-Service）而**旧 hook 进程存活**时，进入稳态死循环：

- App HookIpcClient 连接 ~2.5s 即断 → 立即经 broker（command 15）重拉 hook → 新 hook 命中
  `Global\AK97_Hook_SingleInstance_<sid>` 互斥体（旧 hook 持有）自退 → 但其启动期搅动
  max_instances=1 的同名管道 → 旧 hook 服务循环 `ERROR_PIPE_BUSY(231)`（hook.log "所有的
  管道范例都在使用中"）→ App 连接再断 → 循环。
- 频率 ~23 次/分钟；App+Service 各烧 ~2-4% CPU + 日志刷屏（hook.log 12 分钟累计 356 次 231）。
- hook.log 直方图铁证：10:11-15:47（旧时代）每分钟 0-1 次（对应数次重启，均稳定收养）；
  15:48 起每分钟 ~47 次持续不衰。旧时代 App 重启对存活 hook 是良性收养（连接即稳定），
  服务重启清空 broker Process 表（hook_mode_launcher.rs:25-29 注释自认"属源亦有之缺陷"）后
  丧失查重面，陷入循环。2026-10-01 深水退避缓解只覆盖"拉起失败"分支，"拉起成功但秒死"
  路径无退避。

## 现场处置（已做）

taskkill 遗留 hook（session 2 的 AK97-Service.exe --hook，PID 1756，15:47:00 由旧服务拉起）
→ 下一轮 broker 拉起干净接管（互斥体释放）→ 231 冻结、hook.log 呈健康启动、CPU 回 ~0。

## 代码修方向（未实施）

1. HookIpcClient："拉起成功但连接早夭（<N 秒）"路径加退避/去重（对齐 2026-10-01 拉起失败退避）。
2. broker/服务侧：拉起前先探测 hook 管道是否已有存活实例（可收养则不 spawn）——恢复旧时代
   的收养语义，不依赖随重启清空的 Process 表。
3. hook 模式：互斥体拒绝退出前不触碰管道实例（消除对存活 hook 的搅动），或单例检查前移到
   任何管道创建之前（hook_mode_launcher.rs:31 当前已在最前，核对 HookIpcServer::start 前
   是否还有更早的管道面）。

## 验收条件

1. 重启服务（hook 存活）后 hook.log 无 231 增长、App 连接稳定 >5 分钟。
2. 空闲 CPU 不因 hook 域回涨（App <1%）。

## Comments
