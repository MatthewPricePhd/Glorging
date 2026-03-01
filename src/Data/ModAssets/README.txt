# Mod Asset Overrides

This project now supports optional cosmetic overrides from disk.

Runtime folder (relative to `Lemmix.exe`):

- `Data\\ModAssets\\UI\\menu_background.png`
- `Data\\ModAssets\\UI\\loading_background.png`
- `Data\\ModAssets\\Lemmings\\anim_XX.png`
- `Data\\ModAssets\\Lemmings\\mask_XX.png`

If an override file is missing, the game uses built-in assets.
If an override file exists but has wrong dimensions, startup raises an error with expected size.

See `MOD_ASSET_PIPELINE.md` in repo root for full specs.
