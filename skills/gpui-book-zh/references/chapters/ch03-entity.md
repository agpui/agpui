# Chapter 3: State Management — Entity

> 来源：The GPUI Book — state-management/entity。对应原文：`src/state-management/entity.md`。

## Core Idea

`Entity<T>` 是需要跨应用各部分通信的状态载体；它由 GPUI 持有（所有 entity 都 owned inside `App`），你拿到的是句柄。经实现 `AppContext` trait 的类型（`App`、`Context<T>` 等）管理。T 实现 `Render` 时，该 Entity 惯称 view。

## Key Concepts

- **创建**：`let entity = app.new(|_cx| SomeState { some_value: true })`
- **读取**：`entity.read(app)` → `&T`（不可变引用）
- **更新**：`entity.update(app, |state, cx| { ... })` —— 闭包拿到 `&mut T` 与 `&mut Context<T>`；要界面刷新就在闭包里 `cx.notify()`
- **降级**：`entity.downgrade()` → `WeakEntity`（弱指针，用于防持有环——延伸，书未说明动机）
- **AppContext trait**：`App` 与 `Context<T>` 都实现它；异步场景还有其它实现（`AsyncApp` 等），它们都 deref 到 `App` 来访问 entities

## Code Examples

```rust
let entity = app.new(|_cx| SomeState { some_value: true }); // 创建
let some_state = entity.read(app);                          // 读
entity.update(app, |some_state, _cx| {                      // 写
    some_state.some_value = false;
});
let weak_entity = entity.downgrade();                       // 弱引用
```

- **What it demonstrates**：Entity 生命周期四件套：new / read / update / downgrade。

## Mental Models

- **Entity 是句柄，不是值**：clone handle 便宜，真状态活在 GPUI（App）里；"owned by GPUI" 是理解借用检查不拦你的关键。
- **update 闭包 = 事务现场**：状态修改与 `cx.notify()` 应在同一个 update 闭包内完成。

## Key Takeaways

1. `app.new(...)` 创建、`entity.read(app)` 读、`entity.update(app, |s, cx|)` 写。
2. view = T 实现了 `Render` 的 `Entity<T>`（见 ch12）。
3. 需要防循环持有（延伸）/在其它结构中长期引用时，downgrade 成 `WeakEntity`。

## Connects To

- **ch02**: `cx.notify()` 的语义与 Context 的 deref 关系。
- **ch12**: Render trait 如何把 Entity 变成 view。
