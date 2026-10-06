# opt-01: GPUI 托盘菜单与设置窗卡死修复复盘

> S59d/S60/S60b 系列(RUN-NOTES.md)全过程的提炼与沉淀。
> 涉及:托盘图标七项菜单、设置窗、全局热键(hook)链、AK97-Service 管道。
> 关联技能:mattpocock-skills/diagnosing-bugs、gpui-kit(coding-guides)。

## 1. 背景与现象

用户报障的表象按发现顺序:

| # | 现象 | 第一直觉(错) |
|---|------|--------------|
| 1 | 重新编译部署后托盘"双击无反应" | 新 exe 坏了(错,见根因 1) |
| 2 | 设置窗弹出后**白屏、卡死**,随后**搜索窗也卡死**、进程异常退出 | 渲染 bug(错,见根因 2/3) |
| 3 | 托盘右键菜单消失、左键无响应 | 托盘注册失效(错,是死锁后遗症) |
| 4 | 双击 Ctrl 热键无反应,ESC 隐藏后无法唤回 | 召唤逻辑坏(错,见根因 5) |
| 5 | "禁用快捷键"点击"不生效" | toggle 坏(错,热键链已死,无从验证) |

关键教训先行:**五个表象、五个真根因,彼此不同**。第一个直觉判断全部落空,
每一步都靠程序化证据(probe_hung/打点链/单变量二分/真机对照)重新钉死。

## 2. 诊断方法论(本复盘最可复用的部分)

### 2.1 反馈环先行(diagnosing-bugs Phase 1)

- `probe_hung.py`:ctypes 调 `IsHungAppWindow` 枚举进程全部顶层窗口,
  输出 `hung=True/False` + `VERDICT: RED/GREEN`。**一次运行即可判定"主线程
  消息泵是否被阻塞"**,把"卡死"从主观体感变成程序化红绿信号。
- 配合 `tasklist` 真实 PID、`GetWindowRect` 真实尺寸,一张表钉死现场。
- 非确定性 bug 的目标不是干净复现,而是**提高复现率**:多次探针+真机操作采样。

### 2.2 打点夹逼(定位到行)

- 关键路径布 `[DBG-set]` 前缀打点(命令泵收包→cmd enter→options→open_window
  →内层 view→Root→render 进出→HWND 提取→槽赋值→cmd exit→pump 返回)。
- 三轮收敛:每轮只在断点区间加锚,直到真死点夹逼到**一条语句**
  ("slot assigned 打了、注册日志没打"→ 死点=持 STATE 锁时的那条 log)。
- 清理:Phase 6 用 `grep -c DBG-set` 确认清零,脚本化删除。

### 2.3 单变量二分 + 真机对照刀

- 排除矩阵逐项单变量验证:Render 交互面(静态占位)→ VM::new 构造耗时
  (Rust 测试计时,36ms)→ app_id → options 逐位贴 LocalSendSendWindow →
  PopUp/Normal → VM 生命周期(全局单例)。
- **对照刀**:把已证不卡的 QuickSearchWindow 视图挂进设置窗命令链
  (不注册槽,纯对照)。一次真机操作分流"GPUI 层 vs view 层"——
  结果"快搜样子+不卡",把嫌疑从 GPUI 深层拉回 view/VM 差异。
- 每刀一次部署一次真机验证,**绝不凭阅读代码下结论**。

### 2.4 dump 与工具边界

- `probe_dump.py`:ctypes 调 `MiniDumpWriteDump` 抓 hung 进程全量转储
  (921KB,留档 `.scratch/ak97_hang.dmp`)。
- 系统无 cdb/WinDbg,minidump 栈帧分析缺工具——**诚实录 limitations**,
  转而用对照刀补位。
- **CUA(computer-use)窗域限制**:只能操作窗口内区域,Shell 托盘
  (任务栏/溢出面板)在窗外——托盘域自动化用 `drive-click/drive-rclick`
  (mouse_event 合成,DOWN/UP 间隔 ≥120ms 才被 Shell 识别)+全屏截图+HITL。

### 2.5 HITL(人手点)是 Shell 托盘域唯一可靠验证

- 合成左键命中过一次(定位性实验:toggle 计数 6→7),合成右键 0/5→1/1
  (加间隔后)。菜单项点击多次未命中。
