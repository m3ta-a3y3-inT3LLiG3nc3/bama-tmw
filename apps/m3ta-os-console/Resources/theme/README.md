# BAMA theme pack: TMW Cosmic Lightbody v1 (DRAFT)
**Status:** palette direction confirmed by Kingdom on 2026-10-27, with the exact hexes delegated to GrokBot Design. The logo (B v3 Hybrid M) is **staged and pending Kingdom approval**.
**Who applies it:** K0Ad33 applies this to `~/bama-tmw` on the Mac. This pack does **not** touch the repo.

## Files
| File | Use |
|---|---|
| `tokens.json` | Source of truth (copy of `/workspace/brand-system/th3m3taway/tokens.json`) |
| `tokens.css` | Raw `--tmw-*` tokens plus semantic light (`:root`) and dark (`.dark` / `[data-theme=dark]`) variables |
| `shadcn-globals.css` | shadcn/ui HSL variables: background, foreground, card, popover, primary, secondary, muted, accent, destructive, border, input, ring, chart-1..5, radius |
| `tailwind.theme.js` | `theme.extend` (shadcn color mapping, `tmw.*` raw colors, Inter, nebula gradient) |
| `icons/` | iOS set (1024 → 20, opaque full-bleed), macOS set (1024 → 16 plus `AppIcon.icns`), web (favicon.ico, 16/32/48/192/512, maskable 192/512) and SVG sources |

## Apply (K0Ad33)
1. **Branch:** create one, e.g. `theme/tmw-cosmic-lightbody`.
2. **CSS variables:**
   - **If the app uses shadcn:** replace the `:root` / `.dark` blocks in `globals.css` with `shadcn-globals.css`.
   - **Otherwise:** import `tokens.css`.
3. **Tailwind:** merge `tailwind.theme.js` into `tailwind.config.*`. If the app uses Tailwind v4 CSS-first config, map the same variables in `@theme`.
4. **Dark mode:** make dark the default by putting `class="dark"` on `<html>`. Light mode = Lightbody Day.
5. **Font:** load Inter (OFL), e.g. with `next/font/google` or self-hosted.
6. **Icons:**
   - iOS: put `ios-*.png` in `Assets.xcassets/AppIcon.appiconset`.
   - macOS: use `AppIcon.icns` / `macos-*.png`.
   - Web: copy `web-*.png` and `favicon.ico` to `public/`, with the maskable icons in the manifest (`purpose: "maskable"`).
7. **Check:** run the app in both modes and check text contrast. The token pairs are all ≥4.5:1, as listed in `tokens.json` → `modes_semantic.contrast`.

## Rules
- Never use `cosmic-red-deep` or `violet-deep` as text on onyx. They are fills only.
- Never put red text on violet, or violet on red (1.33:1).
- The nebula gradient is for hero/glow only, at most one per screen.
- One primary action per screen. `primary` = cosmic red.
- `ring` / `link` = violet-glow. `destructive` = alert ember (#FF9F6B dark, #A3261C light), kept distinct from brand red.

## Approval gate
Kingdom has to approve the logo before release builds or store uploads.
