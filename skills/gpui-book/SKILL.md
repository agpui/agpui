---
name: gpui-book
description: "Knowledge base: The GPUI Book (by matinaniss; GPUI is the Rust GPU-accelerated UI framework powering the Zed editor). Use when developing desktop applications in the GPUI / Zed ecosystem: application startup chain (Application/App/Window/Context), Entity and Global state management, Div/Text/Img/Deferred elements, Taffy styling and layout, animations, mouse and keyboard actions/focus, Render and RenderOnce hybrid rendering, foreground/background async executors, with copy-pasteable minimal example code. Covers the GPUI framework itself; for component library usage and design guidelines, see the gpui-kit and gpui-kit-design-guides skills respectively."
---

<!-- argument-hint: [topic, framework name, or chapter number, e.g. "Entity", "global", "ch11"] -->

# The GPUI Book

**Author**: matinaniss | **Form**: mdBook (39 sections + 52 code snippets) | **Chapters**: 14 (this skill) | **Generated**: 2026-10-02 | **Proofread**: 2026-10-06 (verified section-by-section against the source book; errors fixed, beyond-book inferences tagged as "extension")
**Source**: [github.com/matinaniss/gpui-book](https://github.com/matinaniss/gpui-book) (cloned to `ref-projs/gpui-book`)

## How to Use This Skill

- **No arguments** — load the core mental models below as reference
- **With a topic** — ask for terms like `Entity`, `global`, `keybinding`, `deferred`; check the Topic Index first, then read the corresponding chapter file before answering
- **With a chapter** — ask for `ch11`; load that chapter directly
- **Browse** — ask "which chapters are there?" to see the Chapter Index

Before answering questions not covered by Core Frameworks, read the relevant chapter file first.

---

## Core Frameworks & Mental Models

**1. Hybrid rendering model (the book's first concept)**
Use `Render` when state must survive multiple frames and updates are driven by notify (view = `Entity<T>`, T: Render). Use `RenderOnce` when the component is stateless, arguments in elements out (`render(self, ...)` takes ownership, requires `#[derive(IntoElement)]`). Runtime picture: notify → view re-renders → RenderOnce component tree rebuilt every frame — retained wraps immediate.

**2. GPUI owns everything; you only get handles**
Entities and Globals are all owned inside `App`; you hold `Entity<T>` handles (cloning is cheap). Types implementing `AppContext` (`App`, `Context<T>`, `AsyncApp`, ...) all deref to `App` — for "can I call App's methods here?" first check the deref chain.

**3. The notify contract**
After mutating state you must call `cx.notify()` (Context\<T\>), otherwise the UI silently fails to refresh — the root cause of GPUI's most common "why didn't it update" problem (empirical judgment, not stated in the book). The update closure = the transaction site: mutation and notify complete within the same closure.

**4. The startup chain is fixed**
`Application::new().run(|app| { app.open_window(WindowOptions::default(), |window, app| { app.new(|_cx| RootView) }).unwrap(); })` — the main of every GPUI application is this template.

**5. Stateful interaction needs an id first**
`on_click` / `on_hover` need element state across frames → must first call `.id("stable_id")` (StatefulInteractiveElement); the id must not change across frames. `on_click` fires on release. To call view methods use `cx.listener(Self::method)`.

**6. Keyboard = the five-step action chain**
`actions!(ns, [A])` → `KeyBinding::new("keystroke", A, ctx)` → `app.bind_keys([...])` → element-level `track_focus(&fh)` + `fh.focus(window)` → `on_action`. For cross-platform modifiers use `secondary` (macOS = platform key, elsewhere = control). App-level `on_action` is the focus-free global fallback.

**7. Styling = Taffy flexbox with two paths**
CSS-style chained helper methods (`.flex().flex_col()...`) and mutating the `Style` struct directly are equivalent (the `Styled` trait's `.style()`). overflow is a `Point<Overflow>` with independent x/y.

**8. Zero text allocation**
Text in render: static text uses `&'static str`; dynamic text is stored as `SharedString` in the Entity and cloned in render. `String` heap-allocates every frame — the book explicitly recommends using it sparingly.

**9. Dual async executors**
Touching UI/app state → main thread (`App::spawn`/foreground); pure computation/IO → background. `Task<T>` **cancels on drop**; if you don't consume the result, call `.detach()`. A blocked foreground executor = the whole app freezes.

**10. Order is layering**
GPUI has no explicit z-index (extension), following the Painter's algorithm (later-painted is on top). To paint over something else: `deferred(child).with_priority(n)`, larger n on top.

**11. Handles must be handled explicitly**
The `Subscription` from `observe_global` and async `Task`s: either hold them or `.detach()`, otherwise the subscription goes dead / the task is cancelled. Reading an unset global (`global()`/`global_mut()`) will **panic** — defend with `try_global` / `has_global` / `default_global`.

---

## Chapter Index

| # | Title | Key Content |
|---|------|----------|
| [ch01](references/chapters/ch01-getting-started.md) | Getting Started | dependency setup, create-gpui-app, manual project creation |
| [ch02](references/chapters/ch02-architecture.md) | Architecture | Application/App/Window/Context, notify |
| [ch03](references/chapters/ch03-entity.md) | State — Entity | new/read/update/downgrade |
| [ch04](references/chapters/ch04-global.md) | State — Global | full API table, panic defense, observe_global |
| [ch05](references/chapters/ch05-elements.md) | Elements | Div/child/children, Img, Deferred+priority |
| [ch06](references/chapters/ch06-text.md) | Text | 5 text types, SharedString, StyledText/InteractiveText |
| [ch07](references/chapters/ch07-styling-element.md) | Styling — Element | Taffy, two paths, full flexbox property table |
| [ch08](references/chapters/ch08-styling-text-image.md) | Styling — Text & Image | text/image style properties, object_fit, loading/fallback |
| [ch09](references/chapters/ch09-animations.md) | Animations | Animation, with_animation, easing |
| [ch10](references/chapters/ch10-interactivity-mouse.md) | Interactivity — Mouse | .id(), on_click/on_hover, cx.listener |
| [ch11](references/chapters/ch11-interactivity-keyboard.md) | Interactivity — Keyboard | five-step action chain, modifiers, key_context, focus |
| [ch12](references/chapters/ch12-rendering.md) | Rendering | Render vs RenderOnce, hybrid model |
| [ch13](references/chapters/ch13-async.md) | Async | foreground/background executors, Task/detach, timer |
| [ch14](references/chapters/ch14-examples.md) | Examples | Hello World, complete Counter end-to-end code |

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

- [glossary.md](references/glossary.md) — all terms and definitions (including entries not expanded in the book's type overview table)
- [patterns.md](references/patterns.md) — 9 technique patterns (When/How/Trade-offs)
- [cheatsheet.md](references/cheatsheet.md) — decision tables, hard prerequisites checklist, minimal skeleton, symptom → root cause

---

## Scope & Limits

This skill covers only the content of The GPUI Book. **Parts of the book not yet written at the time it was fetched** (empty or intro-only placeholders in the source repo): the Svg / Anchored / List / Uniform List / Canvas elements, Implementing Element (Request Layout / Prepaint / Paint), Testing, and the body text of the type overview table entries — this skill marks them honestly and does not invent content; when these topics are needed, consult the `gpui-kit` skill or the Zed repository source code. GPUI keeps evolving with Zed; the book is based on the API (git mainline) as of the time it was written and may diverge from the latest version. For component library usage and design guidelines, see the `gpui-kit` and `gpui-kit-design-guides` skills. The source images (2 example screenshots) were not read.
