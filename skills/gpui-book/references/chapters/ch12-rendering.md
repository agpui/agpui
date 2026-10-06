# Chapter 12: Rendering — Render and RenderOnce (the hybrid rendering model)

> Source: The GPUI Book — the two rendering sections. Corresponding original text: `src/rendering/`. This is the most important concept chapter of the book (editorial emphasis, not in the book).

## Core Idea

GPUI is a **hybrid rendering** framework: `Render` (retained mode) — a view carried by an Entity, re-rendered only when notified; `RenderOnce` (immediate mode) — constructed, rendered, and immediately discarded components that live inside a view's render. Views can freely nest components.

## Key Concepts

- **`Render`** (retained / view layer):
  ```rust
  fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement
  ```
  Makes T of an `Entity<T>` a view; without notify there is no re-render (the meaning of "retained").
- **`RenderOnce`** (immediate / component layer):
  ```rust
  #[derive(IntoElement)]
  struct SomeComponent;
  impl RenderOnce for SomeComponent {
      fn render(self, window: &mut Window, cx: &mut App) -> impl IntoElement { div() }
  }
  ```
  - **Takes over `self`** (by value, in contrast to Render's `&mut self`) — suits components that store no mutable state of their own
  - constructed, rendered, then discarded; rebuilt on every re-render of the view (driven by notify)
  - needs `#[derive(IntoElement)]` to be usable as a child

## Code Examples

```rust
impl Render for RootView {
    fn render(&mut self, _w: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        div().child(SomeComponent)   // an immediate component nested inside a retained view
    }
}
```

- **What it demonstrates**: how the two traits cooperate — the view keeps state, and the component tree is rebuilt on every re-render of the view (driven by notify).

## Mental Models

- **Use Render when**: the type is stateful, must survive across frames, and updates are driven by notify → view (Entity).
- **Use RenderOnce when**: a stateless display/composition unit, parameters in, element out → component.

## Anti-patterns

- **Putting application state inside a RenderOnce component**: render takes ownership, leaving the component nowhere to keep cross-frame state; state belongs to the view (Entity).

## Key Takeaways

1. The signature difference is the exam point: `&mut self + Context<Self>` (Render) vs `self + App` (RenderOnce).
2. Custom components must `#[derive(IntoElement)]`.
3. The running picture = notify → view re-render → rebuild the RenderOnce component tree — "retained wrapping immediate".

## Connects To

- **ch02/ch03**: Entity + notify are what drives Render.
- **ch14**: the counter example shows the complete state loop of a Render view.
