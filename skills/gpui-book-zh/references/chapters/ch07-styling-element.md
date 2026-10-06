# Chapter 7: Styling — Element（Taffy 布局与样式 API）

> 来源：The GPUI Book — styling/index 与 styling/element。对应原文：`src/styling/`。

## Core Idea

GPUI 用 **Taffy** 作底层布局引擎。样式有两条等价路径：CSS 风格链式工具函数（`.flex().flex_col()...`，本质是底层 `Style` 结构体修改的简写）或直接修改 `Style` 结构体。任何实现 `Styled` trait 的元素都有 `.style()` 入口。也可自建简写函数。

## Key Concepts

- **两路径对比**（等价结果）：
  - 工具函数：`div().flex().flex_col().child("Hello").child("World")`
  - Style 结构体：`let mut element = div().child("Hello").child("World"); let style = element.style(); style.display = Some(Display::Flex); style.flex_direction = Some(FlexDirection::Column);`
- **Display**：`Block` / `Flex` / `Grid` / `None`
- **FlexDirection**：`Row` / `Column` / `RowReverse` / `ColumnReverse`
- **Position**：`Relative` / `Absolute`
- **对齐三件套**（枚举值）：
  - `align_content`（内容对齐）：Start/End/FlexStart/FlexEnd/Center/Stretch/SpaceBetween/SpaceEvenly/SpaceAround
  - `align_items`（子元素对齐）：取值为 Start / End / FlexStart / FlexEnd / Center / Baseline / Stretch（与 align_content 不同，不含 SpaceBetween/SpaceEvenly/SpaceAround）
  - `align_self`（自身对齐）：同 align_items
  - `justify_content`（主轴空间分配）：同 align_content
- **弹性**：`flex_basis`（初始尺寸）/ `flex_grow`（填充速率）/ `flex_shrink`（收缩速率）/ `flex_wrap`（NoWrap/Wrap/WrapReverse）/ `gap`
- **盒模型**：`margin` / `padding` / `inset` / `size` / `max_size` / `min_size` / `aspect_ratio` / `corner_radii` / `border_color` / `box_shadow` / `background`
- **其它**：
  - `opacity`：0 完全透明 ~ 1 完全不透明
  - `overflow`：**`Point<T>` 包装，x/y 各自独立**；值域 Visible/Clip/Hidden/Scroll
  - `visibility`：Visible / Hidden（控制是否绘制）
  - `mouse_cursor`：悬停时的光标样式
  - `text`：子文本样式；`.text_style()` 拿可变引用（详见 ch08）

## Anti-patterns

- **以为 overflow 是单一值**：它是 per-axis 的 `Point<Overflow>`，x/y 可分别设置。
- **混用 Start/End 与 FlexStart/FlexEnd 时忽视语义差异**：两套并存是 CSS 兼容语义，注意对齐基准（引申，书未论述二者语义差异）。

## Key Takeaways

1. 工具函数与 Style 结构体等价，选顺手的；自定义简写函数也被书认可。
2. 布局心智 = flexbox（Taffy）：主轴/交叉轴/弹性三参一套搬过来。
3. `overflow` 是 x/y 独立的 Point<Overflow>。

## Connects To

- **ch05**: div 挂样式成为组件外壳。
- **ch08**: 文本与图片的专属样式。
- **ch09**: 动画通过 delta 驱动样式属性变化。
