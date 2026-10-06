# opt-04: AK97 空闲 CPU 1.5 核复盘——全局单例化后的生命周期偏差与 windbg 取证链

> S76 单轮诊断全过程的提炼。姊妹篇:opt-03-ctrl.md(热键链断点——同一个
> status_monitor 的另一病相)。诊断纪律:mattpocock-skills/diagnosing-bugs
> 六阶段;取证按 ak97-rm-drive(cdb 命令行面)。

## 1. 背景与现象

| 现象 | 关键对照 |
|---|---|
| 用户报:ak97.exe CPU 持续 40%+,"实际上并无业务" | 任务管理器口径(整机归一) |
| 实测:空闲烧 7.47s/5s = **1.49 核**(8 逻辑核的 18.7%),累计 4941s CPU | 单核 sum 口径 151% |
| **0 可见窗口**(wenum IsWindowVisible=0)、无索引/查询业务 | "无业务"前提成立 |
| AK97-Service.exe 同烧 ~1 核(12.7%) | 两进程同时异常 |
| 进程**不卡**(窗口可开、功能正常) | 与 opt-01/opt-03 的"卡/死"完全异病 |

分水岭判断:**进程健康 + 持续高耗 = 后台有东西在空转**。不是断链(opt-03 病),
是永生的轮询链。

## 2. 取证链解剖

```
反馈回路:.scratch/ak97_cpu_sample.ps1
  (Get-Counter \Process(X)\% Processor Time,归一化 = CookedValue/逻辑核数;
   注意该计数器口径是"单核和",除核数才等于任务管理器读数)
→ cdb 双 dump(.dump /ma,间隔 ~10s)+ !runaway 7 差分
→ 热点线程栈(符号=src/shared-target/release/*.pdb,md5 与部署三处一致)
→ 栈面 ↔ 代码面互证
```

**!runaway 形态学**:33 线程、内核态时间全面压倒用户态(线程 28: user 8:15 +
kernel 20:54)。内核态主导 = 系统调用密集型轮询(CreateFileW/read_dir 家族),
不是用户态死循环。差分双 dump 比单帧快照强:燃烧摊在多线程上,单帧只能抓到
两个现行犯,差分证明全体在持续烧。

## 3. 诊断过程(六阶段真跑)

### Phase 1-2 反馈环与复现

- 回路一条命令:采样 5×2s,断言空闲 CPU>40% → RED/GREEN。确定性、秒级、
  agent 可跑。修复后同一回路转绿 = 终验判据。
- 复现归一:0 可见窗 + 无业务 = 稳定 RED,无需操作。

### Phase 3-4 假设与证据(栈→代码,每步 file:line)

| 证据 | 真机/代码实证 | 结论 |
|---|---|---|
| 线程 28 现行栈 | ZwCreateFile→CreateFileW→fs::stat→`LocalDriveSettingsViewModel::update_status`→`SettingsViewModel::apply_ui_state`→(符号归因 `new`)→**`NetworkDriveSettingsViewModel::spawn_refresh_loop` 闭包** | apply 路径每轮 stat 本地盘 |
| 线程 30 现行栈 | ZwOpenFile→FindFirstFileExW→read_dir→`get_cached_drives`→**同一 spawn_refresh_loop 闭包** | gather 路径每轮扫 indexes 目录 |
| 循环为何不停 | 设计是"排空 pending 即 break"(network_drive_settings_view_model.rs:559-602);唯一喂入口 `apply_ui_state`(settings_view_model.rs:546) | **有人在持续喂,循环忠实排空** |
| 谁在喂(触发源 1) | monitor 5s interval tick(settings_status_monitor.rs:71-83),退出条件仅 Weak::upgrade 失败——VM 是 OnceLock 单例**永不 drop** | 定时器永续 |
| 谁在喂(触发源 2) | USN 状态流订阅线程,每帧→schedule_apply_ui_state(monitor.rs:179-184);服务端 100ms 节流推送 ≈ 最高 10 帧/秒 | 帧流是燃烧主频,5s tick 是下限 |
| 单轮为何贵 | 每轮 = 每盘 GetVolumeInformationW+Path::exists + WNet 枚举 + read_dir+逐 .idx CreateFileW 读头 + WSL 注册表 + user_settings 深拷贝 + 全行 INPC | 频率×全量×多线程=1.5 核 |
| 自反馈环? | apply_gathered_data 结构未变走 in_place,不回触发;4 处 fast_refresh 全在用户动作路径 | **排除**(假设证伪记录) |

