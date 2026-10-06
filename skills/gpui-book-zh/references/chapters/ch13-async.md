# Chapter 13: Async（前台/后台执行器）

> 来源：The GPUI Book — async 两节。对应原文：`src/async/`。

## Core Idea

GPUI 提供两个执行器：**foreground** 在主线程跑（绝不能跑会阻塞的非平凡操作，否则整个应用冻结）；**background** 在后台线程跑。`spawn` 返回 `Task<T>`，**drop 即取消**，`.detach()` 放手让它跑完。

## Key Concepts

- **获取**：`app.foreground_executor()` / `app.background_executor()`（均需 `AppContext`）。
- **spawn**：两者均为 `.spawn(future) -> Task<T>`；Task 被 drop 时任务**立即取消**；`.detach()` 让任务跑完。
- **`App::spawn`** 简写：`app.spawn(async |app| { ... }).detach()` —— 主线程任务且闭包参数给 `AsyncApp`（异步侧访问应用状态）。
- **timer**：`app.background_executor().timer(Duration) -> Task<()>` —— 定时器，可在 future 里 `timer.await`。

## Code Examples

（代码出自 architecture/snippets/spawn.rs）

```rust
// 主线程异步（可访问 AsyncApp）
app.spawn(async |app| { /* 异步工作 */ }).detach();

// 后台线程异步
app.background_executor()
    .spawn(async { /* 纯计算/IO */ })
    .detach();

// 定时器
let timer = app.background_executor().timer(Duration::from_secs(10));
app.background_executor().spawn(async {
    timer.await;
    println!("Timer Finished!");
}).detach();
```

- **What it demonstrates**：两个执行器的 spawn 形态、detach 语义、timer 的 await 用法。

## Decision Rules

- 要更新 UI / 访问应用状态 → 主线程（`App::spawn` 或 foreground_executor）。
- 纯计算 / IO → background_executor。
- 不关心结果 → `.detach()`；要结果 → 持有 Task 并 await。
- 需要延时/轮询 → background timer + await。

## Anti-patterns

- **foreground 里跑阻塞操作**（文件 IO、长计算）→ 主线程阻塞 → 整个应用冻结。书原文："vital to not run operations that may block for any non-trivial duration"。
- **Task 落地即析构**：drop = 立即取消；要么 detach，要么存起来。

## Key Takeaways

1. Task 的 drop = 取消——把 Task 存起来或 detach，别让它顺手析构。
2. timer 是后台线程的定时原语，await 它做延时/轮询。
3. `AsyncApp` 是异步侧访问应用状态的窗口（书类型总表还列有 `AsyncWindowContext`、`TestAppContext`，正文未展开）。

## Connects To

- **ch02**: `App::spawn` 的完整语境。
- **ch04**: `observe_global` 返回的 Subscription 与 Task 同属"必须显式处理"的句柄（书未明说 Subscription 丢弃的后果）。
