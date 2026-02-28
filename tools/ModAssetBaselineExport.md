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

Optional:

```powershell
.\ModAssetBaselineExport.exe --style Orig --out C:\Temp\BaselineModAssets
```

For a true baseline export, keep `Data\ModAssets` empty when running this tool (or run from a clean copy) so override files are not picked up by the style loader.

## Use with preview

Set `Reference Root` in `tools/ModAssetPreview.ps1` to the exported folder, and `Override Root` to your test pack.
