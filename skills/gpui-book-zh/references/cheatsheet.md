# Cheatsheet（速查：决策规则与阈值）

用途：不查书也能按书的判断方式做决定。每行帮助"决定"，术语定义见 glossary.md。

## 选型决策

| 场景 | 决定 | 依据 |
|---|---|---|
| 有状态、存活多帧、notify 驱动 | `Render` view（Entity） | retained mode |
| 无状态、参数进元素出 | `RenderOnce` + `#[derive(IntoElement)]` | immediate mode；render(self) 接管所有权 |
| 全应用共享一份状态 | `Global`（设置/主题类） | `impl Global for T {}` 前置 |
| 多处引用/独立生命周期的状态 | `Entity<T>` | 句柄便宜 clone（延伸）；防环用 downgrade |
| 不确定 Global vs Entity | Entity | 更可控、panic 面更小（延伸） |
| render 里显示文本 | `&'static str`；动态 → SharedString 存 state | String 每帧堆分配 |
| 异步碰 UI/应用状态 | `App::spawn` / foreground_executor | AsyncApp 访问状态 |
| 纯计算/IO | background_executor | foreground 阻塞 = 应用冻结 |
| 不收结果的异步 | `.detach()` | 否则 Task drop = 立即取消 |
| 元素要盖住兄弟 | `deferred(child).with_priority(n)` | 无 z-index（延伸）；n 大者在上 |
| 跨平台修饰键 | `secondary` | macOS=platform，其余=ctrl |

## 硬性前提（漏了就出错/不编译）

- `on_click` / `on_hover` → **必须先 `.id()`**（StatefulInteractiveElement）。
- 元素级 `on_action` → **必须 `track_focus` + `focus_handle.focus(window)`**。
- 改了状态 → **必须 `cx.notify()`**，否则界面不刷新。
- 自定义组件 → **必须 `#[derive(IntoElement)]`**。
- `impl Global for T {}` → 没有它不能 set_global。
- `observe_global` 的 Subscription → **持有或 detach**（书外补充：书未明说丢弃后果）。
- 读未设置的 global（`global`/`global_mut`）→ **panic**；防御用 `try_global`/`has_global`/`default_global`。
- InteractiveText 的 ElementId → **跨帧必须相同**（书明文）；with_animation 的 ElementId → 跨帧相同（延伸）。

## 最小应用骨架（背下来）

```rust
fn main() {
    Application::new().run(|app| {
        app.open_window(WindowOptions::default(), |_window, app| {
            app.new(|_cx| RootView)          // 根 view
        })
        .unwrap();
    });
}
```

## 布局起手式

```rust
div().size_full().flex().items_center().justify_center().bg(white())
    .child(...)
```

## 键盘动作五步链

```
actions!(ns, [A]) → KeyBinding::new("enter", A, None) → app.bind_keys([...])
                  → track_focus(&fh) + fh.focus(window)   （仅元素级）
                  → .on_action(|&A, window, app| ...)
```

## 修饰符速查

`ctrl` `alt` `shift` `fn` | 平台键：`cmd`/`super`/`win` | 跨平台：`secondary`
组合写法：`ctrl-shift-f`（`-` 连接）。

## 枚举速查

- `Display`: Block / Flex / Grid / None
- `FlexDirection`: Row / Column / RowReverse / ColumnReverse
- `Position`: Relative / Absolute
- `Overflow`（Point\<Overflow\>，x/y 独立）: Visible / Clip / Hidden / Scroll
- `ObjectFit`: Fill / Contain / Cover / ScaleDown / None
- 缓动函数：linear / quadratic / ease_in_out / ease_out_quint
- 对齐枚举含两套语义：Start/End 与 FlexStart/FlexEnd 并存

## 常见症状 → 根因

- 界面不更新 → 忘了 `cx.notify()`。
- on_click 编译不过 → 缺 `.id()`。
- 按键无反应 → 忘 `bind_keys`，或元素未 track_focus+focus。
- 应用卡死 → foreground executor 里跑了阻塞操作。
- Task"没跑完就没了" → Task 被 drop；改 `.detach()` 或持有。
- hover 状态错乱 → `.id()` 跨帧变了。
- 读 global panic → 未 set；改 try_global / default_global。