- 结论:托盘图标/菜单的端到端验证,**坐标锚+人手点+日志判据**为准;
  合成点击只做定位性实验。

## 3. 根因清单(五根因,全部程序化证据钉死)

### 根因 1:单实例守卫误伤(表象 1 的真相)

重新编译部署后双击无反应——**旧实例残留**(窗口隐藏但进程活着,持互斥体),
新实例发 ACTIVATE 后退出。当时管道竞态误报 os error 231 干扰了判断。
**验证**:tasklist 双 PID + 激活链日志(Summon toggle/refocus)。

### 根因 2:持 STATE 锁时调 logger → 同互斥域死锁(表象 2 的死点)

打点夹逼钉死:`open_settings_window_cmd` 从入口起持有 `STATE.lock()`,
`HWND registered` 日志在锁内触发 `logger::log` → 内部 `LOG_STATE.lock()`,
而另一持 LOG_STATE 的线程在等 STATE——ABBA 死锁。
- **修复**:锁域窄化——槽赋值后 `drop(state)` 再打日志;
  日志用轻量格式,锁内不做格式化/文件 IO 以外动作。
- **证据**:slot assigned 打点在、注册日志打点缺失;drop 后真机真绿。

### 根因 3:高频 set_menu 重入 → AppHangB1(表象 3 的真相)

S59 引入的"每次菜单点击后 `rebuild_menu`(set_menu 整体替换)"在多轮
点击下高频触发 muda 对同线程托盘窗的 SendMessage 重入,WER 记录
`AppHangB1`(22:06 两次)。主线程死锁后,全窗口 hung、托盘事件全无响应
(表象 3)。叠加根因 2,进程最终异常退出。
- **修复**:移除每次点击后的重建;动态项(单进程/LocalSend 开关)刷新
  降频至 culture watch(语言变化)与进程重启。

### 根因 4:槽脏 HWND(表象 2 子形态"弹出窗口没有显示")

用户关闭设置窗后槽仍持死 HWND,后续激活序列对死句柄 `ShowWindow` 无效。
- **修复**:`IsWindow(Some(HWND(...)))` 真验,死句柄清槽走重建路径。
- windows 0.62 签名细节:`IsWindow(Option<HWND>)`(Option 包裹)。

### 根因 5:服务管道死 → hook 1107 轮拉起失败 → 热键链全断(表象 4/5)

- 服务进程活着(AK97Service=Running)但 **PipeServer 监听失效**:
  App 侧 `SendPipeCommand failed: connect timeout`,hook 侧拉起 1107 轮失败。
- **根因 5a(孤儿服务进程)**:`Restart-Service` 只替换服务会话实例
  (7356→11380),**用户会话孤儿 9944 残活**,其管道/钩子会话与新服务互竞:
  hook 单例守卫 "Another hook instance is already running" + os error 231。
  taskkill 9944 后,`Dispatching hook event id=IpcMessageId(41)` 真发,热键恢复。
- **根因 5b(管道为何死)**:服务日志停在 20:14(设置窗首次创建时刻),
  此后 PipeServer 零活动——与多窗/高频操作的时间相关性未闭环,
  **挂独立工单**(见 §7)。
- "禁用快捷键不生效"真相:热键由 hook 进程承载,hook 死则热键整体失效,
  toggle 的 App 侧状态翻转无从表现——**不是 toggle 功能缺陷**。

### 根因 6(契约级):三窗全绕 gpui-kit Root

三窗(快搜/LocalSend/设置)此前全用 `cx.open_window` 直开,**未挂
`gpui_kit::component::Root`,未调 `gpui_kit::init`**。gpui-kit coding-guides
真警告:"Bypassing it can produce behavior that looks correct at rest but
fails when overlays nest or focus changes quickly"——与"静止正常、焦点
互切卡死"逐字吻合。
- **修复**:`gpui_kit::init(cx)`(启动)+
  建窗改双建形态:`内层 view` + `Root::new(view, window, cx)` 真包
  (真源 crates/kit/src/lib.rs:158 等价面;0.6.1 无 open_window 封装,
  手动按文档双建;`cx.open_window` 返回 `WindowHandle<Root>`)。
- **验证边界**:Root 挂上后仍复现卡死,故 Root 缺失是**契约债**而非本次
  死锁直接根因;但二分同时证明 Root+任意 view 的形态可行(对照刀)。

## 4. 修复清单(文件:形态)

