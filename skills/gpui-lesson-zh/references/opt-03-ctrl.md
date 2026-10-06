# opt-03: 双击 Ctrl 热键无响应复盘——跨进程链路断点与服务域深水

> S60b/S60c 系列热键链诊断全过程的提炼。姊妹篇:opt-01-gpui-tray.md(设置窗
> 卡死与托盘)。诊断纪律:mattpocock-skills/diagnosing-bugs 六阶段。

## 1. 背景与现象

| 现象 | 关键对照 |
|---|---|
| 双击 Ctrl 快搜窗不唤起(ESC 隐藏后同样) | **托盘单击/右键"显示主窗口"真常** |
| "禁用快捷键"菜单项点击"不生效" | 热键链死时 toggle 无从表现 |
| 进程**不卡**(probe_hung 真绿、托盘链真活) | 设置窗卡死时全窗 hung(可判) |

分水岭判断:**进程健康 + 单一功能链死 = 跨进程 IPC 链断点**,
与 opt-01 的"主线程死锁全窗 hung"是完全不同的病。

## 2. 热键链解剖(正常链)

```
用户双击 Ctrl
→ hook 进程(低级键盘钩子,独立进程)捕获
   hook.log: "Double-Ctrl detected, sending ACTIVATE."
→ 事件管道(named pipe, hook→App 单向)
→ App HookIpcClient 读取循环(read_message_async)
→ dispatch_event: IpcMessageId::ACTIVATE → on_activated 槽
→ handle_global_summon_hotkey() → 快搜窗唤起
```

hook 由**服务代启**(App 发命令 15=LAUNCH_HOOK → 服务 LaunchHookProcessAsync,
elevation 由服务侧裁决)。**hook 的生死挂在服务管道的生死上**——这是全案锁钥。

## 3. 诊断过程(六阶段真跑)

### Phase 1-2 反馈环与复现

- `probe_hung.py` 判定**进程不 hung**——排除主线程死锁(opt-01 病),
  把问题空间缩到"活进程内的跨进程链路"。
- 端到端行为判据:双击 Ctrl → app.log 是否出现
  `Dispatching hook event id=IpcMessageId::ACTIVATE`(分派打点,Debug 级)。
  **链路健康以端到端行为判定,不以单进程存活判定。**

### Phase 3-4 假设与证据(按时间序,每步真机验证)

| 断点 | 真机证据 | 结论 |
|---|---|---|
| hook 未检测? | hook.log `Double-Ctrl detected, sending ACTIVATE`(三次) | hook 真检测真发 |
| ACTIVATE 未达 App? | app.log(日志轮转后窗口)**零** Dispatching | **事件管道断** |
| 为什么断? | app.log `Failed to launch hook process (round 5402)` | 服务管道死→**服务代启失败**→hook 永不(重)启 |
| 服务死了吗? | 服务进程 Running、服务日志止于 `Request received: 9` | **进程活,PipeServer 挂死** |
| 谁发的命令 9? | 设置窗 VM(status_monitor)→`ensure_status_subscription` | **设置窗打开→SUBSCRIBE_STATUS 流订阅** |
| 因果实锤 | 设置窗开关→`Request received: 9`→管道死(两轮复现:09:49/10:10) | **因果实锤** |

### 因果实验(本复盘的关键一刀)

净重启(服务+应用)后基线真绿(hook 真连、41 真达、热键正常)→
**请用户开一次设置窗**→ 服务日志止于 `Request received: 9`(SUBSCRIBE_STATUS)
→ 管道死(timeout+15)、热键死。**开关设置窗→管道死,因果钉死。**

### 深水边界(诚实录)

服务侧 `SUBSCRIBE_STATUS` 流循环(`stream_status_updates`:signal.acquire
等待+write_status)代码面上是真等待,`ListenLoop` 每连接 tokio::spawn 真并发,
`max_instances=254` 真足——**逐层排除后挂死机理仍在更深处**(tokio 运行时/
驱动交互)。服务进程 minidump(921KB)已抓,无 cdb/WinDbg,**如实挂起待
分析**,不编造结论。

## 4. 根因结构(三个独立根因叠加)

- **根因 A(服务域深水)**:PipeServer 在 SUBSCRIBE_STATUS 流订阅后整体
  挂死(命令管道全部 connect timeout,hook 拉起命令 15 同死)。
  触发面:设置窗打开(VM 构造→status_monitor→订阅)。挂账待 dump 分析。
- **根因 B(服务域)**:**孤儿用户会话服务进程**。`Restart-Service` 只替换
  服务会话实例(7356→11380),用户会话孤儿(9944)残活,其管道/钩子会话
  与新服务互竞:hook 单例守卫 "Another hook instance is already running"
  + `os error 231`(HookIpcServer Server loop error)。taskkill 9944 后
  全链恢复(IpcMessageId(41) 真发)。
- **根因 C(App 侧韧性缺失)**:hook 拉起失败**死循环无自愈**——服务管道
  死时代启(命令 15)永远失败,round 线性涨到 5402。C# 源注释自认
  "self-heals once it's reachable"——**C# 同病**(服务不恢复就永不愈)。
- 放大器:拉起循环 2.5s 疯狂重试(无退避),刷屏且无意义。

## 5. 修复(App 侧自愈与韧性,超越 C# 的增强——授权锚定在代码注释)

