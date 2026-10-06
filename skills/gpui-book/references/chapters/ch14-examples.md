# Chapter 14: Examples — Hello World and Counter (end-to-end examples)

> Source: The GPUI Book — the two examples sections. Corresponding original text: `src/examples/`.

## Core Idea

The two official minimal examples cover the complete skeleton of a GPUI application: Hello World shows "window creation + root view + static text"; Counter shows the complete closed loop of "state + stateful interaction + cx.listener + notify". The main of every example follows the same template.

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

- **Key points**: `size_full().flex().items_center().justify_center()` is the most common centering opener; color helpers (`white`/`black`/`red`/`green`/`blue` etc., scattered across the book's example code).

## Worked Example 2: Counter (state closed loop)

(main and use imports omitted; main differs from Hello World only in the root view construction: `app.new(|_cx| RootView { count: 0 })`)

```rust
struct RootView { count: isize }

impl Render for RootView {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        div().size_full().flex().items_center().justify_center().gap_5().bg(white())
            .child(                                     // "-" button
                div().id("decrement_button")
                    .cursor_pointer().flex().items_center().justify_center()
                    .size_8().rounded_md().border_1().border_color(black())
                    .child("-")
                    .hover(|style| style.bg(red()))
                    .on_click(cx.listener(Self::decrement)),
            )
            .child(                                     // count display
                div().min_w_16().text_3xl().text_center()
                    .child(self.count.to_string()),
            )
            .child(                                     // "+" button
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
        cx.notify();                                    // without this line the UI does not refresh
    }
    fn decrement(&mut self, _event: &ClickEvent, _window: &mut Window, cx: &mut Context<Self>) {
        self.count -= 1;
        cx.notify();
    }
}
```

- **Key points**:
  1. `cx.listener(Self::method)` turns a view method into an on_click callback (the book only uses cx.listener in the Counter example without explaining the mechanism; this is a generalization).
  2. The handler signature is fixed: `fn m(&mut self, event: &ClickEvent, window: &mut Window, cx: &mut Context<Self>)`.
  3. Interaction closed loop = `.id()` → `on_click(cx.listener)` → mutate state → `cx.notify()`.
  4. `.hover(|style| style.bg(...))` shows hover-state styling.

## Key Takeaways

1. Every GPUI application's main follows the same template: `Application::new().run` → `open_window` → `app.new(|cx| RootView)`.
2. The four-piece interaction loop: id → listener → mutate state → notify.
3. Display dynamic text with `self.count.to_string()` (pedagogical style); in production prefer SharedString per ch06.

## Connects To

- **ch10**: the precondition rules of `.id()` + `on_click`.
- **ch02/ch12**: the principle of the notify → re-render loop.
