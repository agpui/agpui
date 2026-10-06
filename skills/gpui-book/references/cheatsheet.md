# Cheatsheet (decision rules and thresholds)

Purpose: make decisions the way the book does, without opening the book. Each line helps you "decide"; term definitions are in glossary.md.

## decision table

| Scenario | Decision | Basis |
|---|---|---|
| stateful, lives across frames, notify-driven | `Render` view (Entity) | retained mode |
| stateless, parameters in / element out | `RenderOnce` + `#[derive(IntoElement)]` | immediate mode; render(self) takes ownership |
| one piece of state shared app-wide | `Global` (settings/theme class) | `impl Global for T {}` required first |
| state referenced from multiple places / with an independent lifetime | `Entity<T>` | the handle clones cheaply (extension); use downgrade to prevent cycles |
| unsure between Global vs Entity | Entity | more controllable, smaller panic surface (extension) |
| displaying text in render | `&'static str`; dynamic → SharedString in state | String heap-allocates every frame |
| async work touching UI/app state | `App::spawn` / foreground_executor | AsyncApp accesses state |
| pure computation/IO | background_executor | blocking the foreground = app freezes |
| async whose result is not needed | `.detach()` | otherwise Task drop = immediate cancellation |
| an element must cover a sibling | `deferred(child).with_priority(n)` | no z-index (extension); higher n on top |
| cross-platform modifier key | `secondary` | macOS=platform, others=ctrl |

## hard prerequisites (missing one = wrong behavior / compile error)

- `on_click` / `on_hover` → **must `.id()` first** (StatefulInteractiveElement).
- element-level `on_action` → **must `track_focus` + `focus_handle.focus(window)`**.
- mutated state → **must `cx.notify()`**, or the UI never refreshes.
- custom component → **must `#[derive(IntoElement)]`**.
- `impl Global for T {}` → without it, set_global is not possible.
- the Subscription from `observe_global` → **hold it or `.detach()`** (beyond-book supplement: the book does not state the consequence of dropping it).
- reading an unset global (`global`/`global_mut`) → **panic**; defend with `try_global`/`has_global`/`default_global`.
- the ElementId of InteractiveText → **must be identical across frames** (explicit in the book); the ElementId of with_animation → identical across frames (extension).

## minimal skeleton (memorize it)

```rust
fn main() {
    Application::new().run(|app| {
        app.open_window(WindowOptions::default(), |_window, app| {
            app.new(|_cx| RootView)          // root view
        })
        .unwrap();
    });
}
```

## layout starter

```rust
div().size_full().flex().items_center().justify_center().bg(white())
    .child(...)
```

## keyboard action five-step chain

```
actions!(ns, [A]) → KeyBinding::new("enter", A, None) → app.bind_keys([...])
                  → track_focus(&fh) + fh.focus(window)   (element level only)
                  → .on_action(|&A, window, app| ...)
```

## modifier quick reference

`ctrl` `alt` `shift` `fn` | platform keys: `cmd`/`super`/`win` | cross-platform: `secondary`
Combinations: `ctrl-shift-f` (joined with `-`).

## enum quick reference

- `Display`: Block / Flex / Grid / None
- `FlexDirection`: Row / Column / RowReverse / ColumnReverse
- `Position`: Relative / Absolute
- `Overflow` (Point\<Overflow\>, x/y independent): Visible / Clip / Hidden / Scroll
- `ObjectFit`: Fill / Contain / Cover / ScaleDown / None
- easing functions: linear / quadratic / ease_in_out / ease_out_quint
- the alignment enums carry two sets of semantics: Start/End coexist with FlexStart/FlexEnd

## common symptoms → root cause

- UI does not update → forgot `cx.notify()`.
- on_click fails to compile → missing `.id()`.
- keystroke has no effect → forgot `bind_keys`, or the element lacks track_focus+focus.
- app freezes → a blocking operation ran in the foreground executor.
- the Task "disappears before finishing" → the Task was dropped; switch to `.detach()` or hold it.
- hover state misbehaves → the `.id()` changed across frames.
- reading a global panics → not set; switch to try_global / default_global.
