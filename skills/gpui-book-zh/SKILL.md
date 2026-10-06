---
name: gpui-book-zh
description: "知识库：The GPUI Book（matinaniss 著，GPUI 是驱动 Zed 编辑器的 Rust GPU 加速 UI 框架）。开发 GPUI / Zed 生态桌面应用时使用：应用启动链（Application/App/Window/Context）、Entity 与 Global 状态管理、Div/Text/Img/Deferred 元素、Taffy 样式与布局、动画、鼠标与键盘动作/焦点、Render 与 RenderOnce 混合渲染、前台/后台异步执行器，含可复制的最小范例代码。覆盖 GPUI 框架本身；组件库用法与设计规范分别见 gpui-kit、gpui-kit-design-guides 技能。"
---

<!-- argument-hint: [主题、框架名或章节号，如 "Entity"、"global"、"ch11"] -->

# The GPUI Book（中文版）

**作者**: matinaniss | **形态**: mdBook（39 小节 + 52 代码片段） | **章节**: 14（本技能） | **生成**: 2026-10-02 | **校对**: 2026-10-06（对照源书逐节核验，错误已修正，书外引申标注「延伸」）
**源**: [github.com/matinaniss/gpui-book](https://github.com/matinaniss/gpui-book)（已克隆至 `ref-projs/gpui-book`）

## How to Use This Skill

- **无参数** — 加载下方核心心智模型作参考
- **带主题** — 问 `Entity`、`global`、`keybinding`、`deferred` 等词；先查 Topic Index，再读对应章节文件后作答
- **带章节** — 问 `ch11`；直接加载该章
- **浏览** — 问"有哪些章节？"看 Chapter Index

回答未被 Core Frameworks 覆盖的问题前，先读相关章节文件。

---

## Core Frameworks & Mental Models

**1. 混合渲染模型（全书第一概念）**
Use `Render` when 状态要存活多帧、由 notify 驱动更新（view = `Entity<T>`，T: Render）。Use `RenderOnce` when 无状态组件、参数进元素出（`render(self, ...)` 接管所有权，需 `#[derive(IntoElement)]`）。运行画面：notify → view 重渲染 → 每帧重建 RenderOnce 组件树——retained 包 immediate。

**2. GPUI 拥有一切，你只拿句柄**
Entity、Global 都 owned inside `App`；你持有 `Entity<T>` 句柄（clone 便宜）。实现 `AppContext` 的类型（`App`、`Context<T>`、`AsyncApp`…）都 deref 到 `App`——"能不能用 App 的方法"先看 deref 链。

**3. notify 契约**
改了状态必须 `cx.notify()`（Context\<T\>），否则界面静默不刷新——GPUI 最常见"为什么没更新"的根因（经验判断，书未明说）。update 闭包 = 事务现场：修改与 notify 同闭包完成。

**4. 启动链固定**
`Application::new().run(|app| { app.open_window(WindowOptions::default(), |window, app| { app.new(|_cx| RootView) }).unwrap(); })` —— 所有 GPUI 应用的 main 都是这个模板。

**5. 有状态交互先 id**
`on_click` / `on_hover` 需要跨帧元素状态 → 必须先 `.id("stable_id")`（StatefulInteractiveElement），id 跨帧不能变。`on_click` 在 release 时触发。访问视图方法用 `cx.listener(Self::method)`。

**6. 键盘 = 动作五步链**
`actions!(ns, [A])` → `KeyBinding::new("keystroke", A, ctx)` → `app.bind_keys([...])` → 元素级 `track_focus(&fh)` + `fh.focus(window)` → `on_action`。跨平台修饰符用 `secondary`（macOS=platform 键，其余=control）。App 级 `on_action` 免焦点全局兜底。

**7. 样式 = Taffy flexbox 双路径**
CSS 风格链式工具函数（`.flex().flex_col()...`）与直接改 `Style` 结构体等价（`Styled` trait 的 `.style()`）。overflow 是 x/y 独立的 `Point<Overflow>`。

**8. 文本零分配**
render 里的文本：静态用 `&'static str`；动态存 `SharedString` 进 Entity、render 里 clone。`String` 每帧堆分配，书明确少用。

**9. 异步双执行器**
碰 UI/应用状态 → 主线程（`App::spawn`/foreground）；纯计算/IO → background。`Task<T>` **drop 即取消**，不收结果就 `.detach()`。foreground 阻塞 = 整个应用冻结。

**10. 顺序即层级**
GPUI 无显式 z-index（延伸），遵循 Painter's algorithm（后画者在上）。要盖住别人：`deferred(child).with_priority(n)`，n 大者在上。

**11. 句柄必须显式处理**
`observe_global` 的 `Subscription`、异步 `Task`：要么持有要么 `.detach()`，否则订阅失效/任务取消。读未设置的 global（`global()`/`global_mut()`）会 **panic**——防御用 `try_global` / `has_global` / `default_global`。

---

## Chapter Index

| # | 标题 | 关键内容 |
|---|------|----------|
| [ch01](references/chapters/ch01-getting-started.md) | Getting Started | 依赖引入、create-gpui-app、手动建项 |
| [ch02](references/chapters/ch02-architecture.md) | Architecture | Application/App/Window/Context、notify |
| [ch03](references/chapters/ch03-entity.md) | State — Entity | new/read/update/downgrade |
| [ch04](references/chapters/ch04-global.md) | State — Global | API 全表、panic 防御、observe_global |
| [ch05](references/chapters/ch05-elements.md) | Elements | Div/child/children、Img、Deferred+priority |
| [ch06](references/chapters/ch06-text.md) | Text | 5 种文本类型、SharedString、StyledText/InteractiveText |
| [ch07](references/chapters/ch07-styling-element.md) | Styling — Element | Taffy、双路径、flexbox 属性全表 |
| [ch08](references/chapters/ch08-styling-text-image.md) | Styling — Text & Image | 文本/图片样式属性、object_fit、loading/fallback |
| [ch09](references/chapters/ch09-animations.md) | Animations | Animation、with_animation、缓动 |
| [ch10](references/chapters/ch10-interactivity-mouse.md) | Interactivity — Mouse | .id()、on_click/on_hover、cx.listener |
| [ch11](references/chapters/ch11-interactivity-keyboard.md) | Interactivity — Keyboard | 动作五步链、修饰符、key_context、焦点 |
| [ch12](references/chapters/ch12-rendering.md) | Rendering | Render vs RenderOnce、混合模型 |
| [ch13](references/chapters/ch13-async.md) | Async | 前台/后台执行器、Task/detach、timer |
| [ch14](references/chapters/ch14-examples.md) | Examples | Hello World、Counter 完整闭环代码 |

## Topic Index

- **Action** → ch11, ch02
- **Animation / with_animation** → ch09
- **App / Application / Window / Context** → ch02
- **App::spawn / AsyncApp** → ch02, ch13
- **Deferred / z-index / Painter's algorithm** → ch05
- **Div / child / children / ParentElement** → ch05
- **ElementId** → ch06, ch09, ch10
- **Entity / WeakEntity / AppContext** → ch03
- **focus / FocusHandle / track_focus** → ch11
- **Global / set_global / observe_global / ReadGlobal** → ch04
- **Img / ImageSource / object_fit** → ch05, ch08
- **key context / keystroke modifiers / KeyBinding** → ch11
- **on_click / on_hover / id() / cx.listener** → ch10, ch14
- **on_action / actions! / bind_keys** → ch11, ch02
- **Render / RenderOnce / view** → ch12
- **SharedString / StyledText / TextRun / InteractiveText** → ch06
- **Styling / Style / Taffy / flex** → ch07, ch08
- **Subscription / detach** → ch04, ch13
- **Task / timer / executor** → ch13

## Supporting Files

- [glossary.md](references/glossary.md) — 全部术语与定义（含书类型总表中未展开的条目）
- [patterns.md](references/patterns.md) — 9 个技法模式（When/How/Trade-offs）
- [cheatsheet.md](references/cheatsheet.md) — 决策表、硬性前提清单、最小骨架、症状→根因

---

## Scope & Limits

本技能只覆盖 The GPUI Book 的内容。**书截至抓取时尚未撰写的部分**（源仓库中为空或仅有导言占位）：Svg / Anchored / List / Uniform List / Canvas 元素、Implementing Element（Request Layout / Prepaint / Paint）、Testing、类型总表的词条正文——本技能如实标注，不臆造内容；这些主题需要时查 `gpui-kit` 技能或 Zed 仓库源码。GPUI 随 Zed 持续演进，本书基于其撰写时的 API（git 主线），可能与最新版本有出入。组件库用法与设计规范见 `gpui-kit`、`gpui-kit-design-guides` 技能。源图片（2 张示例截图）未读取。
