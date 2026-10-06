# Chapter 14: Examples — Hello World 与 Counter（端到端范例）

> 来源：The GPUI Book — examples 两节。对应原文：`src/examples/`。

## Core Idea

两个官方最小范例覆盖 GPUI 应用的完整骨架：Hello World 展示"建窗 + 根 view + 静态文本"；Counter 展示"状态 + 有状态交互 + cx.listener + notify"的完整闭环。所有范例的 main 都是同一个模板。

## Worked Example 1: Hello World

```rust
use gpui::{AppContext, Application, Context, IntoElement, ParentElement, Render, Styled,
           Window, WindowOptions, div, white};

struct RootView;

impl Render for RootView {
    fn render(&mut self, _window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        div()
            .size_full()
            .flex()
            .items_center()
            .justify_center()
            .bg(white())
            .child("Hello World!")
    }
}

fn main() {
    Application::new().run(|app| {
        app.open_window(WindowOptions::default(), |_window, app| {
            app.new(|_cx| RootView)
        })
        .unwrap();
    });
}
```

- **要点**：`size_full().flex().items_center().justify_center()` 是最常用的居中起手式；颜色 helper（`white`/`black`/`red`/`green`/`blue` 等，散见于书示例代码）。

## Worked Example 2: Counter（状态闭环）

（省略 main 与 use 导入；main 与 Hello World 仅根 view 构造不同：`app.new(|_cx| RootView { count: 0 })`）

```rust
struct RootView { count: isize }

impl Render for RootView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        div().size_full().flex().items_center().justify_center().gap_5().bg(white())
            .child(                                     // "-" 按钮
                div().id("decrement_button")
                    .cursor_pointer().flex().items_center().justify_center()
                    .size_8().rounded_md().border_1().border_color(black())
                    .child("-")
                    .hover(|style| style.bg(red()))
                    .on_click(cx.listener(Self::decrement)),
            )
            .child(                                     // 计数显示
                div().min_w_16().text_3xl().text_center()
                    .child(self.count.to_string()),
            )
            .child(                                     // "+" 按钮
                div().id("increment_button")
                    .cursor_pointer().flex().items_center().justify_center()
                    .size_8().rounded_md().border_1().border_color(black())
                    .child("+")
                    .hover(|style| style.bg(green()))
                    .on_click(cx.listener(Self::increment)),
            )
    }
}

impl RootView {
    fn increment(&mut self, _event: &ClickEvent, _window: &mut Window, cx: &mut Context<Self>) {
        self.count += 1;
        cx.notify();                                    // 缺了这行界面不刷新
    }
    fn decrement(&mut self, _event: &ClickEvent, _window: &mut Window, cx: &mut Context<Self>) {
        self.count -= 1;
        cx.notify();
    }
}
```

- **要点**：
  1. `cx.listener(Self::method)` 把视图方法变成 on_click 回调（书仅在 Counter 范例中使用 cx.listener，未解释机制，此处为归纳）。
  2. handler 签名固定：`fn m(&mut self, event: &ClickEvent, window: &mut Window, cx: &mut Context<Self>)`。
  3. 交互闭环 = `.id()` → `on_click(cx.listener)` → 改状态 → `cx.notify()`。
  4. `.hover(|style| style.bg(...))` 展示 hover 态样式。

## Key Takeaways

1. 所有 GPUI 应用的 main 同一模板：`Application::new().run` → `open_window` → `app.new(|cx| RootView)`。
2. 交互闭环四件套：id → listener → 改状态 → notify。
3. 显示动态文本用 `self.count.to_string()`（教学写法）；生产按 ch06 优先 SharedString。

## Connects To

- **ch10**: `.id()` + `on_click` 的前置规则。
- **ch02/ch12**: notify → 重渲染的闭环原理。
