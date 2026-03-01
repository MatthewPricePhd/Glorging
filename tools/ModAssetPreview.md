# Mod Asset Preview Tool

Standalone UI preview for `Data\ModAssets` files without running `Lemmix.exe`.

The preview tool now includes baseline export orchestration:

- detects game install folders
- ensures baseline assets exist for all five built-in styles (`Orig`, `Ohno`, `H94`, `X91`, `X92`)
- runs `ModAssetBaselineExport.exe` automatically when baseline data is missing
- defaults override editing to a game-loadable pack folder:
  - `Data\ModAssets\Packs\Glorging`
- includes quick actions:
  - `Open Active Pack Folder`
  - `Launch Game`

Editor side-car integration:

- new `Editor` tab for LibreSprite workflow
- clone/update LibreSprite source from inside the UI
- open source folder for direct modification
- launch LibreSprite and open the currently selected asset directly
- includes built-in `Integrated Edit (No Install)` for direct strip editing without external tools
  - runs inline inside the `Editor` tab (no popup window)
  - use `Editor > Basic` for normal workflow
  - LibreSprite controls moved to `Editor > Advanced`
  - launcher now starts PowerShell with `-STA` for stable WinForms/OLE behavior

## Current Progress (Mar 1, 2026)

Preview tab:

- left file list pane widened by default for better filename readability
- removed `Strip Diff` and `Frame Diff` columns
- remaining preview boxes:
  - `Reference Strip`
  - `Override Strip`
  - `Reference Frame`
  - `Override Frame`

Basic editor:

- kept non-Windows-dialog mapping workflow in the integrated panel
- added fixed left tool panel (resizable but enforced minimum width)
- added `Default Palette (Strip Analysis)` from all frames in selected strip
- added `Custom Mapping` swatches (1:1 with default palette positions)
- added recolor mapping workflow:
  - click default palette swatch to choose source and active draw color
  - optionally choose target via draw color picker
  - click matching custom mapping slot to assign target color
  - `Apply Map to Strip` is enabled only when all mapping slots are filled
  - apply works across all frames in the strip
  - iterative re-apply is supported (change mapped colors and apply again)
- improved first-load layout and readability:
  - light tool-panel background
  - readable toolbar/button styling
  - enforced splitter sizing after first layout pass

Debug/test support:

- detailed interaction logging is currently enabled in `%TEMP%\ModAssetPreview.log`
- helper launcher script:
  - `tools\Launch-ModAssetPreview.ps1` (supports `-FreshLog`)
- helper interaction test harness:
  - `tools\Run-PaletteInteractionTest.ps1`

## Run

From repo root:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\ModAssetPreview.ps1
```

Or build and run launcher EXE:

- project: `src/ModAssetPreviewLauncher.dproj`
- exe: `ModAssetPreviewLauncher.exe`

LibreSprite source location (default):

- `third_party\LibreSprite`

Optional:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\ModAssetPreview.ps1 `
  -GameRoot "C:\Games\Glorging" `
  -PackName "MyPack"
```

Optional roots:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\ModAssetPreview.ps1 `
  -OverrideRoot "C:\path\to\MyPack\ModAssets" `
  -ReferenceRoot "C:\path\to\Baseline\ModAssets"
```

If `ReferenceRoot` is omitted, the tool tracks style selection and uses:

- `<GameRoot>\Data\ModAssets\Baseline\<Style>`

## What it previews

- UI backgrounds (`menu_background.png`, `loading_background.png`)
- Lemming strips (`anim_00.png` ... `anim_27.png`)
- Mask strips (`mask_00.png` ... `mask_05.png`)

## Preview usage

- Set `Override Root` to your test assets.
- Set `Reference Root` to a baseline asset export (or leave auto-style reference enabled).
- The preview shows side-by-side reference/override strip and frame views.

You can generate a reference export with:

- `src/ModAssetBaselineExport.dpr` (see `tools/ModAssetBaselineExport.md`)

## Notes

- The app validates dimensions against `MOD_ASSET_PIPELINE.md`.
- If `Reference Root` is empty, it still works for single-pack preview.
