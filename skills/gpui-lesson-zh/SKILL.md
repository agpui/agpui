---
name: gpui-lesson-zh
description: >-
  AK97(Rust+GPUI+Win32 IPC)项目排障纪律:从 references/ 五份实战复盘
  (opt-01 设置窗卡死/托盘、opt-02 服务 PipeServer 自死锁、opt-03 热键链、
  opt-04 空闲 CPU 烧核、opt-05 激活管道 231/路由静默 no-op)归纳的诊断分流
  矩阵、真机取证方法与 GPUI/Win32/生命周期/翻译接线面红线。当遇到:GPUI
  窗口卡死/白屏/hung、托盘或热键无响应、命名管道超时/半开、服务进程
  "活着但不响应"、Rust Mutex 死锁、空闲/无业务时 CPU 持续高耗、后台定时
  器或订阅不随窗退场、hook 进程被循环拉起、后台数据已到而 UI 列表陈旧、
  命令路径动作静默无效(无日志无错误)、日志出现管道 os-231、测试进程
  STATUS_ACCESS_VIOLATION,或要在本项目中新增窗口/管道/钩子/锁/后台轮询
  /属性通知/事件订阅代码时——先读本技能,按矩阵分流再动手。不做泛化
  诊断,只提供本项目实证过的路径与工具锚。
---

# gpui-lesson-zh:本项目实证过的排障纪律

五份复盘的全量细节在本技能 `references/` 目录,本技能是**分流矩阵+工具锚+红线**的可执行摘要。
需要完整案情时按节读源文档(路径见 §6)。

## 1. 症状→病类分流矩阵(先分流,再动手)

| 症状 | 首查(真判据) | 本项目实证过的病类 |
|---|---|---|
| **多窗全 hung**(连托盘都无响应) | `scripts/probe_hung.ps1` / `.sh` → `VERDICT: RED` | 主线程死锁:锁域死锁(持 A 锁调会取 B 锁的设施)或高频 set_menu 重入(WER AppHangB1) → opt-01 §3 |
| **单功能链死**(进程不 hung,托盘/菜单正常) | 端到端行为判据(如双击 Ctrl → app.log `Dispatching hook event id=ACTIVATE`) | 跨进程链断:服务管道死→hook 拉起失败→热键死 → opt-03 §2 |
| **服务 Running 但管道全 timeout** | service.log 最后一条(如 `Request received: 9`) | 服务侧锁死锁:同线程 Mutex 重入自死锁 → opt-02 §4 |
| **进程不卡但 CPU 持续高**(空闲烧核) | 采样回路 `scripts/ak97_cpu_sample.ps1`(RED/GREEN)→ cdb **双 dump 差分** `!runaway` | 内核态主导=系统调用轮询:全局单例×后台链永生(定时器/订阅不随窗亡) → opt-04 §3-4 |
| **窗口弹出但空白/无显示** | wenum 尺寸 + 槽内句柄 `IsWindow` 真验 | GPUI 默认窗无 bounds;槽脏 HWND(关窗后死句柄) → opt-01 根因 4 |
| **偶发,复现不稳** | 找时间窗:构建期持锁 × 用户操作重叠 | "偶发=时间窗",非随机 → opt-02 §7.4 |
| **拉起/重试计数线性涨** | grep `round N` | 自愈缺失+依赖死,计数器即金丝雀 → opt-03 §7.6 |
| **`Hook process launched` 刷屏**(热键时好时坏) | hook.log 按分钟直方图:`grep -E "Another hook instance\|os error 231" hook.log \| 按分钟计数` | 服务重启+遗留 hook 存活 → os-231 churn(2.5s 循环拉起);杀遗留 hook 即愈 → opt-04 §7 |
| **后台数据已到而 UI 列表/状态陈旧**(日志确认数据到达) | 沿 数据→VM notify→窗口桥→视图 链逐环查:属性通知是否存在、转发订阅是否存活 | 翻译接线面三缺陷:CollectionChanged 丢失/子→父转发订阅 `let _` 即弃/防抖漏 Cancel → opt-05 §3 |
| **命令路径动作静默无效**(无日志无错误无效果) | grep 动作站点 `TODO(port)` + `let _ =`;静默 no-op 与成功不可区分 | 路由/分发站点未接线(TODO(port)[N] no-op)→ opt-05 §3-D2 |
| **日志出现管道 os-231(激活/拉起)** | 先判身份:预期瞬态(Debug 短退避)还是 churn 症状(直方图) | 两种病:churn 循环拉起(→opt-04 §7)或 max_instances=1 固有忙窗(**良性瞬态,别当主因**——真凶常在别处,误判放大器) → opt-05 §2 |
| **测试进程 STATUS_ACCESS_VIOLATION(无 RUST_BACKTRACE 栈)** | 查结构体字段声明序:RAII 订阅句柄字段是否声明在通知源字段之后 | 析构序:Rust 按声明序 drop,订阅句柄先于源声明才安全 → opt-05 §3 |

