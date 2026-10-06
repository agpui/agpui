# Chapter 6: Elements — Text (five types of text rendering)

> Source: The GPUI Book — elements/text. Corresponding original text: `src/elements/text.md`.

## Core Idea

There are 5 types for rendering text; the core trade-off is **ownership and allocation cost**: `&'static str` is zero-cost; `String` heap-allocates on every re-render (should be used sparingly); `SharedString` clones cheaply and is usually stored in Entity state; `StyledText` / `InteractiveText` handle partial styling and partial interactivity.

## Key Concepts

- **`&'static str`**: a literal goes straight into `.child("Hello")`, zero allocation.
- **`String`**: usable for dynamic construction, but the book explicitly says "should be used sparingly" — it heap-allocates on every re-render.
- **`SharedString`**: an immutable string that clones cheaply; `SharedString::new_static("Hello")`. Typical usage: store it in Entity state and do `self.text.clone()` in render — avoiding String's per-frame allocation.
- **`StyledText`**: applies different styles to different ranges (`TextRun`) of the text. Unnecessary when the whole text shares one style.
  - `TextRun { len, font, color, background_color, underline, strikethrough }` — `len` is the length of that range (e.g. "Text" splits into two runs of len=2 + len=3)
  - `.with_runs(vec![...])` attaches the ranges
  - Underline/strikethrough styles: `UnderlineStyle { thickness, color, wavy }`, `StrikethroughStyle { thickness, color }`
- **`InteractiveText`**: makes text ranges clickable/hoverable:
  `InteractiveText::new("id", StyledText::new("Text")).on_click(vec![1..3], |_range_index, _window, _app| ...)`
  - **The ElementId must be identical every frame**, otherwise state tracking breaks
  - The first parameter of `on_click` is the list of clickable character (byte) ranges; it fires only when both press and release land within the same range, and the callback's first parameter is the index of the hit range in that list (in the example, `vec![1..3]` means bytes 1..3). This semantics is a beyond-book supplement, based on the `clickable_ranges` implementation of InteractiveText in the gpui source code.

## Reference Tables

| Type | When to use | Cost |
|---|---|---|
| `&'static str` | static literals | zero allocation |
| `String` | one-off dynamic text | heap allocation on every re-render |
| `SharedString` | dynamic text displayed in render | cheap clone, no re-render allocation |
| `StyledText` + `TextRun` | different styles per range within the same text | |
| `InteractiveText` | clicking/hovering text ranges | ElementId must be stable across frames |

## Anti-patterns

- **Using `String::from` / `format!` directly as a child in render**: heap allocation every frame (the book says String should be used sparingly); dynamic text should be stored as `SharedString` in an Entity. Note: the book's own starter hello_world.rs uses `format!` — that is a teaching simplification, not a pattern to imitate.

## Key Takeaways

1. Default to `&'static str`; store dynamic text as SharedString in an Entity and clone in render.
2. `TextRun.len` is the range length; runs concatenate in order to form the full text.
3. The ElementId of `InteractiveText` must be identical every frame.

## Connects To

- **ch08**: text styling properties (font/line/align…, at the Styled trait level).
- **ch10**: element-level interaction's `.id()` matches the id semantics of InteractiveText here.
