# Lemmix Community Modding Guide

This project is a Delphi VCL Windows game. The fastest path is:

1. Build and run the base game on Windows.
2. Add community content as **user styles** on disk.
3. Avoid changing bundled original assets unless you explicitly need a full rebuild.

## 1) Windows Build Setup

1. Install Delphi 10.3+ (Community Edition is fine).
2. Open `src/Lemmix.dproj`.
3. Build `Win32` (Release recommended first).
4. Run the produced `Lemmix.exe` from the `src` folder.

Notes:
- This repo includes `src/bass.dll`, used for audio.
- If you edit `.rc` resource inputs, rebuild resources with `src/Data/BuildResources.bat` before compiling.

## 2) Resource Rebuild Script

`src/Data/BuildResources.bat` compiles `.rc` files into `.RES`.

- It now skips missing optional files instead of hard-failing.
- Main style resources currently present in this repo:
  - `Styles/Orig/orig.rc`
  - `Styles/Ohno/ohno.rc`
  - `Styles/H94/h94.rc`
  - `Styles/X91/x91.rc`
  - `Styles/X92/x92.rc`

Music `.rc` files are optional and may be absent in this checkout.

## 3) Preferred Community Mod Workflow

Use disk-based **user styles** (no exe patching required for core gameplay changes).

The game discovers custom style folders under:
- default: `Data/Styles/`
- or a custom folder via in-game Config screen (`Path to Styles`)

Create a folder like:

```text
Data/
  Styles/
    MyCommunityPack/
      Style.config
      ground0o.dat
      vgagr0.dat
      ...
      level0001.lvl (or *lev*.dat files)
      Music/
        track01.mod (optional)
        track02.mp3 (optional)
```

### Required/expected DOS-style files

For `family=DOS` with `graphics=DEFAULT`, the loader expects:
- Ground metadata files matching `ground*o.dat`
- Graphic files matching `vgagr*.dat`
- Matching numeric indices in both sets

Levels can be either:
- DAT sets matching `*lev*.dat`, or
- Raw `.LVL` files (must match expected LVL size)

### `Style.config` keys

Supported keys:
- `description=...`
- `author=...`
- `info=...`
- `family=DOS` or `family=LEMMINI`
- `graphics=DEFAULT|ORIG|OHNO|CONCAT`
- `specialgraphics=DEFAULT|ORIG`
- `mechanics=OHNO|ORIG`
- `maindat=OHNO|ORIG`

Minimal example:

```ini
description=My Community Pack
author=Your Name
info=Modern art pass + custom levels
family=DOS
graphics=DEFAULT
specialgraphics=DEFAULT
mechanics=OHNO
maindat=ORIG
```

## 4) Repository Strategy for Community Mods

Recommended structure:

1. Keep this code repo focused on engine/source.
2. Keep mod assets in a separate repo (or subfolder with clear licensing).
3. Document exactly which files are original, replaced, or newly created.

For public releases, prefer fully original/replacement art and audio to reduce legal risk around historic bundled data.

## 5) Quick Contributor Checklist

1. Pull repo on Windows.
2. Build and run once.
3. Copy/create a user style in `Data/Styles/<PackName>`.
4. Set style path in config if using external folder.
5. Launch, select your style, verify levels/audio/art.
