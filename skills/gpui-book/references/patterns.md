# Patterns

Format: **When to use** → **How** → **Trade-offs**. All drawn from The GPUI Book main text or its example code.

## notify closed loop (state → UI)
**When**: after any entity state mutation.
**How**: `entity.update(app, |state, cx| { state.x = ...; cx.notify(); })` — mutation and notify in the same closure; re-renders automatically when T: Render.
**Trade-offs**: forgetting notify = UI silently does not update (the most common bug); notifying too often = redundant rendering, granularity is per Entity (extension).

## cx.listener method handler
**When**: on_click and similar callbacks need to read/write the view's own state.
**How**: `.on_click(cx.listener(Self::increment))`; method signature `fn increment(&mut self, event: &ClickEvent, window: &mut Window, cx: &mut Context<Self>)`, mutate state inside the method + `cx.notify()`.
**Trade-offs**: one-line logic uses an inline closure; multi-line or reused logic uses a method + listener (extension).

## stateful interaction in three steps
**When**: cross-frame interactive state such as on_click / on_hover is needed.
**How**: `.id("stable_id")` → attach handlers → the id stays the same across frames.
**Trade-offs**: a changing id = lost interactive state; stateless handlers (such as certain events) do not need an id.

## zero-allocation text rendering
**When**: producing text inside render.
**How**: static → `&'static str`; dynamic → store text as `SharedString` in Entity state, clone it in render via `self.text.clone()`; String/format! is acceptable only for one-off text.
**Trade-offs**: String is simple and direct but heap-allocates every frame; SharedString costs one extra state field.

## z-order control (deferred)
**When**: an element needs to cover an earlier-painted sibling (tooltip, rudimentary overlay).
**How**: `deferred(child)` defers painting; `deferred(child).with_priority(n)` controls relative order, higher n paints on top.
**Trade-offs**: GPUI has no explicit z-index (extension); order is layering; deferred defers layout and paint.

## executor selection
**When**: any async work.
**How**: touches UI / app state → `App::spawn` / foreground_executor; pure computation/IO → background_executor; result not needed → `.detach()`; timers → background `timer(Duration)` + await.
**Trade-offs**: blocking the foreground = the whole app freezes; background results must be spawned again to the foreground to return to the main thread (extension).

## five-step action chain
**When**: keyboard commands / bindable commands.
**How**: `actions!(ns, [A])` → `KeyBinding::new("keystroke", A, ctx)` → `app.bind_keys([...])` → for element level, additionally `track_focus(&fh)` + `fh.focus(window)` → `on_action` callback.
**Trade-offs**: use `secondary` for cross-platform; when the same keystroke has multiple bindings, scope them with key_context (extension); App-level on_action is a focus-free global fallback.

## global settings store
**When**: a single piece of state shared app-wide (settings, theme, etc.).
**How**: `impl Global for T {}` → `set_global` → read/mutate via `global`/`global_mut` → subscribe to changes with `observe_global`.
**Trade-offs**: reading before it is set → panic; defensive paths: `try_global` / `has_global` / `default_global` (Default fallback).

## weak references against cycles
**When**: Entities hold each other, or an Entity is stored for the long term.
**How**: `entity.downgrade()` → `WeakEntity`; upgrade when needed.
**Trade-offs**: upgrading must handle the already-released case (extension); with strong references, lifetimes are managed uniformly by GPUI.

## focus-driven element-level actions
**When**: the same action should be answered by "whoever has focus", rather than triggered globally.
**How**: the view holds a `FocusHandle` (created via `app.focus_handle()`) → `.track_focus(&self.focus_handle)` in render → `focus_handle.focus(window)` at build time → attach `on_action` to the element.
**Trade-offs**: focus management is on you (who focuses, and when); global actions carry none of this cost.