| 修复 | 文件:形态 |
|---|---|
| **自愈重启服务**:连续拉起失败 20 轮(~100s)→ `sc.exe stop/start AK97Service`(安装时已授已验证用户 START/STOP,无提权;tray_clean_exit 同款面)→ round 归零 | hook_ipc_client.rs None 分支 + `self_heal_restart_service()` |
| **半开自愈**:事件管道 60s 静默(hook 侧死时 read 静默真挂、无 Err)→ 超时转 LoopError 走既有重连 | 事件循环 `tokio::time::timeout(60s, read_message_async)` 包裹 |
| **指数退避**:拉起失败 5s→10s→20s→40s(上限 60s),打破疯狂重试 | None 分支 backoff |

**语义边界(诚实)**:自愈是**兜底**——服务 PipeServer 挂死的真根因在
服务域(A),自愈只保证热键在 ~100s 内自动恢复,不修服务本身。

## 6. 真机终验(用户确认)

| 项 | 结果 |
|---|---|
| 净重启(服务+应用)后双击 Ctrl | ✅ 唤起(hook 初始化成功+双管真连+41 真达) |
| 托盘单击/右键显示主窗口 | ✅(对照面,真常) |
| ESC 隐藏/唤回 | ✅ |
| 服务重启后热键自动恢复(自愈) | ✅ 兜底路径(待长周期验证) |

## 7. 教训与纪律沉淀

1. **"进程活 ≠ 链路活"**:多进程架构(服务/hook/App)的每个功能链,
   健康判定必须**端到端行为级**(热键=双击 Ctrl 行为),单进程 hung 探测
   只能排除一类病。
2. **功能开关是天然的分段测试点**:设置窗开关与管道死的因果,靠
   "基线(不开)→操作(开)→复测"三段实验一锤钉死——复现实验优先设计
   开关型操作。
3. **服务生命周期双会话坑**:Windows 服务(会话 0)+ 用户会话拉起的
   服务实例并存,`Restart-Service` 不清用户会话孤儿——互竞/单例误拒/
   管道错位全由此生。
4. **半开连接静默死**:named pipe 对端死亡不总产生读错误——**读循环
   必须有超时+重连自愈**,不能信任 read 的错误通知完备性。
5. **自愈分层**:①端内重连(半开超时)②依赖服务重启(跨进程自愈)
   ③服务自身根因修复(工单)——三层缺一,韧性有洞。
6. **round 计数是金丝雀**:`round 5402` 一个数字就暴露了"自愈缺失+服务
   域死"两个问题——持续失败的计数器要有,超阈值要有动作。

## 8. 遗留挂账

1. 服务 PipeServer 挂死机理(SUBSCRIBE_STATUS 流内部)——`ak97_hang.dmp`
   + WinDbg `!analyze -v`/线程栈;或服务域代码走查(流循环锁面)。
2. 孤儿用户会话服务进程的产生与清扫机制。
3. App 侧自愈的长期验证(自愈触发频率/服务重启抖动的用户感知)。
4. 禁用快捷键终验(热键链健康后按原判据)。

## 9. 关联

- opt-01-gpui-tray.md:设置窗卡死(锁域死锁/槽脏/Root 契约)——同窗异病。
- RUN-NOTES S60 系列;`.scratch/single-instance-activate/issues/`。
- 工具:`.scratch/probe_hung.py`/`probe_dump.py`;drive-*.ps1(合成+HITL)。

## 10. 终章(S61):服务 PipeServer 挂死深水根因终钉与终修(WinDbg 实证)

### 10.1 dump 取证的关键教训

- **PID 复用陷阱**:第一次"管理员抓 13200"得到的是 App 进程栈——服务自愈
  重启后新 App 复用了 PID 13200。dump 必须以**镜像名+栈特征**双验
  (`service_dispatcher`/`run_as_service` 出现=真服务)。
- **服务会话(Services, session 0)进程 dump 必须管理员**(err=5)。

### 10.2 双臂真栈(cdb 真析,AK97-Service.pdb 符号)

- **臂 1(流任务)**:`UsnServicePipeServer::handle_client`(SUBSCRIBE_STATUS)
  → `SearchEngine::get_status` → `Mutex::lock_contended` → `RtlWaitOnAddress`
  (永久等锁 M)。
- **臂 2(initializer 线程)**:`SearchEngineInitializer::run` → `build_drives`
  (L49 已持 M)→ `set_drive_state` → `set_drive_state_reset_counts`
  → 再取 M(同线程重入非 reentrant std Mutex)→ **永久自死锁**。

### 10.3 真修

`UsnIndexer::set_drive_state_locked(&mut UsnIndexerShared, drive, state)`
(pub(crate) 已持锁内部形态),build_drives 重入点改调之;全域扫无同类形态。
门禁:core 376/0 + clippy 0;三处部署 md5 一致;提交 cb231a5。

### 10.4 因果链全闭环

设置窗打开 → VM status_monitor → 命令 9 SUBSCRIBE_STATUS 流订阅 →
initializer(构建期)恰持 M 自死锁 → get_status 等 M 永挂(流任务占住连接)
→ 服务 PipeServer 命令链饿死 → hook 拉起(命令 15)失败 → 热键死。
App 自愈(20 轮重启服务)是兜底;本修后 initializer 不再自死锁,服务不再挂。
