# Chapter 9: Animations（动画）

> 来源：The GPUI Book — animations 两节。对应原文：`src/animations/`。

## Core Idea

`Animation` 描述"时长 + 缓动 + 是否重复"，通过 `with_animation`（`AnimationExt` trait 提供）挂到任意可转元素类型；闭包收到 **0.0 → 1.0 的 delta**，用它驱动样式变化。动画状态由 GPUI 驱动，你只写"delta → 样式"的纯映射。

## Key Concepts

- **构造**：`Animation::new(Duration)`；`.repeat()` 无限重复；`.with_easing(f: impl Fn(f32) -> f32)` 自定义缓动（闭包接收 delta、返回修改后的 delta）。
- **内置缓动函数（如）**：`linear`、`quadratic`、`ease_in_out`、`ease_out_quint`。
- **挂载**：`with_animation(id, animation, |this, delta| this.样式(...))`
  - 三参数：`ElementId`、`Animation`、`impl Fn(Self, f32) -> Self`
  - 返回 `AnimationElement<Self>`（Self 为任意可转元素类型）
  - delta 从 0.0 起到 1.0；是否循环取决于 Animation 配置

## Code Examples

```rust
use gpui::{Animation, AnimationExt, ease_in_out, rems, ...};

div().bg(blue()).with_animation(
    "animation",                                        // ElementId
    Animation::new(Duration::from_secs(1))
        .repeat()                                       // 无限循环
        .with_easing(ease_in_out),                      // 缓动
    |this, delta| this.size(rems(delta * 5.)),          // delta → 样式
)
```

- **What it demonstrates**：蓝色方块随 delta 从 0 平滑放大到 5 rems，循环重放（repeat 每轮把 delta 重置回 0.0 从头走向 1.0，放大后跳回再放大），ease_in_out 使每轮先加速后减速——这是全书唯一的动画完整范例。

## Mental Models

- **动画 = 纯函数**：`f(元素, delta) → 元素`；没有手写计时器、没有动画状态机。

## Key Takeaways

1. 常用配方：`Animation::new(dur).repeat().with_easing(ease_in_out)`。
2. `with_animation` 的 id 是 ElementId——语义与交互元素 `.id()` 一致。
3. 想改"运动曲线"，换 easing 函数；想改"节奏"，换 Duration / repeat。

## Connects To

- **ch07**: 闭包里改的正是 Styled 样式属性。
- **ch10**: ElementId 的跨帧稳定要求同源。