| 文件 | 修复 |
|---|---|
| `App/src/services/app_window/app_window_manager.rs` | 命令封送通道(force 竞态修复);`open_settings_window_cmd`(槽脏防护+gpui-kit 双建+HWND 提取+锁域窄化);show/show_entry 双入口封送 |
| `App/src/app_startup.rs` | 设置窗命令泵(force 后 take)+ Root 契约生效路径 |
| `App/src/views/settings/settings_window.rs` | 当前=静态占位 render("设置(完整界面随渲染波次迁移)")+ 死句柄防护协作;VM 全局单例接入 |
| `App/src/views/settings/settings_view_model.rs` | `global_instance()`(OnceLock 单例,窗生命周期解耦)+ vm_new 计时测试 |
| `App/src/views/local_send/local_send_app_event_handler.rs` | `open_send_window()` 公开面(托盘 Send 接 GPUI 发送窗) |
| `App/src/services/tray/tray_icon_service.rs` | ACTIVATE 分支接召唤链;take force;VM 单例;移除高频 rebuild |
| `App/src/services/tray/tray_menu_controller.rs` | Exit→request_quit;菜单标题中文化(title_for:TranslationManager→zh 回退);menu_groups 纯函数 |
| `App/src/services/tray/tray_clean_exit_helper.rs` | request_shutdown→request_quit(停服务+退出真链) |
| `App/src/services/tray/tray_icon_renderer.rs` | 构建期 RGBA 嵌入+真 alpha 重着色+通道序修正 |
| `assets/`+`scripts/` | tray_icon_16.rgba、tray_translations_zh.json、convert/extract 脚本 |

## 5. 真机终验结果(用户手点,HITL)

| 菜单项/行为 | 结果 | 判据 |
|---|---|---|
| 设置开关反复三次 | ✅ | 用户确认"正常显示,不卡" |
| 显示主窗口 | ✅ | 快搜窗聚焦真图 |
| 发送到其他设备... | ✅ | HWND registered 1→2 增量 |
| 干净退出 | ✅ | 进程 0+服务 Stopped 双停(真日志) |
| 退出 | ✅ | 进程消失(18:03) |
| 左键 toggle | ✅ | 合成+手点双通道 |
| 双击 Ctrl/ESC 唤回 | ✅(恢复后) | hook IpcMessageId(41) 真发+用户确认 |
| 禁用快捷键 | ⏳ | 热键链恢复后按同法验证 |
| 设置窗 X 关闭钮 | ❌ 挂账 | 系统 chrome 关闭消息未处理;任务栏关闭可绕 |

## 6. 教训与纪律沉淀

1. **锁域纪律**:持有跨域锁(STATE)时**禁止调用任何可能再取锁的设施**
   (logger/组件 API);回调与日志一律在锁外。打点夹逼是锁域死锁的
   最快定位法。
2. **事件驱动的重建要算频率**:每次用户交互触发的 set_menu/重建在高频
   下会踩驱动层重入。动态刷新选**低频触发点**(语言变化/生命周期),
   不选每次交互。
3. **通道竞态**:LazyLock 惰性首用 + take 型消费 = 首用晚于 take 即静默
   丢失。take 侧 `LazyLock::force` 强制实例化。
4. **窗槽生命周期**:窗口可被用户关闭,槽内句柄必须 `IsWindow` 真验后
   才可复用;死句柄清槽重建。
5. **gpui-kit 契约**:`init` + `Root::new(view, window, cx)` 真包是每窗
   硬性形态;绕开的故障是**条件触发**(静止正常、焦点/overlay 快变即崩),
   code review 静读难以发现——**真机多窗焦点互切必须进回归**。
6. **表象≠根因**:五表象五根因;每个根因都要独立证据链,
   直觉判断全部落空后,程序化反馈环才是生产力。
7. **合成驱动边界**:Shell 托盘(任务栏/溢出面板)对 mouse_event 合成
   点击不可靠(DOWN/UP 需间隔、菜单项点击不命中);HITL+日志判据为准。
8. **日志基础设施**:logger 单行写文件(append)在高频/持锁场景有死锁
   与性能两面风险;考虑 lock-free/异步化(独立改进)。

## 7. 遗留挂账(独立工单)

1. **服务 PipeServer 监听失效**:服务活而管道死(多窗/高频操作后),
   热键链全断的根因;服务日志 20:14 后零活动。服务域深挖。
