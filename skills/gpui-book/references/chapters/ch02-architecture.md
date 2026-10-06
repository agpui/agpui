# Chapter 2: Architecture (Application / App / Window / Context)

> Source: The GPUI Book — the four architecture sections. Corresponding original text: `src/architecture/`.

## Core Idea

The startup chain of a GPUI application is fixed: `Application::new()` → `.run(callback)` → the callback receives `&mut App` → `open_window` creates a window and builds the root view. The four core object types each have their own role: Application is the entry point, App is the global state container, Window is the platform window, and Context is the Entity-specific context.

## Key Concepts

- **Application**: the entry point. Created via `Application::new()`; `run(callback)` consumes it, and the callback fires after the application finishes loading — the application's true entry point.
- **App**: holds the entire application's state; opens windows via `open_window(WindowOptions, callback)`, where the callback provides `&mut Window` and `&mut App` for building the root view. It also has:
  - `app.on_action(...)`: global action callback (App level)
  - `app.spawn(async |app| ...)`: main-thread async; the closure parameter is an `AsyncApp` (with access to application state), returns a `Task`, which can be `.detach()`ed
  - `app.bind_keys([...])`: registers key bindings (see ch11)
- **Window**: the platform window. `window.bounds()` (origin + size), `window.mouse_position()` (mouse coordinates relative to the window).
- **Context**: derefs to `App` (with all of App's capabilities), plus Entity-scoped control functions. The core is `cx.notify()`: tells GPUI that this Entity has been updated and observers should be notified; if T implements `Render`, the view will be re-rendered.

## Code Examples

```rust
// Startup skeleton (universal template for all applications)
fn main() {
    Application::new().run(|app| {
        app.open_window(WindowOptions::default(), |window, app| {
            // Build the root view
        })
        .unwrap();
    });
}
```

```rust
// State update + notify (Context usage)
let entity = app.new(|_cx| SomeState { some_value: true });
entity.update(app, |this, cx| {
    this.some_value = false;
    cx.notify(); // triggers observers / view re-render
});
```

- **What it demonstrates**: the fixed run→open_window chain; the second parameter of the update closure is `Context<T>`, and after mutating state you call `cx.notify()`.

## Anti-patterns

- **Building the root view outside the `open_window` callback**: the `&mut Window` / `&mut App` inside the callback are the construction site (inference).
- **Mutating state without `cx.notify()`**: the UI silently does not update (the most common root cause of "why didn't it refresh" in GPUI (empirical judgment, not stated in the book)).

## Key Takeaways

1. Memorize the startup skeleton: `Application::new().run(|app| app.open_window(...).unwrap())`.
2. `Context` derefs to `App` — to answer "can I use App's methods here", first check the deref chain.
3. `cx.notify()` is the only bridge from "state updated" to "UI refreshed" (empirical judgment, not stated in the book).

## Connects To

- **ch03/ch04**: Entity and Global create/read/update/remove all go through these contexts.
- **ch11**: the global role of `App::on_action` and `bind_keys`.
- **ch13**: the relationship between `App::spawn` and the executor.
