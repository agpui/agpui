# Chapter 8: Styling — Text & Image（文本/图片样式属性）

> 来源：The GPUI Book — styling/text 与 styling/image。对应原文：`src/styling/text.md`、`src/styling/image.md`。

## Core Idea

文本样式经 `.text_style()` 或工具函数配置（颜色、字体、行高等，影响子文本）；图片经 `StyledImage` trait 的 `.image_style()` 配置，除 object_fit 外还提供**加载中 / 加载失败**的降级渲染函数。

## Reference Tables — 文本样式属性（Styled trait 层面）

| 属性 | 说明 | 枚举/结构 |
|---|---|---|
| `color` | 文本颜色 | |
| `background_color` | 文本背景色 | |
| `font_family` | 字体族 | |
| `font_features` | OpenType 特性 | |
| `font_size` | 字号 | |
| `font_style` | 字形 | Normal / Italic / Oblique |
| `font_weight` | 字重 | |
| `line_clamp` | 截断前行数 | |
| `line_height` | 行高 | |
| `strikethrough` | 删除线 | StrikethroughStyle { thickness, color } |
| `text_align` | 对齐 | Left / Center / Right |
| `text_overflow` | 溢出是否截断 | |
| `underline` | 下划线 | UnderlineStyle { thickness, color, wavy } |
| `white_space` | 换行空白处理 | Normal / Nowrap |

## Reference Tables — 图片样式属性（StyledImage trait，`.image_style()`）

| 属性 | 说明 |
|---|---|
| `grayscale` | 是否灰度渲染 |
| `object_fit` | 适配方式：Fill / Contain / Cover / ScaleDown / None |
| `loading` | 可选加载函数：图片加载期间渲染 loading 元素 |
| `fallback` | 可选降级函数：加载失败时渲染 fallback 元素 |

## Key Takeaways

1. 文本样式是**元素级**配置（作用于子文本），与 ch06 的 TextRun 区间样式是两个层次。
2. img 的 `loading` / `fallback` 用于异步加载时显示加载态、失败时显示回退（书中给出的健壮性手段）。
3. `wavy` 下划线（波浪线）由 UnderlineStyle 控制——拼写检查类 UI 的常用件（示意，书无此例）。

## Connects To

- **ch06**: TextRun 的 per-range 样式（font/color/underline 字段同名不同层）。
- **ch07**: Styled trait 的通用样式（size/margin 等）同样适用于 img。
