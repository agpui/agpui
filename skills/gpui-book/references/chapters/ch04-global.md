# Chapter 4: State Management — Global (application-wide shared state)

> Source: The GPUI Book — state-management/global. Corresponding original text: `src/state-management/global.md`. This is the most API-dense section of the book.

## Core Idea

For state that must be shared application-wide, use `Global`: first make the type implement the `Global` marker trait, then set/get. The typical example is application settings. Like Entity, globals are held by GPUI; reading an unset global panics.

## Key Concepts (full API table)

| Operation | API | Notes |
|---|---|---|
| Mark the type | `impl Global for SomeState {}` | zero-cost marker, precedes any set |
| Set | `app.set_global::<T>(value)` or `T::set_global(app, value)` | requires `UpdateGlobal` |
| Read | `app.global::<T>()` or `T::global(app)` | requires `ReadGlobal`; **panics** if unset |
| Mutable read | `app.global_mut::<T>()` | **panics** if unset |
| Try read | `app.try_global::<T>()` → `Option<&T>` | defensive (returns an Option of a reference; the book text stresses reference semantics) |
| Is set | `app.has_global::<T>()` → `bool` | defensive |
| Default fallback | `app.default_global::<T>()` | if unset, initializes via the `Default` impl and then yields a mutable reference |
| Update | `app.update_global::<T, _>(\|state, app\| ...)` or `T::update_global(app, ...)` | |
| Remove | `app.remove_global::<T>()` | |
| Observe updates | `app.observe_global::<T>(\|_app\| { ... })` | returns a `Subscription`: either hold it or `.detach()` it |

## Code Examples

```rust
pub struct SomeState { some_value: bool }
impl Global for SomeState {}

app.set_global::<SomeState>(SomeState { some_value: true });
let some_state = SomeState::global(app);            // read (panic risk)
app.update_global::<SomeState, _>(|some_state, _app| {   // mutate in place
    some_state.some_value = false;
});
app.observe_global::<SomeState>(|_app| { /* callback */ }).detach();
```

- **What it demonstrates**: the idiomatic forms of the full Global read/write set; the convenience methods `T::global` / `T::set_global` / `T::update_global` come from the `ReadGlobal` / `UpdateGlobal` traits respectively. Two additional compile-time constraints: `app.update_global` requires the `BorrowAppContext` trait in scope; `default_global` requires the type to implement `Default` (`#[derive(Default)]`) — missing the import or the derive means compilation fails.

## Anti-patterns

- **`global()` / `global_mut()` on an unset global → panic**: when unsure whether it is set, use `try_global` / `has_global` / `default_global`.
- **Neither holding nor detaching the `Subscription` returned by `observe_global`**: the subscription immediately becomes invalid (beyond-book supplement: the book shows only the hold-or-detach usages and does not state the consequence).

## Key Takeaways

1. `impl Global for T {}` is a precondition; without it you cannot set.
2. The panic vs Option boundary: `global`/`global_mut` assume it is set; `try_global`/`has_global` are for defense.
3. The Subscription returned by an observer must be handled explicitly (hold it or detach).

## Connects To

- **ch03**: Entity vs Global selection (see the cheatsheet decision table).
- **ch13**: the Subscription pattern is isomorphic to the Task detach pattern.
