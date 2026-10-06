# Glossary（术语表）

按字母序。`→ chN` 指向章节文件。标注（书未展开）的条目仅出现在书的类型总表中，无正文。

**Action** — 键盘/命令系统的单元结构体，由 `actions!` 宏在命名空间下生成；经 KeyBinding 绑定按键、on_action 绑定回调 → ch11, ch02

**Animation** — 时长+缓动+是否重复的配置；经 `with_animation`（AnimationExt）挂到元素 → ch09

**AnimationExt** — 提供 `with_animation` 的 trait（书仅示例代码 import 出现）→ ch09

**App** — 应用全局状态容器；open_window / on_action / spawn / bind_keys / global 系列的持有者 → ch02, ch04

**AppContext** — trait；`App`、`Context<T>` 等实现之，deref 到 App 以访问 entities → ch03

**Application** — 入口对象；`new()` 创建、`run(callback)` 启动 → ch02

**AsyncApp** — `App::spawn` 异步闭包的参数；异步侧访问应用状态 → ch02, ch13

**AsyncWindowContext** — 异步窗口上下文（书未展开）→ 书类型总表

**BackgroundExecutor** — 后台线程执行器；spawn / timer → ch13

**ClickEvent** — on_click 回调的点击事件参数 → ch10, ch14

**Context\<T\>** — Entity 专属上下文；deref 到 App，另有 `notify()` 等 → ch02, ch03

**Deferred** — 延迟 layout/paint 的元素；`with_priority` 控制叠放次序 → ch05

**Div** — 最常用容器元素 → ch05

**ElementId** — 元素标识；交互状态与动画的追踪键，必须跨帧稳定（交互 id 与 InteractiveText id 为书明文；动画侧为归纳）→ ch06, ch09, ch10

**Entity\<T\>** — GPUI 持有的状态句柄；T: Render 时即 view → ch03

**FocusHandle** — 焦点句柄；`track_focus` + `focus()` 后元素级 on_action 才能收到 action → ch11

**ForegroundExecutor** — 主线程执行器；禁止阻塞操作 → ch13

**Global** — 全应用共享状态的 marker trait → ch04

**ImageSource** — `img()` 参数的转换目标类型（枚举）；Path 等可经 `Into<ImageSource>` 转换 → ch05

**InteractiveElement** — 无状态交互 trait（.id / key_context / track_focus / on_action）→ ch10, ch11

**InteractiveText** — 文本区间点击/悬停组件 → ch06

**KeyBinding** — keystroke + action + key context 的绑定；`KeyBinding::new` → ch11

**key context** — 限定按键绑定生效范围的字符串上下文；元素用 `key_context()` 声明 → ch11

**keystroke modifiers** — ctrl / alt / shift / fn / cmd(super/win) / secondary → ch11

**Painter's algorithm** — 后画者覆盖先画者的绘制次序规则；deferred 由此控制层级 → ch05

**ParentElement** — 提供 `.child` / `.children` 的 trait（书仅示例代码 import 出现）→ ch05

**ReadGlobal / UpdateGlobal** — `T::global` / `T::set_global` / `T::update_global` 便捷方法的来源 trait（书仅示例代码 import 出现）→ ch04

**Render** — retained mode view trait；`&mut self + Context<Self>`；notify 驱动 → ch12

**RenderOnce** — immediate mode component trait；`self + App`；需 `#[derive(IntoElement)]` → ch12

**SharedString** — 廉价 clone 的不可变字符串；render 友好，替代 String → ch06

**SharedUri** — 共享 URI 类型（书未展开）→ 书类型总表

**StatefulInteractiveElement** — 有状态交互 trait（on_click / on_hover）；前置 `.id()` → ch10

**StrikethroughStyle / UnderlineStyle** — 删除线 {thickness, color} / 下划线 {thickness, color, wavy} 样式结构 → ch06, ch08

**Style** — 元素样式底层结构体；Taffy 布局属性承载 → ch07

**Styled** — 元素样式 trait（`.style()` 与工具函数入口）→ ch07

**StyledImage** — 图片样式 trait（`.image_style()`：grayscale / object_fit / loading / fallback）→ ch08

**StyledText / TextRun** — 分区间样式的文本组件 / 区间描述（len+font+color+background_color+underline+strikethrough 等）→ ch06

**Subscription** — `observe_global` 等的返回值；必须持有或 `.detach()` → ch04

**Taffy** — GPUI 底层布局引擎（flexbox）→ ch07

**Task\<T\>** — 异步任务句柄；drop 即取消；`.detach()` 放行 → ch13

**TestAppContext** — 测试专用上下文（书未展开）→ 书类型总表

**view** — T 实现 Render 的 Entity\<T\> 的惯称 → ch03, ch12

**WeakEntity** — `entity.downgrade()` 的弱指针 → ch03

**Window** — 平台窗口；`bounds()` / `mouse_position()` → ch02

**WindowOptions** — `open_window` 的配置参数 → ch02

**with_animation** — 三参数（id, Animation, delta 闭包）挂载动画 → ch09
