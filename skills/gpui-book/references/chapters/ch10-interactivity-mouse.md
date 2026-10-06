# Chapter 10: Interactivity — Mouse (stateful vs stateless interaction)

> Source: The GPUI Book — interactivity/mouse. Corresponding original text: `src/interactivity/mouse.md`.

## Core Idea

Interaction comes in two tiers: `InteractiveElement` provides event handling that needs no state; `on_click` / `on_hover` need cross-frame element state and belong to `StatefulInteractiveElement` — the element must first be made stateful with `.id(ElementId)`, and the **ID must not change across frames**.

## Key Concepts

- **`.id("some_id")`**: provided by `InteractiveElement`; after the call the element becomes stateful (`Stateful<Div>`), which is what enables `on_click` / `on_hover`. In this scenario id lets GPUI track the element's state across render frames.
- **`on_click`**: fires when the user completes a left-button click (**on release**, not on press). Closure parameters: `ClickEvent`, `&mut Window`, `&mut App`.
- **`on_hover`**: fires once on entering hover and once on leaving it. The closure's first parameter is a `bool` (true = entered / false = left), plus Window and App.
- **Related styling**: `cursor_pointer()` (pointer cursor on hover), `.hover(|style| style.bg(red()))` (hover-state styling, see the ch14 counter).

## Code Examples

(styling calls omitted; the book snippet also has .text_color(white()).h_6() etc.)

```rust
div()
    .id("some_id")                       // make stateful — precondition for on_click
    .bg(red())
    .child("Click Here")
    .on_click(|event, _window, _app| {
        println!("{event:#?}");
    })
```

(styling calls omitted; the book snippet also has .text_color(white()).h_6() etc.)

```rust
div().id("some_id").child("Hover Here").on_hover(|hovered, _window, _app| {
    println!("{}", if *hovered { "Hover started" } else { "Hover ended" });
})
```

- **What it demonstrates**: the fixed `.id()` → handler order; the bool semantics of on_hover.

## Anti-patterns

- **Calling `on_click` without `.id()`**: won't compile — `StatefulInteractiveElement` exists only on stateful elements. Mental mantra: **want on_click/on_hover, id first**.
- **Changing the id across frames**: tracking of interaction state such as hover breaks.

## Key Takeaways

1. `.id()` is the precondition for interaction state, and the step most easily missed when composing components.
2. `on_click` fires on mouse release (not mousedown).
3. When you need to access the view's own state, use `cx.listener(Self::method)` (the standard pattern in the ch14 counter).

## Connects To

- **ch06**: InteractiveText's range clicks are text-level interaction; together with element-level `.id()` they belong to the same ElementId system.
- **ch11**: the action chain of keyboard interaction; `key_context` likewise belongs to InteractiveElement.
- **ch14**: the counter example = this chapter combined with the notify loop.