**分水岭三问**:①进程 hung 吗(probe_hung 一跑即知)?②症状在哪条链上
(端到端行为判据)?③进程闲还是忙(CPU 采样回路——忙则双 dump 差分按栈
抓现行,不插桩不推理)?三问分流掉 80% 的错误方向。

## 2. 诊断工具箱(全部留档可复用)

脚本按平台二份:Windows 用 PowerShell(.ps1),Linux 用 bash(.sh)。Windows 侧
为本项目实证过的路径;Linux 侧为同型跨平台对应实现(X11//proc 工具链),
未经本项目真机实证,判据口径以各脚本头注为准。

| 工具 | 用途 | 真调用形态 |
|---|---|---|
| `probe_hung` | IsHungAppWindow 枚举判 hung(红/绿;Linux 无 GUI-hang API,退化为进程存活+D 态线程检测) | Windows:`powershell -ExecutionPolicy Bypass -File scripts/probe_hung.ps1 [进程名]`;Linux:`bash scripts/probe_hung.sh [进程名]` |
| `probe_dump` | MiniDumpWriteDump/gcore 抓转储 | Windows:`powershell -ExecutionPolicy Bypass -File scripts/probe_dump.ps1 <pid> [out.dmp]`;**服务会话(Services)必须管理员**,err=5 即权限;Linux:`bash scripts/probe_dump.sh <pid> [前缀]`(gcore,注意 ptrace_scope) |
| cdb(WinDbg) | dump 抓取+栈析 | 抓:`"/c/Tools/Program/WinDbg/WinDbg(x64)/cdb.exe" -p <pid> -c ".dump /ma <out>.dmp; qd"`(**双 dump 间隔 5-10s 差分定位热点线程**);析:`cdb -z <dmp> -y "F:\...\src\shared-target\release" -c "!runaway 7; ~*k 60; qd"`;符号=同批 release 的 .pdb(**与部署 exe md5 对账,strip=true 时代必做**) |
| CPU 采样回路 | 空闲 CPU 红绿判据 | Windows:`scripts/ak97_cpu_sample.ps1 -Samples 5 -Interval 2`(进程名内置 AK97/AK97-Service/lff);Linux:`bash scripts/ak97_cpu_sample.sh -n 5 -i 2 <进程名>...`;口径:`\Process`/jiffies 计数是"单核和",**÷逻辑核数**才等于任务管理器/top 读数;多实例按 PID 用 TotalProcessorTime 差分(通配计数器取 max 非和) |
| URI 遥控 | 免托盘 HITL 的开窗验证 | `Start-Process 'ak97://settings'`(uri_router route_settings);配 `scripts/ak97_capture.ps1`/`.sh` 截图判读 + `scripts/ak97_wenum.ps1`/`.sh` 枚举可见窗(wmctrl/xdotool) |
| `[DBG-xx]` 打点夹逼 | 死点定位到行 | 关键路径布点→真机触发→看断在哪两锚之间→加密一轮;**收官必清**(`scripts/cleanup_dbg.ps1` / `.sh`,grep 计数归零) |
| 单变量二分+对照刀 | view 层 vs 框架层 | 每刀只换一个变量;对照刀=把已证不卡的 view 挂进嫌疑链 |
| wenum/截图 | 窗口真态/坐标 | AK97 源仓库 `docs/09-test/test-01/drive-*.ps1`(未随本技能发布);托盘合成右键需 DOWN/UP ≥120ms 间隔 |

**dump 真伪双验**(PID 复用陷阱,实测踩过):栈中出现
`service_dispatcher`/`run_as_service` = 真服务;出现 GPUI/QuickSearchWindow
栈 = App。抓前记录目标 PID 启动时间。

## 3. 红线(写代码前必读,全部实证代价)

### 锁(本项目两起死锁同型:持 A 锁调会取锁的路径)

- **std::Mutex 不可重入**:持锁作用域内调用任何方法,必须证明其传递闭包
  不触同一把锁。语义便捷方法(set_drive_state→...→lock)经三层包装照样死。
- 对策:①拆 `_locked` 已持锁内部形态(本项目先例:
  `UsnIndexer::set_drive_state_locked`);②回调只传 `&mut Shared`;
  ③API 设计期就提供已持锁变体,不做死后补丁。
- **锁内禁调**:logger(LOG_STATE 全局锁)、组件 API、任何 `lock()`。
  日志/回调一律移出锁域(`drop(guard)` 后再打)。

### 生命周期/后台链(全局单例化的代价,opt-04 实证)

- **C#"每窗新建+Dispose"译成 OnceLock 全局单例时,每条后台链(定时器/
  订阅/轮询)必须补等价生命周期门**:存活守卫(先例:`settings_window_alive()`
  总闸,interval tick 与派发 CAS **两处前置**)或 start/dispose 对称 API。
  只改循环体不查触发源生命周期的修复是错的——"排空即 break"的循环
  防不住"有人持续喂"。