### C# 源语义对照(判定"迁移偏差"的关键一刀)

- 逐行同构面:ApplyUiState/RefreshNetworkDrives/RunRefreshLoopAsync 两边无守卫
  差异——**窗口开着两边一样烧,这部分是忠实迁移**。
- 偏差所在:C# VM **每窗新建、关窗即 Dispose**(SettingsViewModel.cs:44/111,
  SettingsStatusMonitor.cs:58-60)→ 空闲时监视链不存在;Rust 为修 AppHang 改
  OnceLock 全局单例(app_window_manager.rs:358-361 注释),cleanup 挂
  on_window_should_close(:432-436)但**该钩子不可达/未覆盖全部关窗路径**
  (dump 证明定时器仍活)→ 链永续。
- 判定:**迁移引入的生命周期偏差**,非两边共有的设计缺陷。

## 4. 根因结构

一句话:**OnceLock 单例化把"随窗生灭的监视链"变成"永生监视链",而清理链
(cleanup→dispose)不具备可达性保证**——两层叠加:生命周期语义丢失(根)+ 关闭
路径钩子不可达(触发器)。hooks 修其一都能止血,修其一不修另一则留潜伏
(见 §8 挂账 02)。

## 5. 修复(方案 A:单点总闸,外科手术)

- `app_window_manager.rs` 新增 `settings_window_alive()`:槽快照(锁内)+
  `IsWindow` 判活(锁外——锁域窄化纪律);死句柄防护复用 2026-09-30 形态
  (窗关后槽不清空,`is_some` 判活是已知缺陷家族)。
- `settings_status_monitor.rs` 两处触发点前置守卫:interval tick 先于
  refresh_lists(无窗连 ping/IPC 都不做)、schedule_apply_ui_state 先于 CAS
  (到帧即弃)。无窗整链静止 = 等价还原源生命周期;OnceLock 单例与 dispose 链
  不动(AppHang 修复保住)。
- 回归测试 2 个:`settings_window_alive_rejects_slot_without_live_hwnd`
  (空槽/死句柄判否,行为面)+ `idle_dispatch_is_gated_on_settings_window_alive`
  (源码守门:两闸位存在且守卫先于业务调用)。
- **include_str! 自包含陷阱**:守门测试用 include_str 读自身源码切片,测试
  代码里的字面量也是锚点候选命中(首次跑挂在"派发守卫缺失")——锚点必须用
  真实签名(`fn schedule_apply_ui_state(&self)`)而非测试里手打的形态。
- 门禁:ak97-app 全量 **428/0/1** + clippy 0 error;release 重建 4m11s,
  三处部署 md5 一致。

## 6. 真机终验

| 断面 | 修复前 | 修复后 |
|---|---|---|
| AK97.exe 空闲 | 18.7%(1.49 核) | **0.1~0.3%** |
| AK97-Service.exe 空闲 | 12.7%(~1 核) | **0.0~0.1%** |
| 开窗监视面 | —— | 服务面板"运行正常/已就绪"(守卫放行,ping 真达,非 error 态) |
| 关窗后 | 持续烧 | 立即回落 |

- 开窗驱动走 `ak97://settings` URI(uri_router.rs:74 route_settings)——
  **激活管道可当设置窗的自动化遥控**,免托盘 HITL。
- 终验中的 13% 短暂峰 = USN 索引器消化当日构建写盘积压,**正当业务,自愈**,
  非回归——判据:service.log "Applying USN records" 密度与自止。

