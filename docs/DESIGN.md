# Freshly design system — "Refined Freshly"

Confident, modern and fast. Obsidian carries weight, mint carries energy, and
photography carries everything else. One typeface, one set of components, in
both apps and the admin console.

## Colour

| Token | Hex | Use |
|---|---|---|
| `mint` | `#00F59B` | Fills: primary button, price pill, online dot, focus on dark. **Never text on white** (1.4:1). |
| `mintDark` (Deep Jade) | `#00875A` | The brand green as *text or icon* on light: prices, links, selected labels. 4.6:1. |
| `mintSoft` / `mintInk` | `#E3FBF1` / `#00563A` | Tinted wash and the text that sits on it (8:1). |
| `obsidian` | `#0B0F19` | Hero headers, secondary (dark) button, selected nav pill, text on mint (13:1). |
| `obsidianRaised` | `#161C28` | Cards and controls on obsidian. |
| `ink` / `inkSubtle` / `inkMuted` | `#0F172A` / `#5B6675` / `#94A3B8` | Body / secondary body (5.5:1) / placeholders and text on obsidian. |
| `canvas` / `field` / `line` / `surface` | `#F6F8FB` / `#EEF2F7` / `#E6EBF1` / `#FFFFFF` | Page / input + chip fill / hairlines / cards. |
| `gold` / `goldInk` | `#FFB020` / `#B45309` | Stars and backup-power marks / the same as readable text. |
| `loadShedding` / `loadSheddingInk` / `loadSheddingSoft` | `#FF8A3D` / `#C2410C` / `#FFF3EB` | Grid alerts. |
| `crimson` / `crimsonSoft` | `#E5484D` / `#FDECEC` | SOS, destructive, errors. |

Rule of thumb: **mint is a fill, jade is a colour.** Text on a mint fill is
obsidian.

## Type

Plus Jakarta Sans (OFL), bundled in `freshly_core`, on iOS and Android alike.
Use the theme's text styles, or `FreshlyType.style(size, weight:, color:)`.
Headings are 700–800 with tightened tracking; body is 400–500.

| Style | Size / weight |
|---|---|
| displaySmall / headlineLarge | 28 / 800 — hero headlines, screen intros |
| headlineMedium | 24 / 800 |
| headlineSmall | 21 / 700 — empty-state titles |
| titleLarge | 19 / 700 — section headers, app bars |
| titleMedium | 16 / 700 — card titles |
| bodyLarge / bodyMedium | 16 / 14, line height 1.45 |
| bodySmall | 13, `inkSubtle` — meta lines |

## Shape and spacing

4-pt grid: 4, 8, 16, 24, 32, 48. Card radius 18, large radius 28 (heroes,
sheets), small radius 12. Buttons 54 high with a 16 radius. Every tappable
thing is at least 48×48.

Cards are flat: white, 1 px `line` border, no shadow. Only things that float
(sticky bars, rail cards over photos) get `FreshlyShadows`.

## Buttons

- **Primary** — `FilledButton`: mint fill, obsidian text. One per screen.
- **Secondary, confident** — `ElevatedButton`: obsidian fill, white text.
- **Secondary, quiet** — `OutlinedButton`: white with a line border.
- **Tertiary** — `TextButton`: jade text, no box.
- Nothing ripples. Presses dim.

## Components (`freshly_core/lib/src/widgets/ui_kit.dart`)

`SectionHeader`, `StatusPill` (tones: neutral, brand, success, warning,
danger, info, dark), `IconBadge`, `RatingLabel` (shows "New" when there are no
reviews, never "0.0"), `MonogramArt` and `FreshlyAvatar` (a provider without a
photo gets their initial on a deep gradient, never a grey box), `OnlineDot`,
`EmptyState`, `Skeleton` (shimmer; holds still under reduce-motion),
`StickyActionBar`, `ScreenIntro`, `GroupedList`, `LineItem`, and
`ParallaxHero` / `Parallax`.

## Patterns

- **Hero screens** (home, provider command centre, wallet) open on an obsidian
  `ParallaxHero` with the status bar turned light.
- **Form and onboarding screens**: `ScreenIntro` at the top, fields on `field`
  fill, a full-width primary button pinned at the bottom.
- **Decisions** (checkout, add-ons, accept an offer) end in a `StickyActionBar`
  that shows the money beside the button.
- **Loading** is a skeleton in the shape of the content, not a centred
  spinner. **Empty** is an `EmptyState` with the one thing to do about it.
  **Errors** say what happened and offer a retry.
- **Status** is a `StatusPill`, never coloured free text.
- **Money** is always rendered from the server's `Money`/`PriceQuote`; design
  never recomputes a total.
- Respect reduce-motion everywhere (`MediaQuery.disableAnimations`).

## Looking at screens without a phone

Each app has a screen tour that renders real screens with real fonts against a
fake API:

```bash
cd apps/mobile_client && flutter test test_screens --update-goldens
# PNGs in test_screens/out/
```