- **dispose 不可"只能死不能生"**:abort/cancel 后若无重启 API,关窗钩子
  一旦可达即永久哑火(先例:status_monitor dispose 后重开设置窗不刷新,
  潜伏地雷)。
- 句柄/窗槽存活判定一律 `IsWindow` 真验,**禁 `is_some`**(死句柄家族);
  查询函数锁内只快照,Win32 调用在锁外。
- 源码守门测试(include_str! 切片)的锚点会被**测试自身字面量**抢先命中
  ——锚点用真实签名(含 `&self`),不用测试里手打的形态。
- 空闲 CPU 短暂峰先查业务指纹(service.log USN "Applying USN records" 密度)
  再判回归——**正当业务自愈 ≠ 缺陷复发**。

### 翻译接线面(WPF/C#→Rust 语义丢失家族——opt-05 实证,S82/S83 五缺陷)

parity(索引/排序/事件流)与单测全绿也**拦不住**本族缺陷:它们是 C#/WPF
语义翻译时丢失的接线面,只有真机 HITL 才暴露。每条按「触发/一线修复/
兜底」三段式编码:

- **属性通知/CollectionChanged 丢失**(先例:replace_results 变更集合后
  从不 notify("Results"))。触发:后台数据已到而视图陈旧。一线修复:在
  变更点补 `property_changed.notify("属性名")`。兜底:同本节第 5 条的
  静默 no-op 审计面(单一出处防漂移)。
- **子→父属性转发订阅 `let _ = _sub` 构造即弃**(RAII 退订句柄,Drop 即
  解订;先例:QuickSearchViewModel::new 两段装配的 search_vm/monitor_vm
  转发订阅)。触发:子 VM 属性全不上行。一线修复:句柄收集进 `_*_subs`
  字段随宿主存活。兜底:clippy/复核禁 `let _ = *_sub*`。
- **订阅句柄字段析构序**(先例:句柄字段声明在通知源字段之后 → 先析构
  源再析构订阅 → RAII Drop 解引用悬垂指针 → STATUS_ACCESS_VIOLATION)。
  触发:测试/运行无栈段错误。一线修复:句柄字段声明**先于**被指向的
  源字段(Rust 按声明序析构)。兜底:新增"指向兄弟字段"的 RAII 句柄时
  复核声明序(REVIEW 清单项)。
- **防抖/生命周期令牌漏 Cancel**(先例:queue_search 只替换令牌槽不
  Cancel 旧令牌——源 `_debounceCts?.Cancel()` 丢失)。触发:快速连发的
  前缀任务全部到期齐发乱序,幸存者被陈旧守卫丢弃。一线修复:替换槽前
  显式 `previous.cancel()`。兜底:回归钉以"仅最后一个执行"计数(旧码
  计数=连发数,必红)。
- **动作站点静默 no-op 禁令**(先例:route_local_send 打开发送窗是
  TODO(port)[3] 无日志吞载荷——与 os-231 毫无因果却连续误导两轮排查)。
  触发:命令路径动作无日志无错误无效果。一线修复:接线到既有命令泵/
  通道。兜底:未接线站点必须 Warn 日志+显式标识,禁止裸 `let _ = ...`
  吞载荷;发布前 grep 审计 dispatch/route/handler 面。

### GPUI(gpui-kit 0.6.1)

- 每窗硬形态:`gpui_kit::init(cx)` + 双建(内层 view Entity +
  `Root::new(view, window, cx)` 真包)。绕 Root 的故障是**条件触发**
  (静止正常、焦点/overlay 快变即崩),静读发现不了——**多窗焦点互切
  必须进真机回归**。
