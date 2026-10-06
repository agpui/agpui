# Chapter 3: State Management — Entity

> Source: The GPUI Book — state-management/entity. Corresponding original text: `src/state-management/entity.md`.

## Core Idea

`Entity<T>` is the state carrier for pieces that need to communicate across the application; it is held by GPUI (all entities are owned inside `App`) — what you hold is a handle. It is managed through types implementing the `AppContext` trait (`App`, `Context<T>`, etc.). When T implements `Render`, the Entity is conventionally called a view.

## Key Concepts

- **Create**: `let entity = app.new(|_cx| SomeState { some_value: true })`
- **Read**: `entity.read(app)` → `&T` (immutable reference)
- **Update**: `entity.update(app, |state, cx| { ... })` — the closure receives `&mut T` and `&mut Context<T>`; to refresh the UI call `cx.notify()` inside the closure
- **Downgrade**: `entity.downgrade()` → `WeakEntity` (a weak pointer, used to prevent ownership cycles — extension; the book does not state the motivation)
- **AppContext trait**: implemented by both `App` and `Context<T>`; async scenarios have other implementors (`AsyncApp` etc.), all of which deref to `App` to access entities

## Code Examples

```rust
let entity = app.new(|_cx| SomeState { some_value: true }); // create
let some_state = entity.read(app);                          // read
entity.update(app, |some_state, _cx| {                      // write
    some_state.some_value = false;
});
let weak_entity = entity.downgrade();                       // weak reference
```

- **What it demonstrates**: the four Entity lifecycle operations: new / read / update / downgrade.

## Mental Models

- **An Entity is a handle, not a value**: cloning the handle is cheap; the real state lives inside GPUI (App); "owned by GPUI" is the key to understanding why the borrow checker does not block you.
- **The update closure = a transaction site**: state mutation and `cx.notify()` should complete within the same update closure.

## Key Takeaways

1. `app.new(...)` to create, `entity.read(app)` to read, `entity.update(app, |s, cx|)` to write.
2. view = an `Entity<T>` whose T implements `Render` (see ch12).
3. To prevent ownership cycles (extension) / for long-lived references from other structures, downgrade to `WeakEntity`.

## Connects To

- **ch02**: the semantics of `cx.notify()` and Context's deref relationship.
- **ch12**: how the Render trait turns an Entity into a view.
