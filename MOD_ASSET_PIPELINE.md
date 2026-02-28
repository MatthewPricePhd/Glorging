# Mod Asset Pipeline

This document defines exactly what to provide for cosmetic overrides (no gameplay logic changes).

## 1) Where files go

All overrides are loaded from disk next to the executable:

- `Data\\ModAssets\\UI\\menu_background.png`
- `Data\\ModAssets\\UI\\loading_background.png`
- `Data\\ModAssets\\Lemmings\\anim_00.png` ... `anim_27.png`
- `Data\\ModAssets\\Lemmings\\mask_00.png` ... `mask_05.png`

If a file is not present, the built-in graphics are used.

Note on style variants:

- The override path is global (`Data\\ModAssets` or selected pack), so one override set is applied across all styles.
- The five built-in styles in F4 (`Orig`, `Ohno`, `H94`, `X91`, `X92`) can still have visual differences (palette/background), so validate each style.
- Use the baseline exporter with `--all-styles` to generate per-style references for diff/testing.

## 2) UI Background Specs

### Menu background

- File: `Data\\ModAssets\\UI\\menu_background.png`
- Required size: `640x350`
- Format: PNG (RGBA supported)
- Behavior: Replaces the tiled brown menu background only. Buttons/logo/text still render on top using normal game logic.

### Loading background

- File: `Data\\ModAssets\\UI\\loading_background.png`
- Recommended size: `640x350` (other sizes are stretched to window)
- Format: PNG
- Behavior: Drawn behind the loading status text.

## 3) Lemming Animation Override Specs

Each `anim_XX.png` is one vertical strip:

- Width = single frame width
- Height = `frame_count * frame_height`
- Frame order: top to bottom (frame 0 at top)

| File | Animation | Frames | Frame Size | Strip Size |
|---|---:|---:|---:|---:|
| `anim_00.png` | Walking | 8 | 16x10 | 16x80 |
| `anim_01.png` | Jumping | 1 | 16x10 | 16x10 |
| `anim_02.png` | Walking RTL | 8 | 16x10 | 16x80 |
| `anim_03.png` | Jumping RTL | 1 | 16x10 | 16x10 |
| `anim_04.png` | Digging | 16 | 16x14 | 16x224 |
| `anim_05.png` | Climbing | 8 | 16x12 | 16x96 |
| `anim_06.png` | Climbing RTL | 8 | 16x12 | 16x96 |
| `anim_07.png` | Drowning | 16 | 16x10 | 16x160 |
| `anim_08.png` | Hoisting | 8 | 16x12 | 16x96 |
| `anim_09.png` | Hoisting RTL | 8 | 16x12 | 16x96 |
| `anim_10.png` | Building | 16 | 16x13 | 16x208 |
| `anim_11.png` | Building RTL | 16 | 16x13 | 16x208 |
| `anim_12.png` | Bashing | 32 | 16x10 | 16x320 |
| `anim_13.png` | Bashing RTL | 32 | 16x10 | 16x320 |
| `anim_14.png` | Mining | 24 | 16x13 | 16x312 |
| `anim_15.png` | Mining RTL | 24 | 16x13 | 16x312 |
| `anim_16.png` | Falling | 4 | 16x10 | 16x40 |
| `anim_17.png` | Falling RTL | 4 | 16x10 | 16x40 |
| `anim_18.png` | Umbrella | 8 | 16x16 | 16x128 |
| `anim_19.png` | Umbrella RTL | 8 | 16x16 | 16x128 |
| `anim_20.png` | Splatting | 16 | 16x10 | 16x160 |
| `anim_21.png` | Exiting | 8 | 16x13 | 16x104 |
| `anim_22.png` | Vaporizing | 14 | 16x14 | 16x196 |
| `anim_23.png` | Blocking | 16 | 16x10 | 16x160 |
| `anim_24.png` | Shrugging | 8 | 16x10 | 16x80 |
| `anim_25.png` | Shrugging RTL | 8 | 16x10 | 16x80 |
| `anim_26.png` | Oh-No-ing | 16 | 16x10 | 16x160 |
| `anim_27.png` | Exploding | 1 | 32x32 | 32x32 |

## 4) Mask Override Specs

Masks use the same strip rule (vertical stacked frames):

| File | Mask Strip | Frames | Frame Size | Strip Size |
|---|---:|---:|---:|---:|
| `mask_00.png` | Bash masks | 4 | 16x10 | 16x40 |
| `mask_01.png` | Bash masks RTL | 4 | 16x10 | 16x40 |
| `mask_02.png` | Mine masks | 2 | 16x13 | 16x26 |
| `mask_03.png` | Mine masks RTL | 2 | 16x13 | 16x26 |
| `mask_04.png` | Explosion mask | 1 | 16x22 | 16x22 |
| `mask_05.png` | Countdown digits | 5 | 8x8 | 8x40 |

## 5) Art Delivery Rules (for you or for handoff to me)

Preferred direct-delivery format (fastest):

- Final PNG strips exactly matching dimensions above.
- One file per strip (`anim_XX.png` / `mask_XX.png`).
- RGBA with clean transparency.

If you want me to convert source art for you, provide:

- A layered file (PSD/Krita/ASE) OR sprite sheet PNG per animation.
- Frame order and intended animation name (e.g., "Walking RTL").
- Frame box size and count if not already split.

I can convert those into compliant `anim_XX.png` / `mask_XX.png` files.

## 6) Recommended workflow

1. Start with UI backgrounds (`menu_background.png`, `loading_background.png`).
2. Replace one lemming strip at a time (e.g., `anim_00.png`).
3. Launch game and visually verify before replacing next strip.
4. Commit in small batches so regressions are easy to isolate.

## 7) Current code hooks

- Menu background override in `src/GameScreen.Menu.pas`
- Loading background override in `src/Form.Main.pas`
- Lemming/mask strip overrides in `src/Styles.Base.pas`
