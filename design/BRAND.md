# Kumi Brand

## Mark

`design/kumi-logo.svg` — the kumiko-lattice diamond: a 3×3 assembly rotated 45°,
center piece left open. Eight pieces joined without nails — Ash resources
assembled into a product. Flat single-colour Kumi Indigo, legible from 16px
(favicon) upward. Concept sheet it came from: `design/kumi-logo-concepts.png`
(adopted: top-left).

A kanji-based mark (組 in a seal frame) was drawn and rejected — the character
rebuilt from uniform bars did not read as clean at the sizes that matter.

## Color

| Token | Value | Use |
|---|---|---|
| Kumi Indigo (藍) | `#4338CA` | mark, primary accent, buttons, links |
| Indigo hover | `#3730A3` | hover states |
| Ink | `#101828` | headings, sidebar bg |
| Slate | `#667085` | muted text |
| Paper | `#F6F7F9` | page background |
| Surface | `#FFFFFF` | cards, topbar |
| Border | `#E4E7EC` | hairlines |
| Danger | `#B42318` | destructive actions |

Aizome (Japanese indigo dye) is the brand anchor — deep indigo on paper white.

## Wordmark

Lowercase `kumi`, geometric sans (UI: system-ui stack, weight 600, tight
tracking), Ink color. Mark sits left of the wordmark at cap height, gap ≈ 0.4×
mark width.

## Default product chrome ("everything you build looks Kumi by default")

Generated apps and kumi_admin ship Kumi-branded by default — login card carries
the mark, admin footer says "Powered by Kumi" with the mini mark, top page uses
the token palette. All of it is host-owned code / CSS custom properties, so
users can rebrand freely; Kumi is the default face, never a lock-in.
