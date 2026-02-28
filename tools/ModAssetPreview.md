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

## Run

From repo root:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\ModAssetPreview.ps1
```

Or build and run launcher EXE:

- project: `src/ModAssetPreviewLauncher.dproj`
- exe: `ModAssetPreviewLauncher.exe`

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

## Visual diff

- Set `Override Root` to your test assets.
- Set `Reference Root` to a baseline asset export (or leave auto-style reference enabled).
- The tool shows:
  - Reference strip/frame
  - Override strip/frame
  - Difference image (bright pixels = larger change)

You can generate a reference export with:

- `src/ModAssetBaselineExport.dpr` (see `tools/ModAssetBaselineExport.md`)

## Notes

- The app validates dimensions against `MOD_ASSET_PIPELINE.md`.
- If `Reference Root` is empty, it still works for single-pack preview.
