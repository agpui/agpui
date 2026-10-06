# Patterns（技法与模式）

格式：**When to use**（何时用）→ **How**（怎么做）→ **Trade-offs**（代价）。全部出自 The GPUI Book 正文或其范例代码。

## notify 闭环（状态 → 界面）
**When**: 任何 entity 状态修改之后。
**How**: `entity.update(app, |state, cx| { state.x = ...; cx.notify(); })` —— 修改与 notify 在同一闭包内；T: Render 时自动重渲染。
**Trade-offs**: 忘 notify = 界面静默不更新（最常见 bug）；notify 过频 = 冗余渲染，粒度按 Entity 划分（延伸）。

## cx.listener 方法 handler
**When**: on_click 等回调需要读写视图自身状态。
**How**: `.on_click(cx.listener(Self::increment))`；方法签名 `fn increment(&mut self, event: &ClickEvent, window: &mut Window, cx: &mut Context<Self>)`，方法内改状态 + `cx.notify()`。
**Trade-offs**: 一行逻辑用内联闭包；多行或复用逻辑用方法 + listener（延伸）。

## 有状态交互三步
**When**: 需要 on_click / on_hover 等跨帧交互状态。
**How**: `.id("stable_id")` → 挂 handler → id 跨帧保持不变。
**Trade-offs**: id 变化 = 交互状态丢失；无状态 handler（如某些事件）则不需要 id。

## 文本零分配渲染
**When**: render 内产出文本。
**How**: 静态 → `&'static str`；动态 → 文本存 `SharedString` 进 Entity 状态，render 里 `self.text.clone()`；仅一次性文本可用 String/format!。
**Trade-offs**: String 简单直白，但每帧堆分配；SharedString 多一处状态字段。

## z 序控制（deferred）
**When**: 元素需要盖住先绘制的兄弟（tooltip、浮层雏形）。
**How**: `deferred(child)` 推迟绘制；`deferred(child).with_priority(n)` 控制相对次序，n 大者在上。
**Trade-offs**: GPUI 无显式 z-index（延伸），顺序即层级；deferred 推迟的是 layout 与 paint。

## 执行器选型
**When**: 任何异步工作。
**How**: 碰 UI / 应用状态 → `App::spawn` / foreground_executor；纯计算/IO → background_executor；不收结果 → `.detach()`；定时 → background `timer(Duration)` + await。
**Trade-offs**: foreground 阻塞 = 全应用冻结；background 结果回主线程需再 spawn 到前台（延伸）。

## 动作链五步
**When**: 键盘命令 / 可绑定命令。
**How**: `actions!(ns, [A])` → `KeyBinding::new("keystroke", A, ctx)` → `app.bind_keys([...])` → 元素级再 `track_focus(&fh)` + `fh.focus(window)` → `on_action` 回调。
**Trade-offs**: 跨平台用 `secondary`；同一 keystroke 多绑定时用 key_context 限定作用域（延伸）；App 级 on_action 免焦点全局兜底。

## 全局设置仓库
**When**: 全应用共享一份的状态（设置、主题等）。
**How**: `impl Global for T {}` → `set_global` → `global`/`global_mut` 读改 → `observe_global` 订阅变更。
**Trade-offs**: 未设置就读 → panic；防御路径：`try_global` / `has_global` / `default_global`（Default 回退）。

## 弱引用防环
**When**: Entity 互相持有或长期保存其它 Entity。
**How**: `entity.downgrade()` → `WeakEntity`，用时再升级。
**Trade-offs**: 升级需处理已释放的情况（延伸）；强引用则生命周期由 GPUI 统一管理。

## 焦点驱动的元素级动作
**When**: 同一动作希望"谁聚焦谁响应"，而不是全局触发。
**How**: view 持有 `FocusHandle`（`app.focus_handle()` 创建）→ render 里 `.track_focus(&self.focus_handle)` → 构建时 `focus_handle.focus(window)` → 元素挂 `on_action`。
**Trade-offs**: 焦点管理要自管（谁、何时聚焦）；全局动作无此成本。
