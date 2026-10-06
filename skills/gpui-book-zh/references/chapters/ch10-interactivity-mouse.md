# Chapter 10: Interactivity — Mouse（有状态 vs 无状态交互）

> 来源：The GPUI Book — interactivity/mouse。对应原文：`src/interactivity/mouse.md`。

## Core Idea

交互分两档：`InteractiveElement` 提供无需状态的事件处理；`on_click` / `on_hover` 需要跨帧元素状态，属 `StatefulInteractiveElement` —— 必须先 `.id(ElementId)` 使元素有状态，且 **ID 跨帧不能变**。

## Key Concepts

- **`.id("some_id")`**：`InteractiveElement` 提供；调用后元素变为有状态（`Stateful<Div>`），才能用 `on_click` / `on_hover`。id 在此场景下的作用是让 GPUI 跨渲染帧跟踪该元素的状态。
- **`on_click`**：用户完成左键点击时触发（**release 时**，非按下）。闭包参数：`ClickEvent`、`&mut Window`、`&mut App`。
- **`on_hover`**：进入与离开 hover 各触发一次。闭包第一参数 `bool`（true 进入 / false 离开），另有 Window、App。
- **相关样式**：`cursor_pointer()`（悬停光标）、`.hover(|style| style.bg(red()))`（hover 态样式，见 ch14 counter）。

## Code Examples

（省略样式调用，书 snippet 另含 .text_color(white()).h_6() 等样式链）

```rust
div()
    .id("some_id")                       // 有状态化 —— on_click 的前置条件
    .bg(red())
    .child("Click Here")
    .on_click(|event, _window, _app| {
        println!("{event:#?}");
    })
```

（省略样式调用，书 snippet 另含 .text_color(white()).h_6() 等样式链）

```rust
div().id("some_id").child("Hover Here").on_hover(|hovered, _window, _app| {
    println!("{}", if *hovered { "Hover started" } else { "Hover ended" });
})
```

- **What it demonstrates**：`.id()` → handler 的固定顺序；on_hover 的 bool 语义。

## Anti-patterns

- **不加 `.id()` 直接 `on_click`**：编译不过——`StatefulInteractiveElement` 只存在于有状态元素上。心智口诀：**要 on_click/on_hover，先 id**。
- **id 跨帧变化**：hover 等交互状态跟踪失效。

## Key Takeaways

1. `.id()` 是交互状态的前置条件，也是组件组合中最容易漏的一步。
2. `on_click` 在鼠标 release 时触发（不是 mousedown）。
3. 需要访问视图自身状态时，用 `cx.listener(Self::method)`（ch14 counter 的标准写法）。

## Connects To

- **ch06**: InteractiveText 的区间点击是文本层交互，与元素层 `.id()` 同为 ElementId 体系。
- **ch11**: 键盘交互的动作链；`key_context` 同属 InteractiveElement。
- **ch14**: counter 范例 = 本章 + notify 闭环的合体。
