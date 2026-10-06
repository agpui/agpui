# Chapter 4: State Management — Global（全应用共享状态）

> 来源：The GPUI Book — state-management/global。对应原文：`src/state-management/global.md`。这是全书 API 最密集的一节。

## Core Idea

需要全应用共享的状态用 `Global`：先让类型实现 `Global` marker trait，再 set/get。典型例子是应用设置（settings）。与 Entity 一样由 GPUI 持有；读取未设置的 global 会 panic。

## Key Concepts（API 全表）

| 操作 | API | 备注 |
|---|---|---|
| 标记类型 | `impl Global for SomeState {}` | 零成本 marker，先于一切 set |
| 设置 | `app.set_global::<T>(value)` 或 `T::set_global(app, value)` | 需 `UpdateGlobal` |
| 读取 | `app.global::<T>()` 或 `T::global(app)` | 需 `ReadGlobal`；未设置 **panic** |
| 可变读取 | `app.global_mut::<T>()` | 未设置 **panic** |
| 尝试读取 | `app.try_global::<T>()` → `Option<&T>` | 防御式（返回引用的 Option，书原文强调 reference 语义） |
| 是否已设置 | `app.has_global::<T>()` → `bool` | 防御式 |
| 默认回退 | `app.default_global::<T>()` | 未设置时按 `Default` 实现初始化再给可变引用 |
| 更新 | `app.update_global::<T, _>(\|state, app\| ...)` 或 `T::update_global(app, ...)` | |
| 移除 | `app.remove_global::<T>()` | |
| 观察更新 | `app.observe_global::<T>(\|_app\| { ... })` | 返回 `Subscription`：要么持有，要么 `.detach()` |

## Code Examples

```rust
pub struct SomeState { some_value: bool }
impl Global for SomeState {}

app.set_global::<SomeState>(SomeState { some_value: true });
let some_state = SomeState::global(app);            // 读（panic 风险）
app.update_global::<SomeState, _>(|some_state, _app| {   // 原地改
    some_state.some_value = false;
});
app.observe_global::<SomeState>(|_app| { /* 回调 */ }).detach();
```

- **What it demonstrates**：Global 全套读写的惯用形态；便捷方法 `T::global` / `T::set_global` / `T::update_global` 分别来自 `ReadGlobal` / `UpdateGlobal` trait。另有两个编译期约束：`app.update_global` 需 `BorrowAppContext` trait 在作用域内；`default_global` 要求类型实现 `Default`（`#[derive(Default)]`）——漏 import/漏 derive 即编译失败。

## Anti-patterns

- **`global()` / `global_mut()` 读未设置的 global → panic**：不确定是否已设置时用 `try_global` / `has_global` / `default_global`。
- **`observe_global` 返回的 `Subscription` 既不持有也不 detach**：订阅立即失效（书外补充：书仅展示持有或 detach 两种用法，未明说后果）。

## Key Takeaways

1. `impl Global for T {}` 是前置条件，没有它 set 不了。
2. panic vs Option 的分界：`global`/`global_mut` 假定已设置；`try_global`/`has_global` 用于防御。
3. 观察者返回的 Subscription 必须显式处理（持有或 detach）。

## Connects To

- **ch03**: Entity vs Global 的选型（见 cheatsheet 决策表）。
- **ch13**: Subscription 模式与 Task detach 模式同构。