2. **孤儿用户会话服务进程**:Restart-Service 不清用户会话实例(9944),
   与新服务互竞。服务生命周期真析。
3. **hook 死循环根因**:拉起失败时的循环策略与退避。
4. **设置窗 12 页内容渲染**:各页控件 GPUI 域波次(viewport≠bounds、
   系统 chrome X 无响应、PopUp/Normal 形态选择一并归入)。
5. **托盘图标生产化**:占位 RGBA→主题图标管线、DPI 面(SM_CXSMICON)。

## 8. 工具与脚本留档(`.scratch/`)

| 脚本 | 用途 |
|---|---|
| `probe_hung.py` | IsHungAppWindow 枚举判 hung(红绿判定器) |
| `probe_dump.py` | MiniDumpWriteDump 抓转储 |
| `probe_localsend.py` / `probe_set_localsend.py` | 部署配置读/写探针 |
| `scripts/convert_tray_icon.py` | tray.png→16×16 RGBA(构建期一次性) |
| `scripts/extract_tray_translations.py` | zh-CN 文案→嵌入资产(单一源) |
| `docs/09-test/test-01/drive-*.ps1` | 合成点击/截图/窗口枚举(HITL 辅助) |

dump 留档:`.scratch/ak97_hang.dmp`(921KB,AppHang 现场,待 WinDbg 分析)。

## 9. 追记(S60c):AppHang 终根因定案与因果实验

### 9.1 打点夹逼终钉

三轮加密打点后死点定案(时间戳链,08:20:19 与 08:25:01 两轮同形):

```
cmd enter → options → open_window → inner view(107ms)→ SettingsWindow::new(0ms)
→ Root → render enter/exit(1ms)→ open_window Ok → HWND extracted
→ match enter → slot assigned → [断]
```

死点 = `slot assigned` 之后、注册日志之前——即**持 STATE 锁时调用
`logger::log`**(内部 `LOG_STATE.lock()`)。修复:槽赋值后 `drop(state)`
再打日志。真机真绿(用户:"正常显示,不卡")。

### 9.2 Root 契约复核

二分占位视图(不持 VM)仍卡 → Root 缺失**降级为契约债**,不是本次死锁
直接根因。对照刀(QuickSearchWindow 挂设置链)证明 GPUI 第二窗层干净。

### 9.3 服务管道死因果实验(热键链真相)

设置窗开关后,服务日志止于 `Request received: 9`(= `SUBSCRIBE_STATUS`
流式订阅),随后全部命令 connect timeout、hook 拉起(命令 15)失败、
热键死;事件管道(IpcMessageId 41)独立存活。两轮复现(09:49/10:10 同
命令 9)。

**因果链**:设置窗打开 → VM(status_monitor)→ `ensure_status_subscription`
→ 命令 9 流订阅 → 服务侧 `stream_status_updates` 挂死 → 命令管道全死 →
hook 拉起(15)失败 → 热键死。

- 服务侧 ListenLoop/max_instances(254)/流循环(signal.acquire 等待)
  逐项排除后,挂死机理在更深处——**dmp 留档待 WinDbg 分析**(工具缺,如实挂)。
- 临时绕行:服务重启(Restart-Service)恢复热键;孤儿用户会话服务进程
  (9944)需 taskkill 清理。
- 长期:SUBSCRIBE_STATUS 与命令连接的隔离面(双管道设计已注明
  "订阅/命令必须两条连接"——真断点在订阅流内部,待 dump 定案)。

### 9.4 close-and-clean-up 契约落地(multi-window 文档)

- `on_window_should_close`:设置窗显式订阅(return true 透传)——
  Alt+F4 真关验证 ✅(契约钩子生效);X 钮仍不关(tao 层吞
  `WM_SYSCOMMAND(SC_CLOSE)`,挂 tao/GPUI chrome 波次)。
- `cx.on_window_closed`:app 级订阅,按 WindowId 清理(设置窗槽
  IsWindow 兜底互为闭环);清理链(prewarmer/图标缓存/工作集)挂窗口域波次。
- **托盘策略**(真引句落地):"If your app can reopen a window from the
  dock or tray, choose that policy instead of quitting"——快搜窗常驻
  (ESC=Hide),末窗关闭罕见,退出语义保持 C# parity(OnLastWindowClose)。
