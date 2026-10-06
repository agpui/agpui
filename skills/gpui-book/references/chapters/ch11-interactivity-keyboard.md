# Chapter 11: Interactivity — Keyboard (the action system)

> Source: The GPUI Book — interactivity/keyboard. Corresponding original text: `src/interactivity/keyboard.md`.

## Core Idea

Keyboard interaction goes through the five-step "action" chain: the `actions!` macro declares actions → `KeyBinding::new(keystroke, Action, context)` builds a binding → `app.bind_keys([...])` registers it → (element-level requires `track_focus` + focus) → `on_action` binds the callback. App-level `on_action` acts as the global fallback.

## Key Concepts

- **`actions!(actions_namespace, [Enter])`**: two parameters — a namespace plus a list of action names; generates a unit struct for each action.
- **KeyBinding**: `KeyBinding::new("enter", Enter, None)` — keystroke, action, key context (`None` or `Some("...")`).
- **Modifiers** (joined with `-` in a keystroke, e.g. `ctrl-shift-f`):

| Modifier | Name |
|---|---|
| Control | `ctrl` |
| Alt | `alt` |
| Shift | `shift` |
| Function | `fn` |
| Platform key | `cmd` / `super` / `win` |
| Cross-platform | `secondary` — maps to the platform key on macOS, **to control on other platforms** |

- **Key Context**: an optional `&str` context on `bind_keys` that scopes where a binding takes effect; elements declare their own context with `key_context("...")` (provided by `InteractiveElement`); on a match the action is dispatched to the relevant `on_action` callback.
- **Precondition chain for element-level `on_action`**: the element must be focusable — `track_focus(&focus_handle)` (InteractiveElement) — and that `FocusHandle` must be focused (created via `app.focus_handle()`, focused via `focus_handle.focus(window)`).
- **App level**: `app.on_action(|&Enter, _app| ...)` needs no focus and takes effect globally.

## Code Examples

```rust
actions!(actions_namespace, [Enter]);   // 1. declare the action

struct RootView { focus_handle: FocusHandle }

impl Render for RootView {
    fn render(&mut self, _w: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        div()
            .track_focus(&self.focus_handle)          // 4a. declare focus tracking
            .on_action(|&Enter, _window, _app| {      // 5. bind the callback
                println!("Enter key hit!");
            })
    }
}

fn main() {
    Application::new().run(|app| {
        app.open_window(WindowOptions::default(), |window, app| {
            app.bind_keys([gpui::KeyBinding::new("enter", Enter, None)]); // 2+3. bind + register
            let focus_handle = app.focus_handle();
            focus_handle.focus(window);               // 4b. actually focus it
            app.new(|_cx| RootView { focus_handle })
        })
        .unwrap();
    });
}
```

- **What it demonstrates**: the complete runnable form of the five-step action chain; the callback parameter destructures the unit struct with the `&Enter` pattern.

## Anti-patterns

- **An element with `on_action` but no `track_focus` + focus**: the action is never dispatched to it.
- **Forgetting `bind_keys`**: the keystroke is never bound to an action at all.
- **Hardcoding `cmd` or `ctrl` for cross-platform code**: use `secondary` instead.

## Key Takeaways

1. Five-step chain: `actions!` → `KeyBinding::new` → `bind_keys` → `track_focus`+`focus` → `on_action`.
2. Use the `secondary` modifier for cross-platform bindings (macOS = platform key, everything else = control).
3. `key_context` lets the same keystroke dispatch to different actions in different UI contexts.

## Connects To

- **ch02**: the global variant, `App::on_action`.
- **ch10**: the same family of InteractiveElement methods.
