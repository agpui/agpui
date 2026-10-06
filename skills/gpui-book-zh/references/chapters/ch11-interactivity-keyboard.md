# Chapter 11: Interactivity — Keyboard（动作系统）

> 来源：The GPUI Book — interactivity/keyboard。对应原文：`src/interactivity/keyboard.md`。

## Core Idea

键盘交互走"动作"体系五步链：`actions!` 宏声明动作 → `KeyBinding::new(keystroke, Action, context)` 建绑定 → `app.bind_keys([...])` 注册 → （元素级需 `track_focus` + 聚焦）→ `on_action` 绑定回调。App 级 `on_action` 则全局兜底。

## Key Concepts

- **`actions!(actions_namespace, [Enter])`**：两参数——命名空间 + 动作名列表；为每组动作生成 unit struct。
- **KeyBinding**：`KeyBinding::new("enter", Enter, None)` —— keystroke、动作、key context（`None` 或 `Some("...")`）。
- **修饰符**（用 `-` 连接 keystroke，如 `ctrl-shift-f`）：

| 修饰符 | 名称 |
|---|---|
| Control | `ctrl` |
| Alt | `alt` |
| Shift | `shift` |
| Function | `fn` |
| 平台键 | `cmd` / `super` / `win` |
| 跨平台 | `secondary` —— macOS 映射 platform 键，**其它平台映射 control** |

- **Key Context**：`bind_keys` 的可选 `&str` 上下文，限定绑定生效范围；元素用 `key_context("...")`（`InteractiveElement` 提供）声明自身上下文；匹配时 action 分发给相关 `on_action` 回调。
- **元素级 `on_action` 的前提链**：元素必须可聚焦——`track_focus(&focus_handle)`（InteractiveElement），且该 `FocusHandle` 已被聚焦（`app.focus_handle()` 创建、`focus_handle.focus(window)` 聚焦）。
- **App 级**：`app.on_action(|&Enter, _app| ...)` 不需要焦点，全局生效。

## Code Examples

```rust
actions!(actions_namespace, [Enter]);   // 1. 声明动作

struct RootView { focus_handle: FocusHandle }

impl Render for RootView {
    fn render(&mut self, _w: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        div()
            .track_focus(&self.focus_handle)          // 4a. 声明焦点跟踪
            .on_action(|&Enter, _window, _app| {      // 5. 绑定回调
                println!("Enter key hit!");
            })
    }
}

fn main() {
    Application::new().run(|app| {
        app.open_window(WindowOptions::default(), |window, app| {
            app.bind_keys([gpui::KeyBinding::new("enter", Enter, None)]); // 2+3. 绑定+注册
            let focus_handle = app.focus_handle();
            focus_handle.focus(window);               // 4b. 实际聚焦
            app.new(|_cx| RootView { focus_handle })
        })
        .unwrap();
    });
}
```

- **What it demonstrates**：动作系统五步链的完整可运行形态；回调参数按 `&Enter` 模式解构 unit struct。

## Anti-patterns

- **元素挂了 `on_action` 却没 `track_focus` + 聚焦**：action 永远不会派发到它。
- **忘了 `bind_keys`**：按键根本没有绑定到动作。
- **跨平台硬编码 `cmd` 或 `ctrl`**：应使用 `secondary`。

## Key Takeaways

1. 五步链：`actions!` → `KeyBinding::new` → `bind_keys` → `track_focus`+`focus` → `on_action`。
2. 跨平台修饰符用 `secondary`（macOS=platform 键，其余=control）。
3. `key_context` 让同一 keystroke 在不同 UI 上下文分发给不同动作。

## Connects To

- **ch02**: `App::on_action` 的全局变体。
- **ch10**: 同属 InteractiveElement 的方法族。
