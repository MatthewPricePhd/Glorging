# Mod Asset Preview Tool

Standalone UI preview for `Data\ModAssets` files without running `Lemmix.exe`.

## Run

From repo root:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\ModAssetPreview.ps1
```

Optional roots:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\ModAssetPreview.ps1 `
  -OverrideRoot "C:\path\to\MyPack\ModAssets" `
  -ReferenceRoot "C:\path\to\Baseline\ModAssets"
```

## What it previews

- UI backgrounds (`menu_background.png`, `loading_background.png`)
- Lemming strips (`anim_00.png` ... `anim_27.png`)
- Mask strips (`mask_00.png` ... `mask_05.png`)

## Visual diff

- Set `Override Root` to your test assets.
- Set `Reference Root` to a baseline asset export.
- The tool shows:
  - Reference strip/frame
  - Override strip/frame
  - Difference image (bright pixels = larger change)

You can generate a reference export with:

- `src/ModAssetBaselineExport.dpr` (see `tools/ModAssetBaselineExport.md`)

## Notes

- The app validates dimensions against `MOD_ASSET_PIPELINE.md`.
- If `Reference Root` is empty, it still works for single-pack preview.
