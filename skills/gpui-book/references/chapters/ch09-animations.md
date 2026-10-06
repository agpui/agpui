# Chapter 9: Animations

> Source: The GPUI Book — the two animations sections. Corresponding original text: `src/animations/`.

## Core Idea

`Animation` describes "duration + easing + whether to repeat" and is attached via `with_animation` (provided by the `AnimationExt` trait) to any type convertible into an element; the closure receives a **delta from 0.0 → 1.0** and uses it to drive style changes. Animation state is driven by GPUI — you only write the pure "delta → style" mapping.

## Key Concepts

- **Construction**: `Animation::new(Duration)`; `.repeat()` repeats infinitely; `.with_easing(f: impl Fn(f32) -> f32)` for custom easing (the closure receives the delta and returns the modified delta).
- **Built-in easing functions (such as)**: `linear`, `quadratic`, `ease_in_out`, `ease_out_quint`.
- **Attachment**: `with_animation(id, animation, |this, delta| this.style(...))`
  - Three parameters: `ElementId`, `Animation`, `impl Fn(Self, f32) -> Self`
  - Returns `AnimationElement<Self>` (Self being any type convertible into an element)
  - delta goes from 0.0 up to 1.0; whether it loops depends on the Animation configuration

## Code Examples

```rust
use gpui::{Animation, AnimationExt, ease_in_out, rems, ...};

div().bg(blue()).with_animation(
    "animation",                                        // ElementId
    Animation::new(Duration::from_secs(1))
        .repeat()                                       // infinite loop
        .with_easing(ease_in_out),                      // easing
    |this, delta| this.size(rems(delta * 5.)),          // delta → style
)
```

- **What it demonstrates**: the blue square smoothly grows from 0 to 5 rems as delta increases, with looped replay (repeat resets delta back to 0.0 each round, walking from 0.0 to 1.0 again — the block jumps back and grows again); ease_in_out makes each round accelerate first and then decelerate — this is the only complete animation example in the book.

## Mental Models

- **Animation = pure function**: `f(element, delta) → element`; no hand-written timers, no animation state machines.

## Key Takeaways

1. Common recipe: `Animation::new(dur).repeat().with_easing(ease_in_out)`.
2. The id in `with_animation` is an ElementId — same semantics as the interactive element `.id()`.
3. To change the "motion curve", swap the easing function; to change the "tempo", swap Duration / repeat.

## Connects To

- **ch07**: what the closure modifies are exactly the Styled style attributes.
- **ch10**: the cross-frame stability requirement for ElementId shares the same origin.
