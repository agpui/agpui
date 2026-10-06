# Chapter 13: Async (foreground/background executors)

> Source: The GPUI Book — the two async sections. Corresponding original text: `src/async/`.

## Core Idea

GPUI provides two executors: **foreground** runs on the main thread (never run non-trivial operations that may block there, or the whole application freezes); **background** runs on background threads. `spawn` returns a `Task<T>`; **dropping it cancels the task**, and `.detach()` lets it run to completion.

## Key Concepts

- **Obtaining**: `app.foreground_executor()` / `app.background_executor()` (both require `AppContext`).
- **spawn**: both are `.spawn(future) -> Task<T>`; when the Task is dropped the task is **cancelled immediately**; `.detach()` lets the task run to completion.
- **`App::spawn`** shorthand: `app.spawn(async |app| { ... }).detach()` — a main-thread task whose closure parameter is an `AsyncApp` (access to application state from the async side).
- **timer**: `app.background_executor().timer(Duration) -> Task<()>` — a timer; inside a future you can `timer.await`.

## Code Examples

(code from architecture/snippets/spawn.rs)

```rust
// main-thread async (has access to AsyncApp)
app.spawn(async |app| { /* async work */ }).detach();

// background-thread async
app.background_executor()
    .spawn(async { /* pure computation / IO */ })
    .detach();

// timer
let timer = app.background_executor().timer(Duration::from_secs(10));
app.background_executor().spawn(async {
    timer.await;
    println!("Timer Finished!");
}).detach();
```

- **What it demonstrates**: the spawn forms of the two executors, the detach semantics, and the await usage of timer.

## Decision Rules

- Need to update the UI / access application state → main thread (`App::spawn` or foreground_executor).
- Pure computation / IO → background_executor.
- Don't care about the result → `.detach()`; need the result → hold the Task and await it.
- Need delay/polling → background timer + await.

## Anti-patterns

- **Running blocking operations on the foreground executor** (file IO, long computations) → the main thread blocks → the whole application freezes. Book quote: "vital to not run operations that may block for any non-trivial duration".
- **Letting the Task be dropped on the spot**: drop = immediate cancellation; either detach it or store it.

## Key Takeaways

1. Dropping a Task = cancellation — store the Task or detach it; don't let it get dropped incidentally.
2. timer is the background-thread timing primitive; await it for delays/polling.
3. `AsyncApp` is the window into application state from the async side (the book's type overview table also lists `AsyncWindowContext` and `TestAppContext`, not elaborated in the body text).

## Connects To

- **ch02**: the full context of `App::spawn`.
- **ch04**: the Subscription returned by `observe_global` and the Task both belong to the class of handles that "must be handled explicitly" (the book does not state the consequence of dropping the Subscription).
