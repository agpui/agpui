# opt-02: 服务 PipeServer 挂死深水根因复盘——同线程 Mutex 重入自死锁

> S60b/S60c/S61 系列(服务 PipeServer 挂死)的专篇复盘。
> 姊妹篇:opt-01-gpui-tray.md(设置窗卡死)、opt-03-ctrl.md(热键链与自愈)。
> 诊断纪律:mattpocock-skills/diagnosing-bugs 六阶段;取证:WinDbg cdb + minidump。

## 1. 背景与现象

| 现象 | 首因直觉(错) |
|---|---|
| 服务进程 Running,但 App 连接服务管道全部 `connect timeout` | 服务崩了(错,进程活) |
| hook 进程拉起失败,round 线性涨(370→5402) | hook 本身坏(错,拉起命令走死管道) |
| 双击 Ctrl 热键死,ESC 后无法唤回 | 召唤逻辑坏(错,事件链源头断) |
| "禁用快捷键"点击不生效 | toggle 坏(错,热键链整体死,无从表现) |
| 服务日志止于 `Request received: 9` 后零活动 | 日志轮转(错,真挂死) |

**分水岭**:`Request received: 9` = `SUBSCRIBE_STATUS`(流式状态订阅)。
服务在处理该命令后整体停止响应——挂死点在流订阅内部或其后。

## 2. 因果链(三轮复现实锤)

```
设置窗打开
→ SettingsViewModel::new → status_monitor
→ ensure_status_subscription → 命令 9 SUBSCRIBE_STATUS(流订阅)
→ 服务侧恰在 SearchEngineInitializer::run(构建期)中:
     build_drives 已持 UsnIndexer.shared 锁(M)
     → set_drive_state → set_drive_state_reset_counts → 再次取 M
     → std::Mutex 非可重入 → 同线程永久自死锁(臂 2)
→ 流任务 handle_client → get_status → 等 M 永挂(臂 1,占住该连接)
→ 服务命令处理链饿死(PipeServer 全部命令 connect timeout)
→ hook 拉起(命令 15 LAUNCH_HOOK)失败 → hook 永不启 → 热键死
→ App 侧 hook 拉起死循环(round 5402)
```

**触发条件**(为何不是必现):initializer 构建期(服务启动或盘重建)与
设置窗首开的时间窗重叠才触发——冷启动后立刻开设置窗最易中;服务就绪后
build_drives 已结束,不再持锁,永不复现。这就是"偶发"的全部真相。

## 3. 诊断过程(六阶段真跑,重点录弯路)

### Phase 1-2:反馈环

- **probe_hung**(IsHungAppWindow)证明 App 进程不 hung——把问题空间从
  "进程死锁"(opt-01 病)缩小到"活进程内的跨进程链路"。
- 端到端判据:双击 Ctrl → app.log `Dispatching hook event id=ACTIVATE`。
- 复现实验的**开关型设计**:净重启(服务+应用)→基线真绿(热键活)→
  开一次设置窗→服务日志止于 `Request received: 9`、管道死、热键死。
  三轮复现(09:49/10:10/19:55),因果锤实。

### Phase 3-4:假设备注(弯路实录,价值在教训)

| 假设 | 真机/工具证据 | 结论 |
|---|---|---|
| 日志轮转假象 | 服务日志真止于命令 9 | 排除 |
| 服务崩了 | tasklist: 进程 Running | 排除(进程活≠链路活) |
| 实例数耗尽(max_instances) | create_pipe_instance=254 真读 | 排除 |
| 监听循环堵塞 | ListenLoop 每连接 tokio::spawn 并发 | 排除 |
| 流循环自身死锁 | signal.acquire 等待正常形态 | 排除(挂点在更上游) |
| **dump 分析** | 见 §4 | **终钉** |

### 深水工具战(方法论重点)

1. **minidump 抓取**:`MiniDumpWriteDump` ctypes 封装(probe_dump.py)。
   用户会话进程直抓;**服务会话(Services, session 0)必须管理员**(err=5)。
2. **PID 复用陷阱(本篇最大教训之一)**:第一次"管理员抓 13200"得到的是
   App 进程栈——服务自愈重启后**新 App 复用了 PID 13200**。dump 真伪必须
   以**镜像名+栈特征**双验(`service_dispatcher`/`run_as_service` 出现才是
   真服务;出现 `QuickSearchWindow`/GPUI 栈=App)。
3. **cdb 真析**:`cdb -z dump -y <pdb 目录> -c "~*k 60; qd"`,
   符号用 `src/shared-target/release/*.pdb`(与 exe 同批产物,版本逐位匹配)。

