# Baseline Asset Export Tool

Exports built-in baseline assets to a `ModAssets`-compatible folder for visual diff.

Output includes:
- `UI\menu_background.png` (reconstructed from built-in MAIN.DAT brown background)
- `UI\loading_background.png` (black baseline; built-in loader has no dedicated image file)
- `Lemmings\anim_00.png` ... `anim_27.png`
- `Lemmings\mask_00.png` ... `mask_05.png`

## Build

Open and build this Delphi console project:

- `src/ModAssetBaselineExport.dpr`

## Run

From the built executable folder:

```powershell
.\ModAssetBaselineExport.exe
```

Double-click behavior:

- If launched with no arguments (double-click), it opens an interactive console prompt:
- choose which detected game install to work on
- choose single style vs all styles
- optional output folder override (default: `<Game>\Data\ModAssets\Baseline`)
- it pauses before exit so errors are visible

Explicit game selection:

```powershell
.\ModAssetBaselineExport.exe --game C:\Games\Glorging --style Orig
```

Optional:

```powershell
.\ModAssetBaselineExport.exe --style Orig --out C:\Temp\BaselineModAssets
```

Export all built-in game variants in one run:

```powershell
.\ModAssetBaselineExport.exe --all-styles --out C:\Temp\BaselineAllStyles
```

This creates:

- `BaselineAllStyles\Orig\...`
- `BaselineAllStyles\Ohno\...`
- `BaselineAllStyles\H94\...`
- `BaselineAllStyles\X91\...`
- `BaselineAllStyles\X92\...`

The exporter forces mod overrides off during export, so output is always from built-in assets.

## Use with preview

Set `Reference Root` in `tools/ModAssetPreview.ps1` to the exported folder, and `Override Root` to your test pack.
