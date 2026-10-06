# Chapter 2: Architecture（应用架构：Application / App / Window / Context）

> 来源：The GPUI Book — architecture 四节。对应原文：`src/architecture/`。

## Core Idea

GPUI 应用的启动链固定为 `Application::new()` → `.run(callback)` → 回调中拿到 `&mut App` → `open_window` 建窗并构建根 view。四类核心对象各司其职：Application 是入口，App 是全局状态容器，Window 是平台窗口，Context 是 Entity 专属上下文。

## Key Concepts

- **Application**：入口。`Application::new()` 创建；`run(callback)` 消费它，回调在应用加载完成后触发，是应用真正的入口点。
- **App**：持有整个应用的状态；通过 `open_window(WindowOptions, callback)` 开窗，回调提供 `&mut Window` 与 `&mut App`，用于构建根 view。还有：
  - `app.on_action(...)`：全局动作回调（App 级）
  - `app.spawn(async |app| ...)`：主线程异步，闭包参数为 `AsyncApp`（可访问应用状态），返回 `Task`，可 `.detach()`
  - `app.bind_keys([...])`：注册按键绑定（见 ch11）
- **Window**：平台窗口。`window.bounds()`（原点+尺寸）、`window.mouse_position()`（相对窗口的鼠标坐标）。
- **Context**：deref 到 `App`（拥有 App 的全部能力），另有归属 Entity 的控制功能。核心是 `cx.notify()`：告知 GPUI 该 Entity 已更新、observer 应被通知；若 T 实现 `Render`，view 将被重新渲染。

## Code Examples

```rust
// 启动骨架（全应用通用模板）
fn main() {
    Application::new().run(|app| {
        app.open_window(WindowOptions::default(), |window, app| {
            // 构建根 view
        })
        .unwrap();
    });
}
```

```rust
// 状态更新 + notify（Context 用法）
let entity = app.new(|_cx| SomeState { some_value: true });
entity.update(app, |this, cx| {
    this.some_value = false;
    cx.notify(); // 触发 observers / view 重渲染
});
```

- **What it demonstrates**：run→open_window 的固定链条；update 闭包第二参数就是 `Context<T>`，改完状态调 `cx.notify()`。

## Anti-patterns

- **在 `open_window` 回调之外构建根 view**：回调里的 `&mut Window` / `&mut App` 是构建现场（引申）。
- **改了状态不 `cx.notify()`**：界面静默不更新（GPUI 最常见的"为什么没刷新"根因（经验判断，书未明说））。

## Key Takeaways

1. 记住启动骨架：`Application::new().run(|app| app.open_window(...).unwrap())`。
2. `Context` deref 到 `App`——"能不能用 App 的方法"先看 deref 链。
3. `cx.notify()` 是"状态更新 → 界面刷新"的唯一桥梁（经验判断，书未明说）。

## Connects To

- **ch03/ch04**: Entity 与 Global 的增删改查都经由这些上下文。
- **ch11**: `App::on_action` 与 `bind_keys` 的全局角色。
- **ch13**: `App::spawn` 与执行器的关系。