## 7. 次生发现:hook 域 os-231 churn(独立缺陷,非本次引入)

真机验证途中 app.log 暴露第二个循环:`command: 15 → Hook process launched →
Connected`,~2.5s 一轮永续。机制:服务重启(部署必经)而旧 hook 进程存活
(Stop-Service 不杀其代启物)→ 新 hook 命中会话互斥体自退 → 搅动
max_instances=1 的同名管道 → 旧 hook 服务循环 ERROR_PIPE_BUSY(231) → App
连接秒断重拉。hook.log 直方图铁证:旧时代 0-1 次/分(重启均良性收养),
15:48 服务重启起 47 次/分,12 分钟累计 356 次 231。

现场处置:taskkill 遗留 hook(session 2 的 `AK97-Service.exe --hook`)→
下一轮拉起干净接管,231 冻结,CPU 回 0。代码修三方向(收养语义/早夭退避/
互斥体拒绝前不碰管道)入 issue 03。**与 opt-03 §10 同源**:同是"服务重启
事务"下 hook/broker 域的状态失配,opt-03 修的是服务挂死,本条是残肢。

## 8. 教训与纪律沉淀

1. **空闲 CPU 诊断定式**:先建 perf counter 反馈回路(注意单核和口径,除以
   逻辑核数),再 cdb 双 dump 差分 `!runaway`——内核态主导 = 系统调用轮询,
   直接按栈抓现行,不需要插桩。
2. **符号前置核验**:strip=true 时代 PDB 与部署 exe 必须显式对账(md5 三处
   一致),否则栈不可读;cdb `-y` 指向构建同目录。
3. **"循环排空即 break"的设计防不住"有人持续喂"**——查 CPU 忙先查触发源
   的生命周期,再查循环体。
4. **迁移生命周期偏差是一类缺陷**:C#"每窗新建+Dispose"译成全局单例时,
   必须为每条后台链补等价的存活守卫或 start/dispose 对称 API;Dispose 的
   Rust 对应物不可"只能死不能生"(挂账 02)。
5. **architect 深挖的派发纪律**:主会话只做取证(回路/dump/栈/调用点定位),
   根因推理与修复设计派发子代理(报告须 file:line 证据、区分已证实/推测);
   供应商不可用时降级 general-purpose 同 prompt,不阻塞。
6. 小坑存档:Git Bash 内联 PowerShell 的 `$_`/`$n` 会被展开——一律落 .ps1
   文件;`\Process(X*)\` 通配在多实例时取 max 非求和,按 PID 用
   TotalProcessorTime 差分才准。

## 9. 遗留挂账

`.scratch/ak97-idle-cpu/issues/`:

1. **01 Service 侧空闲烧核**:旧时代证据已随日志轮转灭失;当前实测 0.0%
   (疑似被 App 订阅逼忙),复现条件与独立取证待立。
2. **02 dispose 无重启 API**:should_close 一旦可达,cleanup 永久杀死监视链
   →重开窗不刷新;修法=方案 B(start/dispose 对称+开窗 resume)。
3. **03 hook os-231 churn**:机制/处置/三方向见 §7,待代码修。

## 10. 关联

- opt-03-ctrl.md:**同一个 status_monitor** 的另一病相——opt-03 里它开窗即发
  SUBSCRIBE_STATUS(命令 9)压垮服务 initializer;本篇里它关窗后永续轮询烧
  CPU。设置域后台链的生命周期是共性软肋。
- RUN-NOTES S76;`.scratch/ak97-idle-cpu/issues/01~03`。
- 工具:`.scratch/ak97_cpu_sample.ps1`/`ak97_cpu_by_pid.ps1`(反馈回路)、
  `ak97_cpu_d1/d2.dmp`+`ak97_d2_stacks.txt`(取证)、`ak97_capture.ps1`/
  `ak97_wenum.ps1`(真机面)。
