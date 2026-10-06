# opt-05: 激活管道 os-231 复盘——最响的错误不是病因,静默 no-op 才是

> S82→S83 两轮诊断的提炼(工单 07 → 22 → 25 → S83,横跨 4 张票的连环误导)。
> 姊妹篇:opt-02-PipeServer.md(同线程 Mutex 重入)、opt-04-cpu.md(全局单例生命周期)。
> 诊断纪律:mattpocock-skills/diagnosing-bugs 六阶段;取证:app.log 时间线 + RM-S83 真机截图。

## 1. 背景与现象

第二实例携带 `ak97://localsend/items/<URL编码路径>` 启动时,LocalSend 发送窗偶发不打开。
app.log 同时出现:

| 现象 | 首因直觉(错) |
|---|---|
| `[AppPipeService] Named pipe server error: 所有的管道范例都在使用中。 (os error 231)` | 转发被 231 阻断(错——转发静默成功了) |
| 发送窗不打开 | 管道转发失败所致(错——真因与 231 无关) |
| 231 间歇出现(15:0x 成功/16:29 失败) | 服务循环不稳定(错——循环自愈正常) |
| 票 07 已修"句柄继承" | 修复不彻底,还有残留(错——继承从来不是根因) |

**误导结构的完整还原**:231 以 Error 级别出现在错误时间点附近,看起来像病因;
而真正的病因(路由站点 no-op)**一行日志都没有**。两轮排查(票 07 句柄继承、
S82 初判"231 阻断转发")都被这个响亮的错误带偏。

## 2. 根因(两个独立缺陷 + 一个误判放大器)

### D1: os-231 本体 = max_instances=1 的固有瞬态(良性)

激活管道 `max_instances(1)` + 服务循环「create → connect → read → drop → 再 create」,
客户端端未关闭时(第二实例进程退出慢)重建必得 ERROR_PIPE_BUSY(231)。这是该管道
形态的固有窗口,不是缺陷;服务端退避后自愈,客户端有 5s 重试预算兜底。

**缺陷只在处置**:旧实现 Error 级日志 + 1000ms 退避——把预期瞬态渲染成刺眼错误,
且把服务端盲窗拉长到一秒。

### D2: 发送窗不打开的真因 = 路由站点静默 no-op

`uri_router::route_local_send` 解析 URL、校验设置、算好 mode,然后:

```rust
// TODO(port)[3]: LocalSendAppEventHandler.OpenSendWindow(...)（…尚未接线…）
let _ = mode;
let _ = (request.files, request.text);
```

打开发送窗的动作是**无日志、无错误、无效果的静默 no-op**。与 231 毫无因果关系
(假说裁决:H2 转发被阻——排除,第二实例无 Failed 日志即客户端静默成功;
H3 服务循环死——排除,continue 语义;H4 mutex 漏检——排除,无 Pipe servers starting 行)。

### 误判放大器:Error 日志的时间邻近性

231 恰好在第二实例启动后 9ms 出现——时间邻近性让它"看起来是原因"。
诊断纪律的价值:假说排序阶段用**既有日志证据**排除了 H2/H3/H4,才没有第三次修错方向。

## 3. 修复(S83,commit 91e64ba)

| 项 | 修法 | 回归钉 |
|---|---|---|
| D1 | create 231 分支:退避 1000ms→50ms + 日志降 Debug(预期瞬态非错误);其余错误维持 Error+1000ms | `activation_pipe_rearms_quickly_after_client_lingers`:客户端端滞留释放后 300ms 内恢复监听——实测 **263µs**(旧码全窗失败必红) |
| D2 | 接线 `request_send_window_open_with(files,text)` → 既有 SEND_WINDOW_TX 命令泵(站点 AddFiles/ShowTextMode 原样消费;mode 由 files/text 有无隐含) | `send_window_channel_contract`:正(路径原样入通道)/负(非法 URI 无请求)两腿 |
| 真机 | `ak97://localsend/items/...` → LocalSend 发送窗打开(RM-S83-01) | max_instances 维持 1(源语义,零偏离) |

## 4. 经验教训

### 教训一:最响的错误不是病因,完全无日志的路径才最危险

231(Error 级、时间邻近)连续误导两轮排查;真正的病因是**零日志的静默 no-op**。
命令路径上的动作站点如果不接线又不上报,它就和成功无法区分——这不是理论风险,
是让两轮诊断白做的实害。

**规则化**:命令/动作路径上的未接线站点(TODO(port))必须 `Warn` 日志 + 显式标识,
禁止裸 `let _ = ...` 吞载荷。收口手段:对 dispatch/action 类路径做一次
"静默 no-op 审计"(grep TODO(port) 于 dispatch/route/handler 面),发布前清零。

