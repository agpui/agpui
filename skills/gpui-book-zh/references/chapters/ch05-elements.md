# Chapter 5: Elements — Div / Img / Deferred（基础元素）

> 来源：The GPUI Book — elements 章（Div、Img、Deferred）。对应原文：`src/elements/`。Text 单独成章见 ch06。

## Core Idea

GPUI 的基础元素覆盖容器（div）、图片（img）与绘制顺序控制（deferred）；div 是最常用元素，作为容器通过样式（ch07/08）与交互（ch10/11）组合成任意组件。自定义元素仅在基础元素不够用时才需要（Implementing Element 章书源仅有导言、无展开内容）。

## Key Concepts

- **Div**：`div()` 创建；`ParentElement` trait 提供：
  - `.child(子元素)` —— 加单个子元素
  - `.children([a, b])` —— 批量加子元素
- **Img**：`img(...)` 接受 `Into<ImageSource>`；常用文件路径写法：
  `img(Path::new(env!("CARGO_MANIFEST_DIR")).join("image.png"))`
- **Deferred**：GPUI 遵循 **Painter's algorithm**（后画者覆盖先画者，无显式 z-index）。`deferred(child)` 延迟其 child 的 layout 与 paint，从而改变叠放次序；`.with_priority(n)` 控制相对顺序，**priority 大者绘制在上**。

## Code Examples

```rust
div().child(div())                       // 单子元素
div().children([div(), div()])           // 多子元素
div().child(deferred(div()))             // 延迟绘制
div().child(deferred(div()).with_priority(10)) // 控制叠放优先级
div().size_full().child(
    img(Path::new(env!("CARGO_MANIFEST_DIR")).join("image.png")).size_full()
)                                        // 图片（编译期清单目录）
```

- **What it demonstrates**：容器的两种 child 用法、deferred 的优先级语义、img 的路径构建惯用式。

## Mental Models

- **顺序即层级**：GPUI 没有 z-index（引申）；想盖住别人，就用 deferred 推迟绘制。
- **div 是万能底座**：布局/背景/交互都挂在 div 上，再往里放内容。

## Key Takeaways

1. `.child()` / `.children([...])` 是组合 UI 的基本手段（ParentElement）。
2. `deferred` + `with_priority` 是书中给出的控制叠放次序的机制（Painter's algorithm）。
3. img 用 `CARGO_MANIFEST_DIR` 拼工程内资源路径是书的示例惯用式。

## Connects To

- **ch06**: div 里放文本的五种类型。
- **ch07/ch08**: div 的样式与 img 的样式（StyledImage）。
- **ch10**: div 挂上 `.id()` + `on_click` 变成按钮。
