# Chapter 12: Rendering — Render 与 RenderOnce（混合渲染模型）

> 来源：The GPUI Book — rendering 两节。对应原文：`src/rendering/`。这是全书最重要的概念章（编辑性强调，书无此评价）。

## Core Idea

GPUI 是**混合渲染**框架：`Render`（retained mode）—— Entity 承载的 view，只有被 notify 才重渲染；`RenderOnce`（immediate mode）—— 构造、渲染、即弃的组件，活在 view 的 render 内部。view 里可自由嵌组件。

## Key Concepts

- **`Render`**（retained / view 层）：
  ```rust
  fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement
  ```
  让 `Entity<T>` 的 T 成为 view；不 notify 就不重渲染（ retained 的"保留"含义）。
- **`RenderOnce`**（immediate / component 层）：
  ```rust
  #[derive(IntoElement)]
  struct SomeComponent;
  impl RenderOnce for SomeComponent {
      fn render(self, window: &mut Window, cx: &mut App) -> impl IntoElement { div() }
  }
  ```
  - **接管 `self`**（by-value，对比 Render 的 `&mut self`）——适合不存自身可变状态的组件
  - 构造、渲染、随后丢弃；每次 view 重渲染（由 notify 驱动）时重建
  - 需要 `#[derive(IntoElement)]` 才能作为 child 使用

## Code Examples

```rust
impl Render for RootView {
    fn render(&mut self, _w: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        div().child(SomeComponent)   // retained view 内嵌 immediate 组件
    }
}
```

- **What it demonstrates**：两种 trait 的协作关系——view 保留状态、每次 view 重渲染（由 notify 驱动）时重建组件树。

## Mental Models

- **Use Render when**：类型有状态、要存活多帧、由 notify 驱动更新 → view（Entity）。
- **Use RenderOnce when**：无状态展示/组合单元，参数进、元素出 → component。

## Anti-patterns

- **把应用状态塞进 RenderOnce 组件**：render 接管所有权，组件没有跨帧状态的容身之处；状态属于 view（Entity）。

## Key Takeaways

1. 签名差异是考点：`&mut self + Context<Self>`（Render）vs `self + App`（RenderOnce）。
2. 自定义组件必须 `#[derive(IntoElement)]`。
3. 运行画面 = notify → view 重渲染 → 重建 RenderOnce 组件树——"retained 包 immediate"。

## Connects To

- **ch02/ch03**: Entity + notify 是 Render 的驱动源。
- **ch14**: counter 范例展示 Render view 的完整状态闭环。