### 教训二:翻译缺陷聚集在"无编译期对应物"的语义面,parity 测试全部不可见

S82/S83 五个真机缺陷(Results 通知缺失、转发订阅即弃、防抖漏 Cancel、
析构序悬垂、本篇 no-op)全部是 C#/WPF 语义→Rust 翻译时丢失的**接线面**:
CollectionChanged、CancellationToken.Cancel 副作用、事件订阅生命周期、
Dispatcher 封送。它们不是逻辑错误——golden parity(索引/排序/事件流)全绿,
单测全绿,只有真机 HITL 才暴露。

**规则化**:每窗/每功能维护"接线清单"(事件源→VM notify→窗口桥→视图),
headless 测得到的(通知到达、通道载荷)落为回归钉,测不到的(物理热键、
真窗渲染)显式列入 HITL 清单——不进清单的接线面等于没验收。

### 教训三:RAII 句柄 `let _ = _sub` 即弃 = 订阅即死,且析构序能造出段错误

`PropertyChangedSubscription` 是 Drop 即退订的句柄;`let _ = _sub` 构造即丢,
子→父属性转发链生来即死。修复时又踩出第二层:**字段析构序**——订阅句柄字段
声明在通知源字段之后,先析构源再析构订阅,RAII Drop 解引用悬垂指针直接
STATUS_ACCESS_VIOLATION。

**规则化**:①订阅句柄禁止 `let _` 丢弃,一律入 `_*_subs` 集合字段随宿主存活;
②持有"指向兄弟字段内对象"的 RAII 句柄时,字段声明序必须先于被指向者
(Rust 按声明序析构);③此两类面各配一条结构断言或编译期可见的命名约定。

### 教训四:预期瞬态不配 Error 级日志,盲窗要有量化回归钉

ERROR_PIPE_BUSY(231) 是 max_instances=1 管道的固有节拍。Error 级 + 1s 退避
让它(1)污染取证视野,(2)把服务端盲窗拉长 20 倍。

**规则化**:错误分级按"是否偏离预期"而非"是否非零返回码"——预期瞬态
= Debug + 短退避;并有量化钉锁行为(盲窗 300ms 上限,实测 263µs)。
"预期会失败的调用"没有日志级别语义,就没有取证价值。

### 教训五:假说排序用既有日志证据先行,防止"修第一个 plausible 想法"

本轮 H2/H3/H4 三条被排除的假说,每条都只花了一次 grep(第二实例无 Failed 日志/
continue 语义/无 Pipe servers starting 行)——比任何一次盲修都便宜。
opt-02/opt-04 的教训同构:先证伪,再动码。

**规则化**:diagnosing-bugs Phase 3 的 3-5 假说必须各附"既有日志可判据"——
能用现有证据排除的假说,禁止进入试修。

## 5. 防复发清单(可执行)

1. **静默 no-op 审计**(发布门禁):`grep -rn "TODO(port)" src/App/src --include="*.rs"` 过滤
   dispatch/route/handler/action 面,逐条确认"未接线"是否带 Warn 日志;无日志的 no-op
   即发布阻塞项。
2. **接线清单**:按功能域维护 事件→VM→视图 的 notify 链表(REFERENCES: docs/spec/lertaro-rsg
   各章"单元表"即现成底稿),headless 钉 + HITL 项双列。
3. **RAII 纪律**:clippy/人工复核禁 `let _ = *_sub*`;订阅句柄字段命名统一 `_forward_subs`
   型;析构序审查纳入 CODE REVIEW 清单。
4. **日志分级语义**:预期瞬态(Debug+短退避)/意外失败(Error+长退避或中止)二分,
   新增错误分支必须声明归属。
5. **假说纪律**:诊断必出 3-5 假说表 + 既有证据判据,附在 RUN-NOTES 条目中(S83 格式)。

## 6. 关联索引

- 工单:`.scratch/scheme-10-rsg/issues/{07,22,25}-*.md`(07 句柄继承审计、22 os-231 新证据、25 结果回显行)
- 提交:`8bed5b7`(批次)、`ac424aa`(S81 pump panic)、`d3c5912`(S82 三层)、`91e64ba`(S83 本篇)
- 截图:`docs/09-test/test-01/RM-S8{1,2}-*.png`、`RM-S83-01-send-window.png`
- 账本:`src/migration/RUN-NOTES.md` S80–S83
- 姊妹篇:opt-02(死锁)、opt-03(热键链)、opt-04(空闲 CPU)——同为"翻译接线面"缺陷家族
