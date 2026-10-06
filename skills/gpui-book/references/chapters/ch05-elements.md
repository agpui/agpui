# Chapter 5: Elements — Div / Img / Deferred (basic elements)

> Source: The GPUI Book — elements chapter (Div, Img, Deferred). Corresponding original text: `src/elements/`. Text gets its own chapter, see ch06.

## Core Idea

GPUI's basic elements cover containers (div), images (img), and paint-order control (deferred); div is the most-used element, serving as the container that composes arbitrary components via styling (ch07/08) and interactivity (ch10/11). Custom elements are only needed when the basic elements are insufficient (the Implementing Element chapter in the book source has only an introduction, no expanded content).

## Key Concepts

- **Div**: created via `div()`; the `ParentElement` trait provides:
  - `.child(child)` — add a single child element
  - `.children([a, b])` — add child elements in bulk
- **Img**: `img(...)` accepts `Into<ImageSource>`; the common file-path form:
  `img(Path::new(env!("CARGO_MANIFEST_DIR")).join("image.png"))`
- **Deferred**: GPUI follows the **Painter's algorithm** (later painters cover earlier ones, no explicit z-index). `deferred(child)` defers its child's layout and paint, thereby changing the stacking order; `.with_priority(n)` controls the relative order — **higher priority paints on top**.

## Code Examples

```rust
div().child(div())                       // single child
div().children([div(), div()])           // multiple children
div().child(deferred(div()))             // deferred painting
div().child(deferred(div()).with_priority(10)) // control stacking priority
div().size_full().child(
    img(Path::new(env!("CARGO_MANIFEST_DIR")).join("image.png")).size_full()
)                                        // image (compile-time manifest directory)
```

- **What it demonstrates**: the container's two child usages, deferred's priority semantics, and the idiomatic path construction for img.

## Mental Models

- **Order is layering**: GPUI has no z-index (inference); to cover something else, defer its painting with deferred.
- **div is the universal base**: layout/background/interactivity all hang off div, then put content inside.

## Key Takeaways

1. `.child()` / `.children([...])` are the basic means of composing UI (ParentElement).
2. `deferred` + `with_priority` are the mechanism the book gives for controlling stacking order (Painter's algorithm).
3. Building in-project asset paths for img with `CARGO_MANIFEST_DIR` is the book's idiomatic example form.

## Connects To

- **ch06**: the five types for putting text in a div.
- **ch07/ch08**: div styling and img styling (StyledImage).
- **ch10**: div with `.id()` + `on_click` becomes a button.
