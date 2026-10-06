# Chapter 8: Styling — Text & Image (text/image style properties)

> Source: The GPUI Book — styling/text and styling/image. Corresponding original texts: `src/styling/text.md`, `src/styling/image.md`.

## Core Idea

Text styling is configured via `.text_style()` or utility functions (color, font, line height, etc., affecting child text); images are configured via the `StyledImage` trait's `.image_style()`, which besides object_fit also provides degraded rendering functions for **loading / load failure**.

## Reference Tables — text style properties (Styled trait level)

| Property | Description | Enum/Struct |
|---|---|---|
| `color` | text color | |
| `background_color` | text background color | |
| `font_family` | font family | |
| `font_features` | OpenType features | |
| `font_size` | font size | |
| `font_style` | font style | Normal / Italic / Oblique |
| `font_weight` | font weight | |
| `line_clamp` | number of lines before truncation | |
| `line_height` | line height | |
| `strikethrough` | strikethrough | StrikethroughStyle { thickness, color } |
| `text_align` | alignment | Left / Center / Right |
| `text_overflow` | whether overflow is truncated | |
| `underline` | underline | UnderlineStyle { thickness, color, wavy } |
| `white_space` | whitespace/wrapping handling | Normal / Nowrap |

## Reference Tables — image style properties (StyledImage trait, `.image_style()`)

| Property | Description |
|---|---|
| `grayscale` | whether to render in grayscale |
| `object_fit` | fit mode: Fill / Contain / Cover / ScaleDown / None |
| `loading` | optional loading function: renders a loading element while the image is loading |
| `fallback` | optional fallback function: renders a fallback element when loading fails |

## Key Takeaways

1. Text styling is an **element-level** configuration (applied to child text), a separate layer from ch06's TextRun range styling.
2. img's `loading` / `fallback` show a loading state during async loading and a fallback on failure (robustness measures given in the book).
3. The `wavy` (squiggly) underline is controlled by UnderlineStyle — a common building block for spell-check-style UIs (illustrative, not in the book).

## Connects To

- **ch06**: TextRun's per-range styling (font/color/underline — same-named fields at a different layer).
- **ch07**: the Styled trait's general styling (size/margin etc.) applies to img as well.