- `WindowOptions` 必须显式 `window_bounds`(默认窗尺寸/定位异常);
  `IsWindow(Option<HWND>)`(windows 0.62,Option 包裹,与
  IsWindowVisible 裸 HWND 签名不同)。
- 窗槽(缓存的 HWND)复用前必须 `IsWindow` 真验;关窗走
  `on_window_should_close`(可取消)+ `cx.on_window_closed`(按
  WindowId 清理);托盘可重开的应用末窗关闭**不强制 quit**。

### 管道/IPC

- **半开连接静默死**:对端死亡不总产生读错误——读循环必须
  `tokio::time::timeout` 包裹(本项目先例:事件管道 60s 静默即重连)。
- **LazyLock 通道竞态**:TX 惰性首用 + take 型消费,首用晚于 take 即
  静默丢失——take 侧 `LazyLock::force`。
- **自愈三层**(缺一有洞):端内重连(半开超时)→ 依赖重启(hook 拉起
  20 轮失败重启服务,先例 `self_heal_restart_service`)→ 根因工单。
- 流式命令(SUBSCRIBE_STATUS 等)独占连接,与命令连接分离是设计本意;
  服务日志止于某命令号 = 挂点就在该命令处理链上。

### Shell/托盘(HITL 边界)

- 合成点击对 Shell 托盘**不可靠**(右键需间隔、菜单项不命中)——
  端到端验证以**人手点+日志判据**为准;合成只做定位性实验。
- muda 0.20 无 per-item `set_visible`,动态显隐以重建/set_menu 承载,
  且**禁止每次交互触发**(高频重入踩 AppHangB1;选语言变化等低频点)。

## 4. 健康判据(回归清单)

- 进程级:probe_hung 全 False。
- 行为级:双击 Ctrl 唤起(app.log 41 真达);托盘七项逐项;
  设置窗开关三次;服务日志持续滚动(不止于任何 `Request received: N`)。
- 自愈降级证据:`self-heal` 日志零新增 = 服务侧根因真修好的行为级判据。
- 空闲 CPU:采样回路 PEAK <1%(opt-04 修复前 18.7%);hook.log
  `os error 231` 零增长(churn 已愈的判据)。
- 接线面:激活管道 re-arm <300ms(回归钉 `rearm_tests`,实测 263µs);
  发送窗通道契约钉正/负两腿绿;`grep -rn "TODO(port)" src/App/src`
  于 dispatch/route/handler 面逐条带 Warn(静默 no-op 审计,opt-05 §5)。
- 多窗焦点互切回归(Root 契约的条件触发面)。

## 5. 信道纪律(本系列诊断中三度踩坑)

工具回显可能伪造(Edit 假成功/伪 grep 输出/伪 TaskOutput)。判据:
编译器+`git -C <根>` 真输出为唯一地面真值;写后最小读回+编译验证;
**每条命令显式 cd 钉 cwd**(仓库根与 src/ 两级漂移是伪路径主源);
find/grep 零命中先疑 cwd 再疑文件不存在。

## 6. 源文档(完整案情按节取)

- `references/opt-01-gpui-tray.md` — 设置窗卡死六根因/打点夹逼到行/
  对照刀/托盘中文化与 Send 接通/坐标锚。
- `references/opt-02-PipeServer.md` — 服务自死锁因果链/cdb 双臂真栈/
  PID 复用陷阱/锁 API 设计教训。
- `references/opt-03-ctrl.md` — 热键链解剖/双会话服务孤儿坑/半开自愈/
  三层自愈分层。
- `references/opt-04-cpu.md` — 空闲 CPU 1.5 核 windbg 取证链/双 dump 差分/
  生命周期守卫两处前置/hook os-231 churn。
- `references/opt-05-activation-pipe-231.md` — os-231 良性瞬态定性/路由站点
  no-op 真因/翻译接线面五缺陷家族/误判放大器(Error 时间邻近性)/假说证据
  先行裁决表。
- `references/issues/01~03` — Service 烧核取证单/dispose 无重启单/hook
  churn 修法三方向。
- AK97 源仓库留档(未随本技能发布):RUN-NOTES S58-S61,S76,S80-S83
  (src/migration/RUN-NOTES.md);drive-*.ps1 真机驱动脚本;提交链
  50f922c/cb231a5/2a5eeb6/69eabe2/8bed5b7/ac424aa/d3c5912/91e64ba/684d710。
