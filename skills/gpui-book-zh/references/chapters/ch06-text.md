# Chapter 6: Elements — Text（文本渲染的五种类型）

> 来源：The GPUI Book — elements/text。对应原文：`src/elements/text.md`。

## Core Idea

渲染文本有 5 种类型，核心取舍是**所有权与分配成本**：`&'static str` 零成本；`String` 每次重渲染都堆分配（应少用）；`SharedString` 廉价 clone、通常存进 Entity 状态；`StyledText` / `InteractiveText` 处理局部样式与局部交互。

## Key Concepts

- **`&'static str`**：字面量直接 `.child("Hello")`，零分配。
- **`String`**：动态构建可用，但书明确 "should be used sparingly" —— 每次重渲染都堆分配。
- **`SharedString`**：不可变、可廉价 clone 的字符串；`SharedString::new_static("Hello")`。典型用法：存入 Entity 状态，render 里 `self.text.clone()` —— 避开 String 的每帧分配。
- **`StyledText`**：对文本的不同区间（`TextRun`）施加不同样式。整段同样式时不必用它。
  - `TextRun { len, font, color, background_color, underline, strikethrough }` —— `len` 是该区间长度（如 "Text" 拆成 len=2 + len=3 两个 run）
  - `.with_runs(vec![...])` 挂区间
  - 下划线/删除线样式：`UnderlineStyle { thickness, color, wavy }`、`StrikethroughStyle { thickness, color }`
- **`InteractiveText`**：让文本区间可点击/可悬停：
  `InteractiveText::new("id", StyledText::new("Text")).on_click(vec![1..3], |_range_index, _window, _app| ...)`
  - **ElementId 必须每帧相同**，否则状态跟踪失效
  - `on_click` 第一参数是可点击的字符（字节）区间列表；按下与抬起均落在同一区间内才触发，回调首参为命中区间在该列表中的下标（示例 `vec![1..3]` 即字节 1..3）。此语义为书外补充，据 gpui 源码 InteractiveText 的 clickable_ranges 实现

## Reference Tables

| 类型 | 何时用 | 成本 |
|---|---|---|
| `&'static str` | 静态字面量 | 零分配 |
| `String` | 一次性动态文本 | 每次重渲染堆分配 |
| `SharedString` | render 中显示的动态文本 | 廉价 clone，无重渲染分配 |
| `StyledText` + `TextRun` | 同段文本分区间不同样式 | |
| `InteractiveText` | 文本区间点击/悬停 | ElementId 须跨帧稳定 |

## Anti-patterns

- **在 render 中 `String::from` / `format!` 直接做 child**：每帧堆分配（书称 String 应少用）；动态文本应存 `SharedString` 进 Entity。注意：书自带的入门 hello_world.rs 用了 `format!`，属教学简化，勿当范式。

## Key Takeaways

1. 默认 `&'static str`；动态文本存 SharedString 进 Entity，render 里 clone。
2. `TextRun.len` 是区间长度，runs 按顺序拼接成整段文本。
3. `InteractiveText` 的 ElementId 必须每帧一致。

## Connects To

- **ch08**: 文本的样式属性（font/line/align…，Styled trait 层面）。
- **ch10**: 元素级交互的 `.id()` 与此处 InteractiveText 的 id 语义一致。