## 4. 深水根因终钉(cdb 双臂真栈)

### 臂 1(流任务,等锁)

```
UsnServicePipeServer::handle_client (SUBSCRIBE_STATUS 闭包)
→ SearchEngine::get_status
→ std::sync::mutex::futex::Mutex::lock_contended
→ KERNELBASE!WaitOnAddress / ntdll!RtlWaitOnAddress   ← 永久等 M
```

### 臂 2(initializer 线程,持锁者自死锁)

```
SearchEngineInitializer::run
→ UsnIndexerBuildExtensions::build_drives        ← L49: 已持 M(shared.lock)
   → set_drive_state("indexing")                 ← L68: 持锁中调用
      → set_drive_state_reset_counts
         → shared.lock()                          ← 同线程重入非 reentrant Mutex
→ 永久自死锁(M 未释放,本线程在等自己持有的锁)
```

**根因定性**:不是两线程互等的经典 ABBA,而是**同线程 Mutex 重入自死锁**
(std::sync::Mutex 不可重入;重入即未定义行为/死锁)。臂 1 只是受害者——
任何后续要 M 的服务路径全部饿死,PipeServer 只是第一个被用户看见的。

### 代码位点

- `Core/src/indexer/usn/usn_indexer_build_extensions.rs`:
  `build_drives` L49 持锁;L68 持锁中调 `set_drive_state`;
  同文件 L95 还有一次同形回调注入(`set_drive_state: &|...|`)——重入风险面。
- `Core/src/indexer/usn/usn_indexer.rs`:
  `set_drive_state` → `set_drive_state_reset_counts` → `shared.lock()`。

## 5. 真修

```rust
// usn_indexer.rs:已持锁内部形态(pub(crate),语义同源拆分)
pub(crate) fn set_drive_state_locked(shared: &mut UsnIndexerShared, drive: &str, state: &str)

// usn_indexer_build_extensions.rs:重入点改调(持 M 中)
UsnIndexer::set_drive_state_locked(&mut shared, drive, "indexing");
```

- 门禁:core 376 passed/0 failed + clippy 0;三处部署 md5 一致;提交 cb231a5。
- **遗留风险面(留账)**:build_extensions 内 L95 的回调注入与其它
  `set_drive_state*` 调用点需在后续波次做同型审查(本修只拔了实证触发点)。

## 6. 验证

- 部署后:服务日志不再止于命令 9(持续滚动);设置窗反复开关无挂死;
- App 自愈(20 轮重启服务)降级为纯兜底,正常态不应再触发
  (`self-heal` 日志零新增 = 修好的行为级证据);
- 热键链:hook 真连+41 真达,双击 Ctrl 正常(用户真机确认)。

## 7. 教训与纪律沉淀

1. **std::Mutex 不可重入**——持锁调用任何"可能再取同一把锁"的方法(哪怕
   经三层包装的语义便捷方法)就是自死锁。对策三选一:
   ①拆 `_locked` 内部形态(本修);②回调/闭包只传 `&mut Shared`;
   ③换 ReentrantMutex(重入计数有成本,慎用)。**API 设计期就把"已持锁
   变体"作为公共面一部分**,而不是死锁后的补丁。
2. **持锁段审查规则**:凡 `lock()` 作用域内出现的**方法调用**,必须证明
   其传递闭包不触碰同一把锁——编译器不查,只能靠 review 纪律或
   `#![warn(unused_lock)]` 类 lint 辅助。
3. **dump 取证双验**:镜像名+栈特征验真伪;服务会话必须管理员;抓前
   先记录目标 PID 的启动时间(防 PID 复用误判)。
4. **偶发 = 时间窗**:构建期持锁 × 用户操作(开设置窗)窗口重叠才触发。
   找不到必现路径时,找"谁在什么阶段持着什么锁"。
5. **服务日志的"最后一条"是金线索**:`Request received: 9` 后零活动,
   挂点就在命令 9 的处理链上——日志止点即侦查起点。
6. **跨进程症状,单进程根因**:热键死/管道 timeout 都发生在 App/hook 侧,
   根因却在服务进程内部的一把锁——**不要在受害进程里找根因**。

## 8. 关联

- opt-01-gpui-tray.md:App 侧锁域死锁(STATE×LOG_STATE)——同型异位,
  本项目两起死锁均为"持 A 锁调会取 B 锁的路径",纪律同源。
- opt-03-ctrl.md:热键链自愈(半开超时+服务重启兜底)——本修后兜底
  降级为纯保险。
- RUN-NOTES S60b/S60c/S61;提交 cb231a5;dump 留档 `.scratch/*.dmp`。
