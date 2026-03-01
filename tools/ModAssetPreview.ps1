param(
  [string]$OverrideRoot = "",
  [string]$ReferenceRoot = "",
  [string]$StartAsset = "",
  [string]$GameRoot = "",
  [string]$PackName = "Glorging",
  [string]$LibreSpriteRoot = "",
  [string]$LibreSpriteExe = ""
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NativeWin {
  [DllImport("user32.dll", SetLastError=true)]
  public static extern IntPtr SetParent(IntPtr hWndChild, IntPtr hWndNewParent);
  [DllImport("user32.dll", SetLastError=true)]
  public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
  [DllImport("user32.dll", SetLastError=true)]
  public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
  [DllImport("user32.dll", SetLastError=true)]
  public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
  [DllImport("user32.dll", SetLastError=true)]
  public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@

[System.Windows.Forms.Application]::EnableVisualStyles()

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..")
$styleNames = @("Orig", "Ohno", "H94", "X91", "X92")
$previewVersion = "v2026.02.28-embedded-libresprite"
$settingsDir = Join-Path $env:APPDATA "Glorging"
$settingsPath = Join-Path $settingsDir "ModAssetPreview.settings.json"
$logPath = Join-Path $env:TEMP "ModAssetPreview.log"

function Write-PreviewLog {
  param([string]$message)
  try {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    Add-Content -Path $logPath -Value ("[{0}] {1}" -f $ts, $message) -Encoding UTF8
  } catch {}
}

function Load-PreviewSettings {
  if (-not (Test-Path $settingsPath -PathType Leaf)) {
    return [pscustomobject]@{
      LibreSpriteRoot = ""
      LibreSpriteExe = ""
      CustomColors = @()
      LastDrawColor = -1
    }
  }
  try {
    $raw = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $loadedColors = @()
    if ($null -ne $raw.CustomColors) {
      foreach ($v in $raw.CustomColors) {
        try { $loadedColors += [int]$v } catch {}
      }
    }
    return [pscustomobject]@{
      LibreSpriteRoot = [string]$raw.LibreSpriteRoot
      LibreSpriteExe = [string]$raw.LibreSpriteExe
      CustomColors = $loadedColors
      LastDrawColor = $(try { [int]$raw.LastDrawColor } catch { -1 })
    }
  } catch {
    return [pscustomobject]@{
      LibreSpriteRoot = ""
      LibreSpriteExe = ""
      CustomColors = @()
      LastDrawColor = -1
    }
  }
}

function Save-PreviewSettings {
  param([string]$savedRoot, [string]$savedExe, [int[]]$savedCustomColors = @(), [int]$savedLastDrawColor = -1)
  if (-not $PSBoundParameters.ContainsKey("savedCustomColors")) {
    $savedCustomColors = $script:customPalette
  }
  if ($savedLastDrawColor -lt 0 -and $null -ne $script:lastDrawColor) {
    try { $savedLastDrawColor = [System.Drawing.ColorTranslator]::ToOle($script:lastDrawColor) } catch {}
  }
  try {
    Ensure-Directory $settingsDir
    $obj = [pscustomobject]@{
      LibreSpriteRoot = $savedRoot
      LibreSpriteExe = $savedExe
      CustomColors = $savedCustomColors
      LastDrawColor = $savedLastDrawColor
    }
    ($obj | ConvertTo-Json -Depth 3) | Set-Content -Path $settingsPath -Encoding UTF8
  } catch {}
}

$savedSettings = Load-PreviewSettings
$script:customPalette = @()
if ($null -ne $savedSettings.CustomColors -and $savedSettings.CustomColors.Count -gt 0) {
  foreach ($v in $savedSettings.CustomColors) {
    try { $script:customPalette += [int]$v } catch {}
  }
}

function Normalize-CustomPalette16 {
  param([int[]]$inputColors)
  $out = New-Object 'System.Collections.Generic.List[int]'
  if ($null -ne $inputColors) {
    foreach ($c in $inputColors) {
      try {
        # Force every entry to a 24-bit RGB OLE color; this avoids invalid/system
        # negative values from clearing the dialog custom-color slots.
        $rgb24 = ([int]$c -band 0x00FFFFFF)
        [void]$out.Add($rgb24)
      } catch {}
      if ($out.Count -ge 16) { break }
    }
  }
  while ($out.Count -lt 16) { [void]$out.Add(0xFFFFFF) }
  return $out.ToArray()
}

function Update-CustomPalette {
  param([System.Drawing.Color]$colorToAdd, [string]$savedRoot, [string]$savedExe)
  $script:lastDrawColor = [System.Drawing.Color]::FromArgb(255, $colorToAdd.R, $colorToAdd.G, $colorToAdd.B)
  $ole = [System.Drawing.ColorTranslator]::ToOle($colorToAdd)
  $newList = New-Object System.Collections.Generic.List[int]
  [void]$newList.Add([int]$ole)
  foreach ($c in $script:customPalette) {
    if ([int]$c -ne [int]$ole) { [void]$newList.Add([int]$c) }
    if ($newList.Count -ge 16) { break }
  }
  $script:customPalette = Normalize-CustomPalette16 -inputColors $newList.ToArray()
  Save-PreviewSettings -savedRoot $savedRoot -savedExe $savedExe -savedCustomColors $script:customPalette
}

function Sync-CustomPaletteFromDialog {
  param([System.Windows.Forms.ColorDialog]$dialog, [string]$savedRoot, [string]$savedExe, [System.Drawing.Color]$preferredColor)
  try {
    if ($null -eq $dialog) { return }
    $arr = $dialog.CustomColors
    $newList = New-Object 'System.Collections.Generic.List[int]'
    if ($null -ne $preferredColor -and -not $preferredColor.IsEmpty) {
      [void]$newList.Add([int][System.Drawing.ColorTranslator]::ToOle($preferredColor))
      $script:lastDrawColor = [System.Drawing.Color]::FromArgb(255, $preferredColor.R, $preferredColor.G, $preferredColor.B)
    }
    # Preserve existing recents first so dialog placeholder slots cannot evict them.
    foreach ($v in $script:customPalette) {
      $iv = [int]$v
      if ($newList.Contains($iv)) { continue }
      [void]$newList.Add($iv)
      if ($newList.Count -ge 16) { break }
    }
    # Then append dialog-provided custom slots (if any new colors were added there).
    if ($null -ne $arr -and $arr.Length -gt 0 -and $newList.Count -lt 16) {
      foreach ($v in $arr) {
        $iv = [int]$v
        if ($newList.Contains($iv)) { continue }
        [void]$newList.Add($iv)
        if ($newList.Count -ge 16) { break }
      }
    }
    $script:customPalette = Normalize-CustomPalette16 -inputColors $newList.ToArray()
    Save-PreviewSettings -savedRoot $savedRoot -savedExe $savedExe -savedCustomColors $script:customPalette
  } catch {}
}

function Set-ColorDialogPaletteSafe {
  param([System.Windows.Forms.ColorDialog]$dialog, [int[]]$colors)
  if ($null -eq $dialog) { return }
  $normalized = Normalize-CustomPalette16 -inputColors $colors
  try {
    $dialog.CustomColors = $normalized
  } catch {
    # Keep this visible in-session so palette regressions are diagnosable.
    if ($null -ne $script:editorStatus) {
      $script:editorStatus.Text = "Status: failed to apply color palette (custom slots may appear blank)."
    }
  }
}

function Show-ColorDialogSafe {
  param([System.Windows.Forms.ColorDialog]$dialog, [System.Windows.Forms.IWin32Window]$owner)
  if ($null -eq $dialog) { return [System.Windows.Forms.DialogResult]::Cancel }
  try {
    if ($null -ne $owner) {
      return $dialog.ShowDialog($owner)
    }
    return $dialog.ShowDialog()
  } catch {
    [void][System.Windows.Forms.MessageBox]::Show(
      $owner,
      "Color picker failed to open. Try launching with an STA host or reset preview settings.`n`n$($_.Exception.Message)",
      "Color Picker Error",
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    return [System.Windows.Forms.DialogResult]::Cancel
  }
}

if ($script:customPalette.Count -gt 0) {
  $script:customPalette = Normalize-CustomPalette16 -inputColors $script:customPalette
}

$defaultDrawColor = [System.Drawing.Color]::FromArgb(255, 235, 235, 235)
$script:lastDrawColor = $defaultDrawColor
try {
  $savedOle = [int]$savedSettings.LastDrawColor
  if ($savedOle -ge 0) {
    $tmpColor = [System.Drawing.ColorTranslator]::FromOle($savedOle)
    $script:lastDrawColor = [System.Drawing.Color]::FromArgb(255, $tmpColor.R, $tmpColor.G, $tmpColor.B)
  }
} catch {}

if ([string]::IsNullOrWhiteSpace($LibreSpriteRoot) -and -not [string]::IsNullOrWhiteSpace($savedSettings.LibreSpriteRoot)) {
  $LibreSpriteRoot = $savedSettings.LibreSpriteRoot
}
if ([string]::IsNullOrWhiteSpace($LibreSpriteRoot)) {
  $LibreSpriteRoot = Join-Path $repoRoot "third_party\LibreSprite"
}
if ([string]::IsNullOrWhiteSpace($LibreSpriteExe) -and -not [string]::IsNullOrWhiteSpace($savedSettings.LibreSpriteExe)) {
  $LibreSpriteExe = $savedSettings.LibreSpriteExe
}

function Resolve-LibreSpriteExe {
  param([string]$rootPath, [string]$explicitExe)
  if (-not [string]::IsNullOrWhiteSpace($explicitExe) -and (Test-Path $explicitExe -PathType Leaf)) {
    return [System.IO.Path]::GetFullPath($explicitExe)
  }
  $candidates = @(
    (Join-Path $rootPath "build\bin\libresprite.exe"),
    (Join-Path $rootPath "build\Release\libresprite.exe"),
    (Join-Path $rootPath "build\RelWithDebInfo\libresprite.exe"),
    (Join-Path $rootPath "bin\libresprite.exe")
  )
  foreach ($c in $candidates) {
    if (Test-Path $c -PathType Leaf) { return [System.IO.Path]::GetFullPath($c) }
  }
  return ""
}

$LibreSpriteExe = Resolve-LibreSpriteExe -rootPath $LibreSpriteRoot -explicitExe $LibreSpriteExe

function Find-LibreSpriteExeAuto {
  param([string]$rootPath)
  $candidates = New-Object System.Collections.Generic.List[string]
  if (-not [string]::IsNullOrWhiteSpace($rootPath)) {
    [void]$candidates.Add((Join-Path $rootPath "build\bin\libresprite.exe"))
    [void]$candidates.Add((Join-Path $rootPath "build\Release\libresprite.exe"))
    [void]$candidates.Add((Join-Path $rootPath "build\RelWithDebInfo\libresprite.exe"))
    [void]$candidates.Add((Join-Path $rootPath "bin\libresprite.exe"))
  }
  [void]$candidates.Add((Join-Path $repoRoot "third_party\LibreSprite\build\bin\libresprite.exe"))
  [void]$candidates.Add((Join-Path $repoRoot "third_party\LibreSprite\build\Release\libresprite.exe"))
  [void]$candidates.Add((Join-Path $env:ProgramFiles "LibreSprite\libresprite.exe"))
  [void]$candidates.Add((Join-Path $env:LOCALAPPDATA "Programs\LibreSprite\libresprite.exe"))

  try {
    $w = where.exe libresprite 2>$null
    if ($LASTEXITCODE -eq 0 -and $w) {
      foreach ($line in $w) {
        if (-not [string]::IsNullOrWhiteSpace($line)) { [void]$candidates.Add([string]$line) }
      }
    }
  } catch {}

  foreach ($c in $candidates) {
    if (-not [string]::IsNullOrWhiteSpace($c) -and (Test-Path $c -PathType Leaf)) {
      return [System.IO.Path]::GetFullPath($c)
    }
  }

  $searchRoots = @(
    (Join-Path $repoRoot "third_party\LibreSprite"),
    $rootPath
  )
  foreach ($sr in $searchRoots) {
    if ([string]::IsNullOrWhiteSpace($sr) -or -not (Test-Path $sr -PathType Container)) { continue }
    try {
      $foundList = @(Get-ChildItem -Path $sr -Recurse -Filter "libresprite.exe" -File -ErrorAction SilentlyContinue)
      if ($foundList.Count -gt 0) {
        $best = $null
        foreach ($f in $foundList) {
          if ($null -eq $best -or $f.LastWriteTime -gt $best.LastWriteTime) { $best = $f }
        }
        if ($null -ne $best) {
          return [System.IO.Path]::GetFullPath($best.FullName)
        }
      }
    } catch {}
  }

  return ""
}

if ([string]::IsNullOrWhiteSpace($LibreSpriteExe) -or -not (Test-Path $LibreSpriteExe -PathType Leaf)) {
  $autoExe = Find-LibreSpriteExeAuto -rootPath $LibreSpriteRoot
  if (-not [string]::IsNullOrWhiteSpace($autoExe)) {
    $LibreSpriteExe = $autoExe
    Save-PreviewSettings -savedRoot $LibreSpriteRoot -savedExe $LibreSpriteExe
  }
}

function Test-GameRoot {
  param([string]$path)
  if ([string]::IsNullOrWhiteSpace($path)) { return $false }
  $root = [System.IO.Path]::GetFullPath($path)
  return (Test-Path (Join-Path $root "Data\Styles") -PathType Container)
}

function Get-GameCandidates {
  param([string]$repoRootPath)
  $set = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
  $list = New-Object System.Collections.Generic.List[string]

  $seed = @(
    (Join-Path $repoRootPath "src"),
    (Join-Path $repoRootPath "dist\Glorging-win32"),
    (Join-Path $repoRootPath "runtime\upstream-2.1.0"),
    $repoRootPath
  )

  foreach ($p in $seed) {
    if (Test-GameRoot $p) {
      $full = [System.IO.Path]::GetFullPath($p)
      if ($set.Add($full)) { [void]$list.Add($full) }
    }
  }

  try {
    foreach ($d in (Get-ChildItem -Path $repoRootPath -Directory -Depth 2 -ErrorAction SilentlyContinue)) {
      if (Test-GameRoot $d.FullName) {
        $full = [System.IO.Path]::GetFullPath($d.FullName)
        if ($set.Add($full)) { [void]$list.Add($full) }
      }
    }
  } catch {}

  return $list.ToArray()
}

function Ensure-Directory {
  param([string]$path)
  if (-not (Test-Path $path -PathType Container)) {
    [void](New-Item -ItemType Directory -Path $path -Force)
  }
}

function Test-BaselineReady {
  param([string]$gameRootPath)
  foreach ($style in $styleNames) {
    $infoPath = Join-Path $gameRootPath ("Data\ModAssets\Baseline\{0}\EXPORT_INFO.txt" -f $style)
    if (-not (Test-Path $infoPath -PathType Leaf)) { return $false }
  }
  return $true
}

function Resolve-ExporterExe {
  param([string]$repoRootPath, [string]$gameRootPath)
  $candidates = @(
    (Join-Path $repoRootPath "src\ModAssetBaselineExport.exe"),
    (Join-Path $gameRootPath "ModAssetBaselineExport.exe")
  )
  foreach ($c in $candidates) {
    if (Test-Path $c -PathType Leaf) { return $c }
  }
  return $null
}

function Ensure-BaselineExportAllStyles {
  param([string]$gameRootPath, [System.Windows.Forms.IWin32Window]$owner)
  if (Test-BaselineReady $gameRootPath) { return $true }

  $exporterExe = Resolve-ExporterExe -repoRootPath $repoRoot -gameRootPath $gameRootPath
  if ($null -eq $exporterExe) {
    [void][System.Windows.Forms.MessageBox]::Show(
      $owner,
      "Could not find ModAssetBaselineExport.exe.`nBuild src\ModAssetBaselineExport.dpr first.",
      "Exporter Missing",
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Error
    )
    return $false
  }

  $outDir = Join-Path $gameRootPath "Data\ModAssets\Baseline"
  Ensure-Directory $outDir

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $exporterExe
  $psi.WorkingDirectory = Split-Path -Parent $exporterExe
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.Arguments = ('--game "{0}" --all-styles --out "{1}"' -f $gameRootPath, $outDir)

  $proc = New-Object System.Diagnostics.Process
  $proc.StartInfo = $psi
  [void]$proc.Start()
  $stdout = $proc.StandardOutput.ReadToEnd()
  $stderr = $proc.StandardError.ReadToEnd()
  $proc.WaitForExit()

  if ($proc.ExitCode -ne 0 -or -not (Test-BaselineReady $gameRootPath)) {
    $msg = "Baseline export failed.`n`nCommand:`n$exporterExe $($psi.Arguments)`n`nSTDOUT:`n$stdout`n`nSTDERR:`n$stderr"
    [void][System.Windows.Forms.MessageBox]::Show(
      $owner,
      $msg,
      "Export Failed",
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Error
    )
    return $false
  }

  return $true
}

function Choose-GameRoot {
  param([string[]]$candidates)
  if ($candidates.Count -gt 0) { return $candidates[0] }
  return $null
}

$candidateRoots = Get-GameCandidates -repoRootPath $repoRoot
if (-not [string]::IsNullOrWhiteSpace($GameRoot) -and (Test-GameRoot $GameRoot)) {
  $GameRoot = [System.IO.Path]::GetFullPath($GameRoot)
} else {
  $GameRoot = Choose-GameRoot -candidates $candidateRoots
}

if ([string]::IsNullOrWhiteSpace($GameRoot)) {
  $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
  $dialog.Description = "Select game install folder (must contain Data\Styles)"
  if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and (Test-GameRoot $dialog.SelectedPath)) {
    $GameRoot = [System.IO.Path]::GetFullPath($dialog.SelectedPath)
  } else {
    throw "No valid game install selected."
  }
}

if ([string]::IsNullOrWhiteSpace($OverrideRoot)) {
  $OverrideRoot = Join-Path $GameRoot ("Data\ModAssets\Packs\{0}" -f $PackName)
}

Ensure-Directory $OverrideRoot
Ensure-Directory (Join-Path $OverrideRoot "UI")
Ensure-Directory (Join-Path $OverrideRoot "Lemmings")

$script:autoReferenceByStyle = [string]::IsNullOrWhiteSpace($ReferenceRoot)
if ($script:autoReferenceByStyle) {
  $ReferenceRoot = Join-Path $GameRoot "Data\ModAssets\Baseline\Orig"
}

function New-AssetSpec {
  param(
    [string]$Id,
    [string]$Display,
    [string]$Kind,
    [string]$RelPath,
    [int]$Frames,
    [int]$FrameW,
    [int]$FrameH
  )
  [pscustomobject]@{
    Id = $Id
    Display = $Display
    Kind = $Kind
    RelPath = $RelPath
    Frames = $Frames
    FrameW = $FrameW
    FrameH = $FrameH
    ExpectedW = $FrameW
    ExpectedH = $FrameH * $Frames
  }
}

$assetSpecs = New-Object System.Collections.Generic.List[object]
$assetSpecs.Add((New-AssetSpec -Id "menu_background" -Display "UI: Menu Background" -Kind "ui" -RelPath "UI\menu_background.png" -Frames 1 -FrameW 640 -FrameH 350))
$assetSpecs.Add((New-AssetSpec -Id "loading_background" -Display "UI: Loading Background" -Kind "ui" -RelPath "UI\loading_background.png" -Frames 1 -FrameW 640 -FrameH 350))

$animRows = @(
  @("anim_00", "Walking", 8, 16, 10),
  @("anim_01", "Jumping", 1, 16, 10),
  @("anim_02", "Walking RTL", 8, 16, 10),
  @("anim_03", "Jumping RTL", 1, 16, 10),
  @("anim_04", "Digging", 16, 16, 14),
  @("anim_05", "Climbing", 8, 16, 12),
  @("anim_06", "Climbing RTL", 8, 16, 12),
  @("anim_07", "Drowning", 16, 16, 10),
  @("anim_08", "Hoisting", 8, 16, 12),
  @("anim_09", "Hoisting RTL", 8, 16, 12),
  @("anim_10", "Building", 16, 16, 13),
  @("anim_11", "Building RTL", 16, 16, 13),
  @("anim_12", "Bashing", 32, 16, 10),
  @("anim_13", "Bashing RTL", 32, 16, 10),
  @("anim_14", "Mining", 24, 16, 13),
  @("anim_15", "Mining RTL", 24, 16, 13),
  @("anim_16", "Falling", 4, 16, 10),
  @("anim_17", "Falling RTL", 4, 16, 10),
  @("anim_18", "Umbrella", 8, 16, 16),
  @("anim_19", "Umbrella RTL", 8, 16, 16),
  @("anim_20", "Splatting", 16, 16, 10),
  @("anim_21", "Exiting", 8, 16, 13),
  @("anim_22", "Vaporizing", 14, 16, 14),
  @("anim_23", "Blocking", 16, 16, 10),
  @("anim_24", "Shrugging", 8, 16, 10),
  @("anim_25", "Shrugging RTL", 8, 16, 10),
  @("anim_26", "Oh-No-ing", 16, 16, 10),
  @("anim_27", "Exploding", 1, 32, 32)
)

$maskRows = @(
  @("mask_00", "Bash Masks", 4, 16, 10),
  @("mask_01", "Bash Masks RTL", 4, 16, 10),
  @("mask_02", "Mine Masks", 2, 16, 13),
  @("mask_03", "Mine Masks RTL", 2, 16, 13),
  @("mask_04", "Explosion Mask", 1, 16, 22),
  @("mask_05", "Countdown Digits", 5, 8, 8)
)

foreach ($row in $animRows) {
  $assetSpecs.Add((New-AssetSpec -Id $row[0] -Display ("Lemming: {0} ({1})" -f $row[1], $row[0]) -Kind "strip" -RelPath ("Lemmings\{0}.png" -f $row[0]) -Frames $row[2] -FrameW $row[3] -FrameH $row[4]))
}
foreach ($row in $maskRows) {
  $assetSpecs.Add((New-AssetSpec -Id $row[0] -Display ("Mask: {0} ({1})" -f $row[1], $row[0]) -Kind "strip" -RelPath ("Lemmings\{0}.png" -f $row[0]) -Frames $row[2] -FrameW $row[3] -FrameH $row[4]))
}

function Test-ExpectedSize {
  param($bmp, [int]$expectedW, [int]$expectedH)
  if ($null -eq $bmp) { return $false }
  return ($bmp.Width -eq $expectedW -and $bmp.Height -eq $expectedH)
}

function Load-BitmapSafe {
  param([string]$path)
  if (-not (Test-Path $path -PathType Leaf)) { return $null }
  try {
    $fileStream = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
      $raw = [System.Drawing.Bitmap]::FromStream($fileStream)
      try {
        # Always convert to 32bpp ARGB so SetPixel editing works for indexed PNGs.
        $editable = New-Object System.Drawing.Bitmap($raw.Width, $raw.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($editable)
        try {
          $g.DrawImage($raw, 0, 0, $raw.Width, $raw.Height)
        } finally {
          $g.Dispose()
        }
        return $editable
      } finally {
        $raw.Dispose()
      }
    } finally {
      $fileStream.Dispose()
    }
  } catch {
    return $null
  }
}

function New-FrameBitmap {
  param($stripBmp, [int]$frameIndex, [int]$frameW, [int]$frameH, [int]$frameCount)
  if ($null -eq $stripBmp) { return $null }
  if ($frameIndex -lt 0 -or $frameIndex -ge $frameCount) { return $null }
  if ($stripBmp.Width -lt $frameW) { return $null }
  $maxH = ($frameIndex + 1) * $frameH
  if ($stripBmp.Height -lt $maxH) { return $null }
  $rect = [System.Drawing.Rectangle]::new([int]0, [int]($frameIndex * $frameH), [int]$frameW, [int]$frameH)
  try {
    return $stripBmp.Clone($rect, $stripBmp.PixelFormat)
  } catch {
    return $stripBmp.Clone($rect, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  }
}

function New-DiffBitmap {
  param($bmpA, $bmpB)
  if ($null -eq $bmpA -or $null -eq $bmpB) { return $null }
  if ($bmpA.Width -ne $bmpB.Width -or $bmpA.Height -ne $bmpB.Height) { return $null }
  $w = $bmpA.Width
  $h = $bmpA.Height
  $outBmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
  for ($y = 0; $y -lt $h; $y++) {
    for ($x = 0; $x -lt $w; $x++) {
      $a = $bmpA.GetPixel($x, $y)
      $b = $bmpB.GetPixel($x, $y)
      $dr = [Math]::Min([Math]::Abs($a.R - $b.R) * 4, 255)
      $dg = [Math]::Min([Math]::Abs($a.G - $b.G) * 4, 255)
      $db = [Math]::Min([Math]::Abs($a.B - $b.B) * 4, 255)
      $outBmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($dr, $dg, $db))
    }
  }
  return $outBmp
}

function Set-ImageBox {
  param($pictureBox, $newImage)
  if ($null -ne $pictureBox.Image) { $pictureBox.Image.Dispose() }
  $pictureBox.Image = $newImage
}

function New-PreviewBox {
  param([string]$titleText)
  $panel = New-Object System.Windows.Forms.Panel
  $panel.Dock = [System.Windows.Forms.DockStyle]::Fill

  $label = New-Object System.Windows.Forms.Label
  $label.Text = $titleText
  $label.Dock = [System.Windows.Forms.DockStyle]::Top
  $label.Height = 20
  $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter

  $picture = New-Object System.Windows.Forms.PictureBox
  $picture.Dock = [System.Windows.Forms.DockStyle]::Fill
  $picture.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
  $picture.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
  $picture.BackColor = [System.Drawing.Color]::FromArgb(18, 18, 18)

  [void]$panel.Controls.Add($picture)
  [void]$panel.Controls.Add($label)

  return [pscustomobject]@{
    Panel = $panel
    Label = $label
    Picture = $picture
  }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Glorging Mod Asset Preview ($previewVersion)"
$form.Width = 1500
$form.Height = 950
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen

$rootLayout = New-Object System.Windows.Forms.TableLayoutPanel
$rootLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
$rootLayout.ColumnCount = 1
$rootLayout.RowCount = 3
$rootLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$rootLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$rootLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))

$toolbar = New-Object System.Windows.Forms.TableLayoutPanel
$toolbar.Dock = [System.Windows.Forms.DockStyle]::Top
$toolbar.ColumnCount = 6
$toolbar.RowCount = 4
$toolbar.AutoSize = $true
$toolbar.Padding = New-Object System.Windows.Forms.Padding(8)
$toolbar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 120)))
$toolbar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
$toolbar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 90)))
$toolbar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 120)))
$toolbar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
$toolbar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 120)))

$gameLabel = New-Object System.Windows.Forms.Label
$gameLabel.Text = "Game Install"
$gameLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$gameLabel.Dock = [System.Windows.Forms.DockStyle]::Fill

$gameCombo = New-Object System.Windows.Forms.ComboBox
$gameCombo.Dock = [System.Windows.Forms.DockStyle]::Fill
$gameCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
foreach ($r in $candidateRoots) { [void]$gameCombo.Items.Add($r) }
if ($gameCombo.Items.IndexOf($GameRoot) -lt 0) { [void]$gameCombo.Items.Add($GameRoot) }
$gameCombo.SelectedItem = $GameRoot

$gameBrowse = New-Object System.Windows.Forms.Button
$gameBrowse.Text = "Select..."
$gameBrowse.Dock = [System.Windows.Forms.DockStyle]::Fill

$styleLabel = New-Object System.Windows.Forms.Label
$styleLabel.Text = "Preview Style"
$styleLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$styleLabel.Dock = [System.Windows.Forms.DockStyle]::Fill

$styleCombo = New-Object System.Windows.Forms.ComboBox
$styleCombo.Dock = [System.Windows.Forms.DockStyle]::Fill
$styleCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
foreach ($s in $styleNames) { [void]$styleCombo.Items.Add($s) }
$styleCombo.SelectedItem = "Orig"

$ensureBaselineButton = New-Object System.Windows.Forms.Button
$ensureBaselineButton.Text = "Ensure Baseline"
$ensureBaselineButton.Dock = [System.Windows.Forms.DockStyle]::Fill

$overrideLabel = New-Object System.Windows.Forms.Label
$overrideLabel.Text = "Override Root"
$overrideLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$overrideLabel.Dock = [System.Windows.Forms.DockStyle]::Fill

$overrideText = New-Object System.Windows.Forms.TextBox
$overrideText.Text = $OverrideRoot
$overrideText.Dock = [System.Windows.Forms.DockStyle]::Fill

$overrideBrowse = New-Object System.Windows.Forms.Button
$overrideBrowse.Text = "Browse"
$overrideBrowse.Dock = [System.Windows.Forms.DockStyle]::Fill

$referenceLabel = New-Object System.Windows.Forms.Label
$referenceLabel.Text = "Reference Root"
$referenceLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$referenceLabel.Dock = [System.Windows.Forms.DockStyle]::Fill

$referenceText = New-Object System.Windows.Forms.TextBox
$referenceText.Text = $ReferenceRoot
$referenceText.Dock = [System.Windows.Forms.DockStyle]::Fill

$referenceBrowse = New-Object System.Windows.Forms.Button
$referenceBrowse.Text = "Browse"
$referenceBrowse.Dock = [System.Windows.Forms.DockStyle]::Fill

$reloadButton = New-Object System.Windows.Forms.Button
$reloadButton.Text = "Reload (F5)"
$reloadButton.Dock = [System.Windows.Forms.DockStyle]::Left
$reloadButton.Width = 120

$autoPlay = New-Object System.Windows.Forms.CheckBox
$autoPlay.Text = "Auto-play strip"
$autoPlay.Checked = $true
$autoPlay.AutoSize = $true

$frameSlider = New-Object System.Windows.Forms.TrackBar
$frameSlider.Minimum = 0
$frameSlider.Maximum = 0
$frameSlider.TickStyle = [System.Windows.Forms.TickStyle]::BottomRight
$frameSlider.SmallChange = 1
$frameSlider.LargeChange = 1
$frameSlider.Width = 300

$frameLabel = New-Object System.Windows.Forms.Label
$frameLabel.Text = "Frame: 0 / 0"
$frameLabel.AutoSize = $true
$frameLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

$openPackButton = New-Object System.Windows.Forms.Button
$openPackButton.Text = "Open Active Pack Folder"
$openPackButton.Dock = [System.Windows.Forms.DockStyle]::Fill

$launchGameButton = New-Object System.Windows.Forms.Button
$launchGameButton.Text = "Launch Game"
$launchGameButton.Dock = [System.Windows.Forms.DockStyle]::Fill

$openOverrideAssetButton = New-Object System.Windows.Forms.Button
$openOverrideAssetButton.Text = "Open Current Override File"
$openOverrideAssetButton.Dock = [System.Windows.Forms.DockStyle]::Fill

[void]$toolbar.Controls.Add($overrideLabel, 0, 0)
[void]$toolbar.Controls.Add($overrideText, 1, 0)
[void]$toolbar.Controls.Add($overrideBrowse, 2, 0)
[void]$toolbar.Controls.Add($referenceLabel, 3, 0)
[void]$toolbar.Controls.Add($referenceText, 4, 0)
[void]$toolbar.Controls.Add($referenceBrowse, 5, 0)
[void]$toolbar.Controls.Add($gameLabel, 0, 1)
[void]$toolbar.Controls.Add($gameCombo, 1, 1)
[void]$toolbar.Controls.Add($gameBrowse, 2, 1)
[void]$toolbar.Controls.Add($styleLabel, 3, 1)
[void]$toolbar.Controls.Add($styleCombo, 4, 1)
[void]$toolbar.Controls.Add($ensureBaselineButton, 5, 1)
[void]$toolbar.Controls.Add($reloadButton, 0, 2)
[void]$toolbar.Controls.Add($autoPlay, 1, 2)
[void]$toolbar.Controls.Add($frameSlider, 4, 2)
[void]$toolbar.Controls.Add($frameLabel, 5, 2)
[void]$toolbar.Controls.Add($openPackButton, 0, 3)
[void]$toolbar.Controls.Add($launchGameButton, 1, 3)
[void]$toolbar.Controls.Add($openOverrideAssetButton, 2, 3)

$mainSplit = New-Object System.Windows.Forms.SplitContainer
$mainSplit.Dock = [System.Windows.Forms.DockStyle]::Fill
$mainSplit.Orientation = [System.Windows.Forms.Orientation]::Vertical
$mainSplit.FixedPanel = [System.Windows.Forms.FixedPanel]::Panel1
$mainSplit.Panel1MinSize = 420
$mainSplit.SplitterDistance = 520

$assetList = New-Object System.Windows.Forms.ListBox
$assetList.Dock = [System.Windows.Forms.DockStyle]::Fill
$assetList.IntegralHeight = $false
foreach ($spec in $assetSpecs) {
  [void]$assetList.Items.Add($spec.Display)
}

[void]$mainSplit.Panel1.Controls.Add($assetList)

$rightLayout = New-Object System.Windows.Forms.TableLayoutPanel
$rightLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
$rightLayout.ColumnCount = 1
$rightLayout.RowCount = 1
$rightLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))

$liveGrid = New-Object System.Windows.Forms.TableLayoutPanel
$liveGrid.Dock = [System.Windows.Forms.DockStyle]::Fill
$liveGrid.ColumnCount = 2
$liveGrid.RowCount = 1
$liveGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
$liveGrid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))

$liveReference = New-PreviewBox "Live Reference"
$liveOverride = New-PreviewBox "Live Override"
[void]$liveGrid.Controls.Add($liveReference.Panel, 0, 0)
[void]$liveGrid.Controls.Add($liveOverride.Panel, 1, 0)

$rightSplit = New-Object System.Windows.Forms.SplitContainer
$rightSplit.Dock = [System.Windows.Forms.DockStyle]::Fill
$rightSplit.Orientation = [System.Windows.Forms.Orientation]::Vertical
$rightSplit.FixedPanel = [System.Windows.Forms.FixedPanel]::None

$diagLayout = New-Object System.Windows.Forms.TableLayoutPanel
$diagLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
$diagLayout.ColumnCount = 2
$diagLayout.RowCount = 2
$diagLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
$diagLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
$diagLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 50)))
$diagLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 50)))

$stripReference = New-PreviewBox "Reference Strip"
$stripOverride = New-PreviewBox "Override Strip"
$frameReference = New-PreviewBox "Reference Frame"
$frameOverride = New-PreviewBox "Override Frame"
[void]$diagLayout.Controls.Add($stripReference.Panel, 0, 0)
[void]$diagLayout.Controls.Add($stripOverride.Panel, 1, 0)
[void]$diagLayout.Controls.Add($frameReference.Panel, 0, 1)
[void]$diagLayout.Controls.Add($frameOverride.Panel, 1, 1)

[void]$rightSplit.Panel1.Controls.Add($liveGrid)
[void]$rightSplit.Panel2.Controls.Add($diagLayout)

[void]$rightLayout.Controls.Add($rightSplit, 0, 0)
[void]$mainSplit.Panel2.Controls.Add($rightLayout)

$form.Add_Shown({
  $targetLeftWidth = 520
  if ($mainSplit.Width -gt ($targetLeftWidth + 220)) {
    $mainSplit.SplitterDistance = $targetLeftWidth
  }
  $targetDiagWidth = 260
  $target = $rightSplit.Width - $targetDiagWidth
  if ($target -gt 120 -and $target -lt ($rightSplit.Width - 120)) {
    $rightSplit.SplitterDistance = $target
  }
})

$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Dock = [System.Windows.Forms.DockStyle]::Fill

$previewTab = New-Object System.Windows.Forms.TabPage
$previewTab.Text = "Preview"
[void]$previewTab.Controls.Add($mainSplit)
[void]$tabControl.TabPages.Add($previewTab)

$editorTab = New-Object System.Windows.Forms.TabPage
$editorTab.Text = "Editor"

$editorTabs = New-Object System.Windows.Forms.TabControl
$editorTabs.Dock = [System.Windows.Forms.DockStyle]::Fill

$editorBasicTab = New-Object System.Windows.Forms.TabPage
$editorBasicTab.Text = "Basic"

$editorAdvancedTab = New-Object System.Windows.Forms.TabPage
$editorAdvancedTab.Text = "Advanced"

$basicLayout = New-Object System.Windows.Forms.TableLayoutPanel
$basicLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
$basicLayout.ColumnCount = 1
$basicLayout.RowCount = 4
$basicLayout.Padding = New-Object System.Windows.Forms.Padding(12)
$basicLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$basicLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$basicLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$basicLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))

$editorLayout = New-Object System.Windows.Forms.TableLayoutPanel
$editorLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
$editorLayout.ColumnCount = 3
$editorLayout.RowCount = 8
$editorLayout.Padding = New-Object System.Windows.Forms.Padding(12)
$editorLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 160)))
$editorLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$editorLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 170)))
$editorLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$editorLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$editorLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$editorLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$editorLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$editorLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$editorLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$editorLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))

$libRootLabel = New-Object System.Windows.Forms.Label
$libRootLabel.Text = "LibreSprite Source"
$libRootLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
$libRootLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

$libRootText = New-Object System.Windows.Forms.TextBox
$libRootText.Dock = [System.Windows.Forms.DockStyle]::Fill
$libRootText.Text = $LibreSpriteRoot

$libRootBrowse = New-Object System.Windows.Forms.Button
$libRootBrowse.Text = "Browse Source"
$libRootBrowse.Dock = [System.Windows.Forms.DockStyle]::Fill

$libExeLabel = New-Object System.Windows.Forms.Label
$libExeLabel.Text = "LibreSprite EXE"
$libExeLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
$libExeLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft

$libExeText = New-Object System.Windows.Forms.TextBox
$libExeText.Dock = [System.Windows.Forms.DockStyle]::Fill
$libExeText.Text = $LibreSpriteExe

$libExeBrowse = New-Object System.Windows.Forms.Button
$libExeBrowse.Text = "Browse EXE"
$libExeBrowse.Dock = [System.Windows.Forms.DockStyle]::Fill

$cloneUpdateButton = New-Object System.Windows.Forms.Button
$cloneUpdateButton.Text = "Setup LibreSprite Source (Advanced)"
$cloneUpdateButton.Dock = [System.Windows.Forms.DockStyle]::Fill

$openSourceButton = New-Object System.Windows.Forms.Button
$openSourceButton.Text = "Open Source Folder"
$openSourceButton.Dock = [System.Windows.Forms.DockStyle]::Fill

$launchLibreButton = New-Object System.Windows.Forms.Button
$launchLibreButton.Text = "Open LibreSprite (External)"
$launchLibreButton.Dock = [System.Windows.Forms.DockStyle]::Fill

$editAssetButton = New-Object System.Windows.Forms.Button
$editAssetButton.Text = "Open Selected Asset In Advanced Panel"
$editAssetButton.Dock = [System.Windows.Forms.DockStyle]::Fill

$integratedEditButton = New-Object System.Windows.Forms.Button
$integratedEditButton.Text = "Edit Selected Asset Here (Mini Tools)"
$integratedEditButton.Dock = [System.Windows.Forms.DockStyle]::Top
$integratedEditButton.Height = 40

$editorHelp = New-Object System.Windows.Forms.Label
$editorHelp.Text = "Basic workflow: select an asset in Preview, then click the mini-editor button below."
$editorHelp.AutoSize = $true
$editorHelp.MaximumSize = New-Object System.Drawing.Size(1000, 0)
$editorHelp.Dock = [System.Windows.Forms.DockStyle]::Fill

$advancedHelp = New-Object System.Windows.Forms.Label
$advancedHelp.Text = "Advanced workflow: open selected asset in embedded LibreSprite panel."
$advancedHelp.AutoSize = $true
$advancedHelp.MaximumSize = New-Object System.Drawing.Size(1000, 0)
$advancedHelp.Dock = [System.Windows.Forms.DockStyle]::Fill

$editorStatus = New-Object System.Windows.Forms.Label
$editorStatus.Text = "Status: idle"
$editorStatus.AutoSize = $true
$editorStatus.Dock = [System.Windows.Forms.DockStyle]::Fill
$editorStatus.Padding = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)

[void]$editorLayout.Controls.Add($libRootLabel, 0, 0)
[void]$editorLayout.Controls.Add($libRootText, 1, 0)
[void]$editorLayout.Controls.Add($libRootBrowse, 2, 0)
[void]$editorLayout.Controls.Add($libExeLabel, 0, 1)
[void]$editorLayout.Controls.Add($libExeText, 1, 1)
[void]$editorLayout.Controls.Add($libExeBrowse, 2, 1)
[void]$editorLayout.Controls.Add($cloneUpdateButton, 0, 2)
[void]$editorLayout.Controls.Add($openSourceButton, 2, 2)
[void]$editorLayout.Controls.Add($launchLibreButton, 0, 3)
[void]$editorLayout.Controls.Add($editAssetButton, 2, 3)
[void]$editorLayout.Controls.Add($advancedHelp, 0, 4)
$editorLayout.SetColumnSpan($advancedHelp, 3)

$advancedEditorHost = New-Object System.Windows.Forms.Panel
$advancedEditorHost.Dock = [System.Windows.Forms.DockStyle]::Fill
$advancedEditorHost.Visible = $false
$advancedEditorHost.BackColor = [System.Drawing.Color]::FromArgb(28, 28, 28)
[void]$editorLayout.Controls.Add($advancedEditorHost, 0, 6)
$editorLayout.SetColumnSpan($advancedEditorHost, 3)

[void]$editorLayout.Controls.Add($editorStatus, 0, 7)
$editorLayout.SetColumnSpan($editorStatus, 3)

[void]$basicLayout.Controls.Add($editorHelp, 0, 0)
[void]$basicLayout.Controls.Add($integratedEditButton, 0, 1)

$basicHint = New-Object System.Windows.Forms.Label
$basicHint.Text = "If no override asset file exists yet, it is auto-seeded from the current reference style."
$basicHint.AutoSize = $true
$basicHint.Dock = [System.Windows.Forms.DockStyle]::Top
[void]$basicLayout.Controls.Add($basicHint, 0, 2)

$integratedEditorHost = New-Object System.Windows.Forms.Panel
$integratedEditorHost.Dock = [System.Windows.Forms.DockStyle]::Fill
$integratedEditorHost.Visible = $false
$integratedEditorHost.BackColor = [System.Drawing.Color]::FromArgb(28, 28, 28)
[void]$basicLayout.Controls.Add($integratedEditorHost, 0, 3)

[void]$editorBasicTab.Controls.Add($basicLayout)
[void]$editorAdvancedTab.Controls.Add($editorLayout)
[void]$editorTabs.TabPages.Add($editorBasicTab)
[void]$editorTabs.TabPages.Add($editorAdvancedTab)
[void]$editorTab.Controls.Add($editorTabs)
[void]$tabControl.TabPages.Add($editorTab)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
$statusLabel.Padding = New-Object System.Windows.Forms.Padding(8, 6, 8, 6)
$statusLabel.AutoSize = $true
$statusLabel.Text = "Status"

[void]$rootLayout.Controls.Add($toolbar, 0, 0)
[void]$rootLayout.Controls.Add($tabControl, 0, 1)
[void]$rootLayout.Controls.Add($statusLabel, 0, 2)
[void]$form.Controls.Add($rootLayout)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 120
$timer.Enabled = $true

$currentSpec = $null
$currentRefStrip = $null
$currentOverrideStrip = $null
$currentFrameIndex = 0
$script:embeddedLibreProc = $null
$script:embeddedLibreHwnd = [IntPtr]::Zero
$script:embeddedAssetPath = ""
$script:embeddedAssetWriteUtc = [datetime]::MinValue

function Dispose-CurrentStripState {
  if ($null -ne $script:currentRefStrip) { $script:currentRefStrip.Dispose(); $script:currentRefStrip = $null }
  if ($null -ne $script:currentOverrideStrip) { $script:currentOverrideStrip.Dispose(); $script:currentOverrideStrip = $null }
}

function Select-Folder {
  param([string]$initialPath)
  $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
  if (-not [string]::IsNullOrWhiteSpace($initialPath) -and (Test-Path $initialPath -PathType Container)) {
    $dialog.SelectedPath = $initialPath
  }
  $dialog.Description = "Select ModAssets root folder"
  if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    return $dialog.SelectedPath
  }
  return $null
}

function Set-ReferenceRootForStyle {
  param([string]$styleName)
  if (-not $script:autoReferenceByStyle) { return }
  $referenceText.Text = Join-Path $GameRoot ("Data\ModAssets\Baseline\{0}" -f $styleName)
}

function Open-ActivePackFolder {
  $target = $overrideText.Text
  if ([string]::IsNullOrWhiteSpace($target)) { return }
  Ensure-Directory $target
  Start-Process -FilePath "explorer.exe" -ArgumentList ('"{0}"' -f $target) | Out-Null
}

function Launch-GameExe {
  $exe = Join-Path $GameRoot "Lemmix.exe"
  if (-not (Test-Path $exe -PathType Leaf)) {
    [void][System.Windows.Forms.MessageBox]::Show(
      $form,
      "Could not find Lemmix.exe in: $GameRoot",
      "Launch Game",
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    return
  }
  Start-Process -FilePath $exe -WorkingDirectory $GameRoot | Out-Null
}

function Select-ExecutableFile {
  param([string]$title, [string]$initialDir)
  $dlg = New-Object System.Windows.Forms.OpenFileDialog
  $dlg.Title = $title
  $dlg.Filter = "Executable (*.exe)|*.exe|All files (*.*)|*.*"
  if (-not [string]::IsNullOrWhiteSpace($initialDir) -and (Test-Path $initialDir -PathType Container)) {
    $dlg.InitialDirectory = $initialDir
  }
  if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    return $dlg.FileName
  }
  return $null
}

function Get-SelectedAssetPath {
  if ($assetList.SelectedIndex -lt 0) { return $null }
  $spec = $assetSpecs[$assetList.SelectedIndex]
  if ($null -eq $spec) { return $null }
  return Join-Path $overrideText.Text $spec.RelPath
}

function Open-CurrentOverrideAsset {
  $assetPath = Get-SelectedAssetPath
  if ([string]::IsNullOrWhiteSpace($assetPath)) {
    [void][System.Windows.Forms.MessageBox]::Show($form, "Select an asset first.", "Open Override", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    return
  }
  Ensure-Directory (Split-Path -Parent $assetPath)
  if (-not (Test-Path $assetPath -PathType Leaf)) {
    [void][System.Windows.Forms.MessageBox]::Show($form, "Override file does not exist yet:`n$assetPath`n`nSave from Editor first.", "Open Override", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
    Start-Process -FilePath "explorer.exe" -ArgumentList ('"/select,{0}"' -f $assetPath) | Out-Null
    return
  }
  Start-Process -FilePath "explorer.exe" -ArgumentList ('"/select,{0}"' -f $assetPath) | Out-Null
}

function Open-IntegratedPixelEditor {
  param([string]$assetPath, $spec)
  Write-PreviewLog ("Open-IntegratedPixelEditor start asset={0}" -f $assetPath)
  if ($null -eq $spec) { return }
  if ($spec.Kind -ne "strip") { [void][System.Windows.Forms.MessageBox]::Show($form, "Integrated editor is optimized for strip assets.`nUse LibreSprite for large UI backgrounds.", "Integrated Editor", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information); return }
  $workingPath=$assetPath; $seededFromReference=$false
  if (-not (Test-Path $workingPath -PathType Leaf)) {
    $refCandidate=Join-Path $referenceText.Text $spec.RelPath
    if (Test-Path $refCandidate -PathType Leaf) {
      Ensure-Directory (Split-Path -Parent $workingPath)
      Copy-Item $refCandidate $workingPath -Force
      $seededFromReference=$true
    } else {
      [void][System.Windows.Forms.MessageBox]::Show($form, "Asset file missing and no reference file found to seed it.`n$workingPath", "Integrated Editor", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
      return
    }
  }
  $srcBmp=Load-BitmapSafe $workingPath
  if ($null -eq $srcBmp) { [void][System.Windows.Forms.MessageBox]::Show($form, "Unable to open asset for editing:`n$workingPath", "Integrated Editor", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error); return }

  $origBmp=[System.Drawing.Bitmap]$srcBmp.Clone()
  $prevAutoPlay=$autoPlay.Checked
  $autoPlay.Checked=$false
  $editFrameCount=[Math]::Max(1,[Math]::Min([int]$spec.Frames,[int][Math]::Floor($srcBmp.Height/[Math]::Max(1,[int]$spec.FrameH))))
  $integratedEditorHost.SuspendLayout()
  try {
    foreach($ctl in @($integratedEditorHost.Controls)){$ctl.Dispose()}
    $integratedEditorHost.Controls.Clear()
    $integratedEditorHost.Visible=$true
    $editorHelp.Visible=$false

    $frameLab=New-Object System.Windows.Forms.Label; $frameLab.Text='Frame'; $frameLab.AutoSize=$true; $frameLab.Margin=New-Object System.Windows.Forms.Padding(2,8,4,2)
    $prevFrameBtn=New-Object System.Windows.Forms.Button; $prevFrameBtn.Text='<'; $prevFrameBtn.Width=28; $prevFrameBtn.Height=24; $prevFrameBtn.Margin=New-Object System.Windows.Forms.Padding(2,6,2,2)
    $framePick=New-Object System.Windows.Forms.NumericUpDown; $framePick.Minimum=0; $framePick.Maximum=[Math]::Max($editFrameCount-1,0); $framePick.Width=52
    $nextFrameBtn=New-Object System.Windows.Forms.Button; $nextFrameBtn.Text='>'; $nextFrameBtn.Width=28; $nextFrameBtn.Height=24; $nextFrameBtn.Margin=New-Object System.Windows.Forms.Padding(2,6,8,2)
    $frameInfo=New-Object System.Windows.Forms.Label; $frameInfo.AutoSize=$true; $frameInfo.Margin=New-Object System.Windows.Forms.Padding(2,8,10,2)

    $zoomLab=New-Object System.Windows.Forms.Label; $zoomLab.Text='Zoom'; $zoomLab.AutoSize=$true; $zoomLab.Margin=New-Object System.Windows.Forms.Padding(2,8,4,2)
    $zoomOutBtn=New-Object System.Windows.Forms.Button; $zoomOutBtn.Text='-'; $zoomOutBtn.Width=28; $zoomOutBtn.Height=24; $zoomOutBtn.Margin=New-Object System.Windows.Forms.Padding(2,6,2,2)
    $zoomPick=New-Object System.Windows.Forms.NumericUpDown; $zoomPick.Minimum=4; $zoomPick.Maximum=96; $zoomPick.Value=35; $zoomPick.Width=52
    $zoomInBtn=New-Object System.Windows.Forms.Button; $zoomInBtn.Text='+'; $zoomInBtn.Width=28; $zoomInBtn.Height=24; $zoomInBtn.Margin=New-Object System.Windows.Forms.Padding(2,6,8,2)
    $fitCheck=New-Object System.Windows.Forms.CheckBox; $fitCheck.Text='Fit'; $fitCheck.AutoSize=$true; $fitCheck.Margin=New-Object System.Windows.Forms.Padding(0,6,8,2)

    $eyeDropper=New-Object System.Windows.Forms.CheckBox; $eyeDropper.Text='Pick'; $eyeDropper.AutoSize=$true; $eyeDropper.Margin=New-Object System.Windows.Forms.Padding(0,6,8,2)
    $fillTool=New-Object System.Windows.Forms.CheckBox; $fillTool.Text='Fill'; $fillTool.AutoSize=$true; $fillTool.Margin=New-Object System.Windows.Forms.Padding(0,6,8,2)
    $eraser=New-Object System.Windows.Forms.CheckBox; $eraser.Text='Eraser'; $eraser.AutoSize=$true; $eraser.Margin=New-Object System.Windows.Forms.Padding(0,6,8,2)

    $saveBtn=New-Object System.Windows.Forms.Button; $saveBtn.Text='Save'; $saveBtn.Width=78
    $backBtn=New-Object System.Windows.Forms.Button; $backBtn.Text='Back'; $backBtn.Width=78
    $miniStatus=New-Object System.Windows.Forms.Label; $miniStatus.Text="Editing $workingPath | Left-click/drag = paint"; $miniStatus.AutoSize=$true; $miniStatus.MaximumSize=New-Object System.Drawing.Size(480,0)

    $split=New-Object System.Windows.Forms.SplitContainer
    $split.Dock='Fill'; $split.Orientation='Vertical'; $split.FixedPanel='Panel1'; $split.Panel1MinSize=300; $split.SplitterDistance=360

    $paletteHost=New-Object System.Windows.Forms.Panel
    $paletteHost.Dock='Fill'; $paletteHost.BackColor=[System.Drawing.Color]::FromArgb(244,246,248)
    $paletteHost.Padding=New-Object System.Windows.Forms.Padding(8); $paletteHost.AutoScroll=$true; $paletteHost.MinimumSize=New-Object System.Drawing.Size(300,0)

    $pl=New-Object System.Windows.Forms.TableLayoutPanel
    $pl.Dock='Fill'; $pl.AutoSize=$false; $pl.ColumnCount=1; $pl.RowCount=20
    $pl.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent,100)))
    for($i=0;$i -lt 19;$i++){ $pl.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize))) }
    $pl.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent,100)))

    $pathHdr=New-Object System.Windows.Forms.Label; $pathHdr.Text='Editing File'; $pathHdr.AutoSize=$true; $pathHdr.ForeColor=[System.Drawing.SystemColors]::ControlText
    $pathBox=New-Object System.Windows.Forms.TextBox; $pathBox.ReadOnly=$true; $pathBox.Dock='Top'; $pathBox.Text=$workingPath; $pathBox.Height=24; $pathBox.Margin=New-Object System.Windows.Forms.Padding(0,0,0,4)

    $frameZoomRow=New-Object System.Windows.Forms.FlowLayoutPanel; $frameZoomRow.AutoSize=$true; $frameZoomRow.WrapContents=$false; $frameZoomRow.Dock='Top'
    foreach($c in @($frameLab,$prevFrameBtn,$framePick,$nextFrameBtn,$frameInfo,$zoomLab,$zoomOutBtn,$zoomPick,$zoomInBtn,$fitCheck)){ [void]$frameZoomRow.Controls.Add($c) }

    $toolHdr=New-Object System.Windows.Forms.Label; $toolHdr.Text='Tools'; $toolHdr.AutoSize=$true; $toolHdr.ForeColor=[System.Drawing.SystemColors]::ControlText
    $toolRow=New-Object System.Windows.Forms.FlowLayoutPanel; $toolRow.AutoSize=$true; $toolRow.WrapContents=$false; $toolRow.Dock='Top'
    foreach($c in @($eyeDropper,$fillTool,$eraser)){ [void]$toolRow.Controls.Add($c) }

    $drawLabel=New-Object System.Windows.Forms.Label; $drawLabel.Text='Draw Color (used for mapping target)'; $drawLabel.AutoSize=$true; $drawLabel.ForeColor=[System.Drawing.SystemColors]::ControlText
    $drawSwatch=New-Object System.Windows.Forms.Panel; $drawSwatch.Width=120; $drawSwatch.Height=24; $drawSwatch.BorderStyle='FixedSingle'
    $drawInfo=New-Object System.Windows.Forms.Label; $drawInfo.Text=''; $drawInfo.AutoSize=$true; $drawInfo.ForeColor=[System.Drawing.SystemColors]::ControlText
    $script:integratedDrawSwatch=$drawSwatch
    $script:integratedDrawInfo=$drawInfo

    $defaultHdr=New-Object System.Windows.Forms.Label; $defaultHdr.Text='Default Palette (Strip Analysis)'; $defaultHdr.AutoSize=$true; $defaultHdr.ForeColor=[System.Drawing.SystemColors]::ControlText
    $defaultFlow=New-Object System.Windows.Forms.FlowLayoutPanel; $defaultFlow.Name='defaultFlowPalette'; $defaultFlow.AutoSize=$true; $defaultFlow.WrapContents=$true; $defaultFlow.Margin=New-Object System.Windows.Forms.Padding(0,2,0,6); $defaultFlow.Dock='Top'

    $customHdr=New-Object System.Windows.Forms.Label; $customHdr.Text='Custom Mapping (1:1 with Default)'; $customHdr.AutoSize=$true; $customHdr.ForeColor=[System.Drawing.SystemColors]::ControlText
    $customFlow=New-Object System.Windows.Forms.FlowLayoutPanel; $customFlow.Name='customFlowPalette'; $customFlow.AutoSize=$true; $customFlow.WrapContents=$true; $customFlow.Margin=New-Object System.Windows.Forms.Padding(0,2,0,6); $customFlow.Dock='Top'

    $mapInfo=New-Object System.Windows.Forms.Label; $mapInfo.Text='1) Click a default color. 2) Pick target with Draw Color picker. 3) Click matching custom box.'; $mapInfo.AutoSize=$true; $mapInfo.ForeColor=[System.Drawing.SystemColors]::ControlText; $mapInfo.MaximumSize=New-Object System.Drawing.Size(520,0)

    $mapRow=New-Object System.Windows.Forms.FlowLayoutPanel; $mapRow.AutoSize=$true; $mapRow.WrapContents=$false; $mapRow.Dock='Top'
    $analyzeBtn=New-Object System.Windows.Forms.Button; $analyzeBtn.Text='Re-analyze Strip'; $analyzeBtn.Width=108
    $clearCustomBtn=New-Object System.Windows.Forms.Button; $clearCustomBtn.Text='Clear Mapping'; $clearCustomBtn.Width=98
    $applyMapBtn=New-Object System.Windows.Forms.Button; $applyMapBtn.Name='applyMapBtn'; $applyMapBtn.Text='Apply Map to Strip'; $applyMapBtn.Width=120; $applyMapBtn.Enabled=$false
    $script:integratedApplyButton=$applyMapBtn
    $script:integratedDefaultFlow=$defaultFlow
    $script:integratedCustomFlow=$customFlow
    foreach($c in @($analyzeBtn,$clearCustomBtn,$applyMapBtn)){ [void]$mapRow.Controls.Add($c) }

    $saveRow=New-Object System.Windows.Forms.FlowLayoutPanel; $saveRow.AutoSize=$true; $saveRow.WrapContents=$false; $saveRow.Dock='Top'
    foreach($c in @($saveBtn,$backBtn)){ [void]$saveRow.Controls.Add($c) }

    foreach($c in @($pathHdr,$pathBox,$frameZoomRow,$toolHdr,$toolRow,$defaultHdr,$defaultFlow,$drawLabel,$drawSwatch,$drawInfo,$customHdr,$customFlow,$mapInfo,$mapRow,$saveRow,$miniStatus)){
      [void]$pl.Controls.Add($c)
    }

    [void]$paletteHost.Controls.Add($pl)

    $canvasHost=New-Object System.Windows.Forms.Panel; $canvasHost.Dock='Fill'; $canvasHost.AutoScroll=$false; $canvasHost.BackColor=[System.Drawing.Color]::FromArgb(30,30,30)
    $canvas=New-Object System.Windows.Forms.PictureBox; $canvas.SizeMode='Normal'; $canvas.BackColor=[System.Drawing.Color]::FromArgb(22,22,22); $canvas.Cursor=[System.Windows.Forms.Cursors]::Cross
    [void]$canvasHost.Controls.Add($canvas)

    [void]$split.Panel1.Controls.Add($paletteHost)
    [void]$split.Panel2.Controls.Add($canvasHost)
    [void]$integratedEditorHost.Controls.Add($split)

    foreach($b in @($prevFrameBtn,$nextFrameBtn,$zoomOutBtn,$zoomInBtn,$saveBtn,$backBtn,$analyzeBtn,$clearCustomBtn,$applyMapBtn)){
      $b.UseVisualStyleBackColor=$true
      $b.FlatStyle='Standard'
      $b.ForeColor=[System.Drawing.SystemColors]::ControlText
      $b.BackColor=[System.Drawing.SystemColors]::Control
    }

    $applyEditorSplit = {
      $want = [Math]::Max(300, [Math]::Min(460, [int]($integratedEditorHost.ClientSize.Width * 0.30)))
      $maxAllowed = [Math]::Max($split.Panel1MinSize, $split.Width - 180)
      if ($maxAllowed -gt $split.Panel1MinSize) {
        $split.SplitterDistance = [Math]::Min($want, $maxAllowed)
      } else {
        $split.SplitterDistance = $split.Panel1MinSize
      }
    }.GetNewClosure()

    $integratedEditorHost.Add_Resize({ $applyEditorSplit.Invoke() }.GetNewClosure())

    $splitReadyTimer = New-Object System.Windows.Forms.Timer
    $splitReadyTimer.Interval = 220
    $splitReadyTimer.Add_Tick({
      $splitReadyTimer.Stop()
      $splitReadyTimer.Dispose()
      $applyEditorSplit.Invoke()
    }.GetNewClosure())
    $splitReadyTimer.Start()

    $editorState=[pscustomobject]@{
      DrawColor=[System.Drawing.Color]::FromArgb(255,$script:lastDrawColor.R,$script:lastDrawColor.G,$script:lastDrawColor.B)
      HoverPx=-1
      HoverPy=-1
    }
    $script:integratedSelectedIndex=-1
    $script:integratedMapApplied=$false
    $script:integratedDrawColor=[System.Drawing.Color]::FromArgb(255,$script:lastDrawColor.R,$script:lastDrawColor.G,$script:lastDrawColor.B)
    $script:integratedDrawArgb=[int]$script:integratedDrawColor.ToArgb()
    $script:integratedActiveMapArgb=[int]$script:integratedDrawArgb
    $global:GlorgingActiveMapArgb=[int]$script:integratedDrawArgb
    $global:GlorgingActiveMapR=[int]$script:integratedDrawColor.R
    $global:GlorgingActiveMapG=[int]$script:integratedDrawColor.G
    $global:GlorgingActiveMapB=[int]$script:integratedDrawColor.B
    $script:integratedTargetArgb=[int]$script:integratedDrawArgb
    $script:integratedSelectedSourceArgb=[int]$script:integratedDrawArgb
    $script:integratedPickedArgb=[int]$script:integratedDrawArgb
    $script:integratedHasPickedColor=$false
    $script:integratedColorSource='default'
    $script:integratedPickerPrimary=$false
    $script:integratedPaletteCount=0
    $script:integratedDefaultColors=@()
    $script:integratedApplyReady=$false
    $drawSwatch.BackColor=$script:integratedDrawColor
    $drawColorDialog=New-Object System.Windows.Forms.ColorDialog
    $drawColorDialog.FullOpen=$true
    $drawColorDialog.AnyColor=$true
    $drawColorDialog.SolidColorOnly=$false
    Set-ColorDialogPaletteSafe -dialog $drawColorDialog -colors $script:customPalette

    $mouseDown=$false
    $dispBmp=$null
    $lastRenderZoom=[int]$zoomPick.Value
    $syncingZoom=$false
    $lastPaintMsg=''
    $defaultPalette=New-Object 'System.Collections.Generic.List[int]'
    $mappedTargets=@{}
    $mappedFilled=@{}
    $script:integratedUiFilledSlots=@{}
    $script:integratedUiPaletteCount=0
    $script:integratedDefaultPalette=$defaultPalette
    $script:integratedMappedTargets=$mappedTargets
    $script:integratedMappedFilled=$mappedFilled

    $colorToHex={ param([System.Drawing.Color]$c) ('#{0:X2}{1:X2}{2:X2}' -f $c.R,$c.G,$c.B) }.GetNewClosure()
    $syncActiveEditorColor={
      param([System.Drawing.Color]$c,[string]$source)
      $safe=[System.Drawing.Color]::FromArgb(255,[int]$c.R,[int]$c.G,[int]$c.B)
      $script:integratedDrawColor=$safe
      $script:lastDrawColor=$safe
      $script:integratedDrawArgb=[int]$safe.ToArgb()
      $script:integratedActiveMapArgb=[int]$safe.ToArgb()
      $global:GlorgingActiveMapArgb=[int]$safe.ToArgb()
      $global:GlorgingActiveMapR=[int]$safe.R
      $global:GlorgingActiveMapG=[int]$safe.G
      $global:GlorgingActiveMapB=[int]$safe.B
      $script:integratedTargetArgb=[int]$safe.ToArgb()
      $script:integratedPickedArgb=[int]$safe.ToArgb()
      $drawSwatch.BackColor=$safe
      $drawInfo.Text=("#{0:X2}{1:X2}{2:X2}" -f $safe.R,$safe.G,$safe.B)
      try { $drawColorDialog.Color=$safe } catch {}
      Write-PreviewLog ("PaletteActiveColor source={0} color=#{1:X2}{2:X2}{3:X2}" -f $source,$safe.R,$safe.G,$safe.B)
    }.GetNewClosure()
    $setDrawColor={
      param([System.Drawing.Color]$c)
      try {
        $safe=[System.Drawing.Color]::FromArgb(255,[int]$c.R,[int]$c.G,[int]$c.B)
        $script:integratedDrawColor=$safe
        $script:integratedDrawArgb=[int]$safe.ToArgb()
        $script:integratedActiveMapArgb=[int]$safe.ToArgb()
        $global:GlorgingActiveMapArgb=[int]$safe.ToArgb()
        $global:GlorgingActiveMapR=[int]$safe.R
        $global:GlorgingActiveMapG=[int]$safe.G
        $global:GlorgingActiveMapB=[int]$safe.B
        $script:integratedTargetArgb=[int]$safe.ToArgb()
        $script:integratedPickedArgb=[int]$safe.ToArgb()
        if($script:integratedDrawSwatch -is [System.Windows.Forms.Control]){ $script:integratedDrawSwatch.BackColor=$safe }
        if($script:integratedDrawInfo -is [System.Windows.Forms.Control]){ $script:integratedDrawInfo.Text=("#{0:X2}{1:X2}{2:X2}" -f $safe.R,$safe.G,$safe.B) }
        $script:lastDrawColor=$safe
        Write-PreviewLog ("setDrawColor => #{0:X2}{1:X2}{2:X2}" -f $safe.R,$safe.G,$safe.B)
      } catch {
        Write-PreviewLog ("setDrawColor ERROR: {0}" -f $_.Exception.Message)
      }
    }.GetNewClosure()
    $setMapSlot={
      param([int]$slot,[System.Drawing.Color]$color)
      try {
        $mappedTargets[$slot]=[int]$color.ToArgb()
        $mappedFilled[$slot]=$true
        Write-PreviewLog ("setMapSlot ok slot={0} argb={1}" -f $slot,[int]$color.ToArgb())
      } catch {
        Write-PreviewLog ("setMapSlot ERROR slot={0}: {1}" -f $slot,$_.Exception.Message)
        throw
      }
    }.GetNewClosure()

    $setApplyEnabled={
      param([bool]$enabled)
      $btn=$script:integratedApplyButton
      if($btn -is [System.Windows.Forms.Button]){
        $btn.Enabled=$enabled
        return
      }
      if($form -is [System.Windows.Forms.Form]){
        $foundBtns=$form.Controls.Find('applyMapBtn',$true)
        if(($null -ne $foundBtns) -and ($foundBtns.Count -gt 0) -and ($foundBtns[0] -is [System.Windows.Forms.Button])){
          $script:integratedApplyButton=$foundBtns[0]
          $foundBtns[0].Enabled=$enabled
          return
        }
      }
      $typeName=if($null -eq $btn){'<null>'}else{$btn.GetType().FullName}
      Write-PreviewLog ("setApplyEnabled missing button type={0}" -f $typeName)
    }.GetNewClosure()
    $getApplyEnabled={
      $btn=$script:integratedApplyButton
      if($btn -is [System.Windows.Forms.Button]){ return [bool]$btn.Enabled }
      return $false
    }.GetNewClosure()
    $updateApplyEnabled={
      $count=[int]$script:integratedUiPaletteCount
      if($count -le 0){
        $count=[Math]::Min([int]$defaultFlow.Controls.Count,[int]$customFlow.Controls.Count)
      }
      $filled=if($null -ne $script:integratedUiFilledSlots){$script:integratedUiFilledSlots}else{@{}}
      $isComplete=($count -gt 0)
      if($isComplete){
        for($i=0;$i -lt $count;$i++){
          if(($filled -isnot [System.Collections.IDictionary]) -or (-not $filled.ContainsKey($i)) -or (-not [bool]$filled[$i])){ $isComplete=$false; break }
        }
      }
      $null=$setApplyEnabled.Invoke([bool]$isComplete)
      Write-PreviewLog ("updateApplyEnabled count={0} enabled={1}" -f $count,$isComplete)
    }.GetNewClosure()
    $invokeUpdateApplyEnabled={
      if($updateApplyEnabled -is [scriptblock]){
        $null=$updateApplyEnabled.Invoke()
        return
      }
      $count=[Math]::Min([int]$defaultFlow.Controls.Count,[int]$customFlow.Controls.Count)
      $filled=if(($script:integratedUiFilledSlots -is [System.Collections.IDictionary])){$script:integratedUiFilledSlots}else{@{}}
      $isComplete=($count -gt 0)
      if($isComplete){
        for($i=0;$i -lt $count;$i++){
          if((-not $filled.ContainsKey($i)) -or (-not [bool]$filled[$i])){ $isComplete=$false; break }
        }
      }
      $null=$setApplyEnabled.Invoke([bool]$isComplete)
      Write-PreviewLog ("invokeUpdateApplyEnabled fallback count={0} enabled={1}" -f $count,$isComplete)
    }.GetNewClosure()
    $refreshSelectionVisuals={ }.GetNewClosure()
    $renderDefaultPalette={
      foreach($ctl in @($defaultFlow.Controls)){$ctl.Dispose()}
      $defaultFlow.Controls.Clear()
      $selectedIdx=if(($null -ne $script:integratedSelectedIndex) -and ($script:integratedSelectedIndex -is [int])){[int]$script:integratedSelectedIndex}else{-1}
      for($i=0;$i -lt $defaultPalette.Count;$i++){
        $argb=[int]$defaultPalette.Item($i)
        $btn=New-Object System.Windows.Forms.Button
        $btn.Width=22; $btn.Height=22; $btn.Margin=New-Object System.Windows.Forms.Padding(2)
        $btn.FlatStyle='Flat'
        $btn.UseVisualStyleBackColor=$false
        $btn.TabStop=$false
        $btn.FlatAppearance.BorderColor=if($i -eq $selectedIdx){[System.Drawing.Color]::FromArgb(0,160,255)}else{[System.Drawing.Color]::FromArgb(90,90,90)}
        $btn.FlatAppearance.BorderSize=if($i -eq $selectedIdx){3}else{1}
        $btn.BackColor=[System.Drawing.Color]::FromArgb($argb)
        $btn.Tag=[int]$i
        $btn.Cursor=[System.Windows.Forms.Cursors]::Hand
        $btn.Add_MouseDown({
          param($s,$e)
          if($e.Button -ne [System.Windows.Forms.MouseButtons]::Left){ return }
          try {
            Write-PreviewLog ("DefaultMouseDown tag={0} button={1}" -f [string]$s.Tag,[string]$e.Button)
            $idx=[int]$s.Tag
            Write-PreviewLog ("DefaultStep idx={0}" -f $idx)
            $srcColor=[System.Drawing.Color]::FromArgb(255,[int]$s.BackColor.R,[int]$s.BackColor.G,[int]$s.BackColor.B)
            $srcArgb=[int]$srcColor.ToArgb()
            Write-PreviewLog ("DefaultStep argb={0}" -f $srcArgb)
            $script:integratedSelectedIndex=$idx
            for($d=0;$d -lt $defaultFlow.Controls.Count;$d++){
              try { $defaultFlow.Controls[$d].FlatAppearance.BorderColor=if($d -eq $idx){[System.Drawing.Color]::FromArgb(0,160,255)}else{[System.Drawing.Color]::FromArgb(90,90,90)}; $defaultFlow.Controls[$d].FlatAppearance.BorderSize=if($d -eq $idx){3}else{1} } catch {}
            }
            for($c=0;$c -lt $customFlow.Controls.Count;$c++){
              try { $customFlow.Controls[$c].FlatAppearance.BorderColor=if($c -eq $idx){[System.Drawing.Color]::FromArgb(0,160,255)}else{[System.Drawing.Color]::FromArgb(90,90,90)}; $customFlow.Controls[$c].FlatAppearance.BorderSize=if($c -eq $idx){3}else{1} } catch {}
            }
            Write-PreviewLog ("selectMapIndex set={0}" -f $idx)
            Write-PreviewLog "DefaultStep selectMapIndex done"
            $script:integratedSelectedSourceArgb=[int]$srcColor.ToArgb()
            $script:integratedHasPickedColor=$false
            $script:integratedColorSource='default'
            $script:integratedPickerPrimary=$false
            $safeSrc=[System.Drawing.Color]::FromArgb(255,[int]$srcColor.R,[int]$srcColor.G,[int]$srcColor.B)
            $script:integratedDrawColor=$safeSrc
            $script:lastDrawColor=$safeSrc
            $script:integratedDrawArgb=[int]$safeSrc.ToArgb()
            if($script:integratedDrawSwatch -is [System.Windows.Forms.Control]){ $script:integratedDrawSwatch.BackColor=$safeSrc }
            if($script:integratedDrawInfo -is [System.Windows.Forms.Control]){ $script:integratedDrawInfo.Text=("#{0:X2}{1:X2}{2:X2}" -f $safeSrc.R,$safeSrc.G,$safeSrc.B) }
            $script:integratedActiveMapArgb=[int]$srcColor.ToArgb()
            $global:GlorgingActiveMapArgb=[int]$srcColor.ToArgb()
            $global:GlorgingActiveMapR=[int]$srcColor.R
            $global:GlorgingActiveMapG=[int]$srcColor.G
            $global:GlorgingActiveMapB=[int]$srcColor.B
            try { if($drawColorDialog -is [System.Windows.Forms.ColorDialog]){ $drawColorDialog.Color=$srcColor } } catch {}
            Write-PreviewLog ("PaletteActiveColor source=default color=#{0:X2}{1:X2}{2:X2}" -f $srcColor.R,$srcColor.G,$srcColor.B)
            Write-PreviewLog "DefaultStep set script colors done"
            Write-PreviewLog ("DefaultSelect index={0} color=#{1:X2}{2:X2}{3:X2}" -f $idx,$srcColor.R,$srcColor.G,$srcColor.B)
            try { if($miniStatus -is [System.Windows.Forms.Control]){ $miniStatus.Text=("Selected source {0}: #{1:X2}{2:X2}{3:X2}" -f [int]$script:integratedSelectedIndex,$srcColor.R,$srcColor.G,$srcColor.B) } } catch {}
            Write-PreviewLog "DefaultStep direct-ui done"
          } catch {
            Write-PreviewLog ("DefaultSelect ERROR: {0}" -f $_.Exception.ToString())
            try { if($miniStatus -is [System.Windows.Forms.Control]){ $miniStatus.Text=("Default palette click failed: {0}" -f $_.Exception.Message) } } catch {}
          }
        }.GetNewClosure())
        [void]$defaultFlow.Controls.Add($btn)
      }
    }.GetNewClosure()

    $renderCustomPalette={
      foreach($ctl in @($customFlow.Controls)){$ctl.Dispose()}
      $customFlow.Controls.Clear()
      $selectedIdx=if(($null -ne $script:integratedSelectedIndex) -and ($script:integratedSelectedIndex -is [int])){[int]$script:integratedSelectedIndex}else{-1}
      for($i=0;$i -lt $defaultPalette.Count;$i++){
        $mt=if($null -ne $script:integratedMappedTargets){$script:integratedMappedTargets}else{$mappedTargets}
        $mf=if($null -ne $script:integratedMappedFilled){$script:integratedMappedFilled}else{$mappedFilled}
        $targetArgb=if(($mt -is [System.Collections.IDictionary]) -and $mt.ContainsKey($i)){[int]$mt[$i]}else{0}
        $isFilled=((($mf -is [System.Collections.IDictionary]) -and $mf.ContainsKey($i)) -and [bool]$mf[$i])
        $btn=New-Object System.Windows.Forms.Button
        $btn.Width=22; $btn.Height=22; $btn.Margin=New-Object System.Windows.Forms.Padding(2)
        $btn.FlatStyle='Flat'
        $btn.UseVisualStyleBackColor=$false
        $btn.TabStop=$false
        $btn.FlatAppearance.BorderColor=if($i -eq $selectedIdx){[System.Drawing.Color]::FromArgb(0,160,255)}else{[System.Drawing.Color]::FromArgb(90,90,90)}
        $btn.FlatAppearance.BorderSize=if($i -eq $selectedIdx){3}else{1}
        $srcArgbForSlot=if($i -lt $defaultPalette.Count){ [int]$defaultPalette.Item($i) } else { [int][System.Drawing.Color]::Black.ToArgb() }
        $uiFilled=(($null -ne $script:integratedUiFilledSlots) -and $script:integratedUiFilledSlots.ContainsKey($i) -and [bool]$script:integratedUiFilledSlots[$i])
        $btn.Tag=@{ Index=[int]$i; SourceArgb=[int]$srcArgbForSlot; Filled=[bool]$uiFilled; TargetArgb=[int]$targetArgb }
        if($isFilled){
          $btn.BackColor=[System.Drawing.Color]::FromArgb($targetArgb)
          $btn.Text=''
        } else {
          $btn.BackColor=[System.Drawing.Color]::FromArgb(250,250,250)
          $btn.Text=' '
        }
        $btn.Cursor=[System.Windows.Forms.Cursors]::Hand
        $btn.Add_MouseDown({
          param($s,$e)
          if($e.Button -ne [System.Windows.Forms.MouseButtons]::Left){ return }
          try {
            Write-PreviewLog ("CustomMouseDown tag={0} button={1}" -f [string]$s.Tag,[string]$e.Button)
            $slot=[int]$s.Tag.Index
            Write-PreviewLog ("CustomStep slot={0}" -f $slot)
            $df=if($script:integratedDefaultFlow -is [System.Windows.Forms.FlowLayoutPanel]){$script:integratedDefaultFlow}else{$null}
            $cf=if($script:integratedCustomFlow -is [System.Windows.Forms.FlowLayoutPanel]){$script:integratedCustomFlow}else{$null}
            if(($null -eq $cf) -and ($s.Parent -is [System.Windows.Forms.FlowLayoutPanel])){ $cf=[System.Windows.Forms.FlowLayoutPanel]$s.Parent }
            if(($null -eq $df) -and ($form -is [System.Windows.Forms.Form])){
              $foundDf=$form.Controls.Find('defaultFlowPalette',$true)
              if(($null -ne $foundDf) -and ($foundDf.Count -gt 0) -and ($foundDf[0] -is [System.Windows.Forms.FlowLayoutPanel])){ $df=[System.Windows.Forms.FlowLayoutPanel]$foundDf[0]; $script:integratedDefaultFlow=$df }
            }
            if(($null -eq $cf) -and ($form -is [System.Windows.Forms.Form])){
              $foundCf=$form.Controls.Find('customFlowPalette',$true)
              if(($null -ne $foundCf) -and ($foundCf.Count -gt 0) -and ($foundCf[0] -is [System.Windows.Forms.FlowLayoutPanel])){ $cf=[System.Windows.Forms.FlowLayoutPanel]$foundCf[0]; $script:integratedCustomFlow=$cf }
            }
            $paletteCount=[int]$script:integratedUiPaletteCount
            if($paletteCount -le 0 -and $defaultPalette.Count -gt 0){ $paletteCount=[int]$defaultPalette.Count }
            if($paletteCount -le 0){
              $dc=if($df -is [System.Windows.Forms.FlowLayoutPanel]){[int]$df.Controls.Count}else{0}
              $cc=if($cf -is [System.Windows.Forms.FlowLayoutPanel]){[int]$cf.Controls.Count}else{0}
              if($dc -gt 0 -and $cc -gt 0){ $paletteCount=[Math]::Min($dc,$cc) }
              elseif($cc -gt 0){ $paletteCount=$cc }
              elseif($dc -gt 0){ $paletteCount=$dc }
            }
            $dfCount=0
            if($df -is [System.Windows.Forms.FlowLayoutPanel]){ $dfCount=[int]$df.Controls.Count }
            $cfCount=0
            if($cf -is [System.Windows.Forms.FlowLayoutPanel]){ $cfCount=[int]$cf.Controls.Count }
            Write-PreviewLog ("CustomStep counts ui={0} defaultList={1} df={2} cf={3} used={4}" -f [int]$script:integratedUiPaletteCount,[int]$defaultPalette.Count,$dfCount,$cfCount,$paletteCount)
            $r=[int]$global:GlorgingActiveMapR
            $g=[int]$global:GlorgingActiveMapG
            $b=[int]$global:GlorgingActiveMapB
            Write-PreviewLog ("CustomStep activeRGB=({0},{1},{2}) activeMapArgbGlobal={3} activeMapArgbScript={4}" -f $r,$g,$b,[int]$global:GlorgingActiveMapArgb,[int]$script:integratedActiveMapArgb)
            if($r -eq 0 -and $g -eq 0 -and $b -eq 0){
              if(($null -ne $s.Tag) -and ($null -ne $s.Tag.SourceArgb)){
                $srcColor=[System.Drawing.Color]::FromArgb([int]$s.Tag.SourceArgb)
                $r=[int]$srcColor.R; $g=[int]$srcColor.G; $b=[int]$srcColor.B
              } elseif($slot -lt $defaultFlow.Controls.Count){
                $dc=$defaultFlow.Controls[$slot].BackColor
                $r=[int]$dc.R; $g=[int]$dc.G; $b=[int]$dc.B
              } elseif([int]$script:integratedSelectedSourceArgb -ne 0){
                $sc=[System.Drawing.Color]::FromArgb([int]$script:integratedSelectedSourceArgb)
                $r=[int]$sc.R; $g=[int]$sc.G; $b=[int]$sc.B
              }
            }
            $currentDraw=[System.Drawing.Color]::FromArgb(255,$r,$g,$b)
            Write-PreviewLog ("CustomStep drawArgb={0}" -f [int]$currentDraw.ToArgb())
            Write-PreviewLog ("CustomSelect slot={0} draw=#{1:X2}{2:X2}{3:X2}" -f $slot,$currentDraw.R,$currentDraw.G,$currentDraw.B)
            $targetColor=[System.Drawing.Color]::FromArgb(255,$currentDraw.R,$currentDraw.G,$currentDraw.B)
            Write-PreviewLog "CustomStep targetColor built"
            $slotTag=if($s.Tag -is [System.Collections.IDictionary]){ $s.Tag } else { @{} }
            $slotWasFilledByTag=(($slotTag -is [System.Collections.IDictionary]) -and $slotTag.ContainsKey('Filled') -and [bool]$slotTag['Filled'])
            $emptyArgb=[System.Drawing.Color]::FromArgb(250,250,250).ToArgb()
            $slotHasMappedUi=$false
            try {
              if(($s -is [System.Windows.Forms.Control]) -and ($s.Text -eq '') -and ($s.BackColor.ToArgb() -ne $emptyArgb)){
                $slotHasMappedUi=$true
              }
            } catch {}
            $slotWasFilled=($slotWasFilledByTag -or $slotHasMappedUi)
            $pickerPrimary=[bool]$script:integratedPickerPrimary
            $applyToSlot=($pickerPrimary -or (-not $slotWasFilled))
            Write-PreviewLog ("CustomStep decision pickerPrimary={0} slotWasFilled={1} applyToSlot={2}" -f $pickerPrimary,$slotWasFilled,$applyToSlot)
            if($applyToSlot){
              $selectedColor=$targetColor
            } else {
              if(($slotTag -is [System.Collections.IDictionary]) -and $slotTag.ContainsKey('TargetArgb')){
                $selectedColor=[System.Drawing.Color]::FromArgb([int]$slotTag['TargetArgb'])
              } elseif($s -is [System.Windows.Forms.Control]){
                $selectedColor=[System.Drawing.Color]::FromArgb(255,[int]$s.BackColor.R,[int]$s.BackColor.G,[int]$s.BackColor.B)
              } else {
                $selectedColor=$targetColor
              }
            }
            $script:integratedHasPickedColor=$true
            $script:integratedColorSource='custom'
            $script:integratedPickerPrimary=$false
            $safeTgt=[System.Drawing.Color]::FromArgb(255,[int]$selectedColor.R,[int]$selectedColor.G,[int]$selectedColor.B)
            $script:integratedDrawColor=$safeTgt
            $script:lastDrawColor=$safeTgt
            $script:integratedDrawArgb=[int]$safeTgt.ToArgb()
            if($script:integratedDrawSwatch -is [System.Windows.Forms.Control]){ $script:integratedDrawSwatch.BackColor=$safeTgt }
            if($script:integratedDrawInfo -is [System.Windows.Forms.Control]){ $script:integratedDrawInfo.Text=("#{0:X2}{1:X2}{2:X2}" -f $safeTgt.R,$safeTgt.G,$safeTgt.B) }
            $script:integratedActiveMapArgb=[int]$selectedColor.ToArgb()
            $global:GlorgingActiveMapArgb=[int]$selectedColor.ToArgb()
            $global:GlorgingActiveMapR=[int]$selectedColor.R
            $global:GlorgingActiveMapG=[int]$selectedColor.G
            $global:GlorgingActiveMapB=[int]$selectedColor.B
            try { if($drawColorDialog -is [System.Windows.Forms.ColorDialog]){ $drawColorDialog.Color=$selectedColor } } catch {}
            Write-PreviewLog ("PaletteActiveColor source=custom color=#{0:X2}{1:X2}{2:X2} applyToSlot={3}" -f $selectedColor.R,$selectedColor.G,$selectedColor.B,$applyToSlot)
            $script:integratedSelectedIndex=$slot
            $dfLoopCount=0
            if($df -is [System.Windows.Forms.FlowLayoutPanel]){ $dfLoopCount=[int]$df.Controls.Count }
            for($d=0;$d -lt $dfLoopCount;$d++){
              try { $df.Controls[$d].FlatAppearance.BorderColor=if($d -eq $slot){[System.Drawing.Color]::FromArgb(0,160,255)}else{[System.Drawing.Color]::FromArgb(90,90,90)}; $df.Controls[$d].FlatAppearance.BorderSize=if($d -eq $slot){3}else{1} } catch {}
            }
            $cfLoopCount=0
            if($cf -is [System.Windows.Forms.FlowLayoutPanel]){ $cfLoopCount=[int]$cf.Controls.Count }
            for($c=0;$c -lt $cfLoopCount;$c++){
              try { $cf.Controls[$c].FlatAppearance.BorderColor=if($c -eq $slot){[System.Drawing.Color]::FromArgb(0,160,255)}else{[System.Drawing.Color]::FromArgb(90,90,90)}; $cf.Controls[$c].FlatAppearance.BorderSize=if($c -eq $slot){3}else{1} } catch {}
            }
            Write-PreviewLog ("selectMapIndex set={0}" -f $slot)
            Write-PreviewLog "CustomStep selectMapIndex done"
            if($applyToSlot){
              if($null -eq $s.Tag){ $s.Tag=@{} }
              $s.Tag.Filled=$true
              $s.Tag.TargetArgb=[int]$selectedColor.ToArgb()
              if($null -eq $script:integratedUiFilledSlots){ $script:integratedUiFilledSlots=@{} }
              $script:integratedUiFilledSlots[$slot]=$true
              Write-PreviewLog "CustomStep mapped tag set"
              try { $s.BackColor=$selectedColor } catch {}
              try { $s.Text='' } catch {}
              Write-PreviewLog "CustomStep sender ui set"
            } else {
              Write-PreviewLog "CustomStep select-only (filled slot, picker not primary)"
            }
            Write-PreviewLog "CustomStep apply-check start"
            $countNow=[int]$paletteCount
            $isComplete=($countNow -gt 0)
            $filledCount=0
            if($cf -is [System.Windows.Forms.FlowLayoutPanel]){
              foreach($ctlFilled in @($cf.Controls)){
                if($ctlFilled -isnot [System.Windows.Forms.Button]){ continue }
                $tagFilled=$ctlFilled.Tag
                $ok=$false
                if(($tagFilled -is [System.Collections.IDictionary]) -and $tagFilled.ContainsKey('Filled')){
                  $ok=[bool]$tagFilled['Filled']
                }
                if($ok){ $filledCount++ }
              }
            }
            if($filledCount -lt $countNow){ $isComplete=$false }
            $applyBtnLocal=$null
            if($script:integratedApplyButton -is [System.Windows.Forms.Button]){ $applyBtnLocal=$script:integratedApplyButton }
            if(($null -eq $applyBtnLocal) -and ($form -is [System.Windows.Forms.Form])){
              $foundBtns=$form.Controls.Find('applyMapBtn',$true)
              if(($null -ne $foundBtns) -and ($foundBtns.Count -gt 0) -and ($foundBtns[0] -is [System.Windows.Forms.Button])){
                $applyBtnLocal=$foundBtns[0]
                $script:integratedApplyButton=$applyBtnLocal
              }
            }
            if($applyBtnLocal -is [System.Windows.Forms.Button]){
              $applyBtnLocal.Enabled=$isComplete
            } else {
              Write-PreviewLog "CustomStep apply button missing in inline setter"
            }
            Write-PreviewLog ("CustomStep apply-check count={0} enabled={1}" -f $countNow,$isComplete)
            $script:integratedApplyReady=$isComplete
            Write-PreviewLog ("CustomStep applyEnabled={0}" -f $isComplete)
            $srcRef = if(($slot -lt $script:integratedDefaultColors.Count) -and ($script:integratedDefaultColors.Count -gt 0)){
              [System.Drawing.Color]::FromArgb([int]$script:integratedDefaultColors[$slot])
            } elseif(($null -ne $s.Tag) -and ($null -ne $s.Tag.SourceArgb)){
              [System.Drawing.Color]::FromArgb([int]$s.Tag.SourceArgb)
            } elseif(($df -is [System.Windows.Forms.FlowLayoutPanel]) -and ($slot -lt $df.Controls.Count)){
              [System.Drawing.Color]::FromArgb(255,$df.Controls[$slot].BackColor.R,$df.Controls[$slot].BackColor.G,$df.Controls[$slot].BackColor.B)
            } else {
              [System.Drawing.Color]::FromArgb(255,0,0,0)
            }
            if($applyToSlot){
              try { $miniStatus.Text=("Mapped #{0:X2}{1:X2}{2:X2} -> #{3:X2}{4:X2}{5:X2} ({6}/{7})" -f $srcRef.R,$srcRef.G,$srcRef.B,$selectedColor.R,$selectedColor.G,$selectedColor.B,$filledCount,$countNow) } catch {}
            } else {
              try { $miniStatus.Text=("Selected custom color {0}: #{1:X2}{2:X2}{3:X2}" -f $slot,$selectedColor.R,$selectedColor.G,$selectedColor.B) } catch {}
            }
            Write-PreviewLog "CustomStep status set"
            Write-PreviewLog ("CustomSelect mapped slot={0} argb={1} filled={2}/{3} applied={4}" -f $slot,[int]$selectedColor.ToArgb(),$filledCount,$countNow,$applyToSlot)
            Write-PreviewLog "CustomStep direct-map done"
          } catch {
            Write-PreviewLog ("CustomSelect ERROR: {0}" -f $_.Exception.ToString())
            try { if($miniStatus -is [System.Windows.Forms.Control]){ $miniStatus.Text=("Custom mapping click failed: {0}" -f $_.Exception.Message) } } catch {}
          }
        }.GetNewClosure())
        [void]$customFlow.Controls.Add($btn)
      }
    }.GetNewClosure()

    $analyzePalette={
      Write-PreviewLog "AnalyzeStrip clicked"
      $counts=@{}
      $oldTargets=@{}
      foreach($k in $mappedTargets.Keys){ $oldTargets[[int]$k]=[int]$mappedTargets[$k] }
      $oldFilled=@{}
      foreach($k in $mappedFilled.Keys){ $oldFilled[[int]$k]=[bool]$mappedFilled[$k] }
      $paletteSource=$srcBmp
      $maxY=[int]($editFrameCount*[int]$spec.FrameH)
      for($y=0;$y -lt $maxY;$y++){
        for($x=0;$x -lt [int]$spec.FrameW;$x++){
          $px=$paletteSource.GetPixel($x,$y)
          if($px.A -le 0){continue}
          $argb=[int]([System.Drawing.Color]::FromArgb(255,$px.R,$px.G,$px.B).ToArgb())
          if($counts.ContainsKey($argb)){$counts[$argb]=[int]$counts[$argb]+1}else{$counts[$argb]=1}
        }
      }
      $defaultPalette.Clear()
      foreach($k in @($counts.Keys | Sort-Object -Descending -Property @{Expression={ $counts[$_] }}, @{Expression={$_}})){
        [void]$defaultPalette.Add([int]$k)
      }
      $script:integratedDefaultColors=@()
      for($ii=0;$ii -lt $defaultPalette.Count;$ii++){ $script:integratedDefaultColors += [int]$defaultPalette.Item($ii) }
      $script:integratedPaletteCount=[int]$defaultPalette.Count
      $script:integratedUiPaletteCount=[int]$defaultPalette.Count
      $script:integratedUiFilledSlots=@{}
      $mappedTargets=@{}
      $mappedFilled=@{}
      $script:integratedDefaultPalette=$defaultPalette
      $script:integratedMappedTargets=$mappedTargets
      $script:integratedMappedFilled=$mappedFilled
      for($i=0;$i -lt $defaultPalette.Count;$i++){
        if($oldTargets.ContainsKey($i) -and $oldFilled.ContainsKey($i)){
          $mappedTargets[$i]=[int]$oldTargets[$i]
          $mappedFilled[$i]=[bool]$oldFilled[$i]
        } else {
          $mappedTargets[$i]=0
          $mappedFilled[$i]=$false
        }
      }
      $script:integratedSelectedIndex=-1
      $mapInfo.Text='1) Click a default color. 2) Pick target with Draw Color picker. 3) Click matching custom box.'
      & $renderDefaultPalette
      & $renderCustomPalette
      $null=$invokeUpdateApplyEnabled.Invoke()
      $miniStatus.Text="Palette analyzed: $($defaultPalette.Count) colors from all $editFrameCount frame(s), source=current strip."
      Write-PreviewLog ("AnalyzeStrip result colors={0}" -f $defaultPalette.Count)
    }.GetNewClosure()

    $render={
      if($null -ne $dispBmp){$dispBmp.Dispose();$dispBmp=$null}
      $zoom=[int]$zoomPick.Value; $w=[int]$spec.FrameW; $h=[int]$spec.FrameH; $frame=[int]$framePick.Value
      if($fitCheck.Checked){
        $availW=[Math]::Max($canvasHost.ClientSize.Width-40,1); $availH=[Math]::Max($canvasHost.ClientSize.Height-40,1)
        $zw=[Math]::Floor($availW/$w); $zh=[Math]::Floor($availH/$h); $autoZoom=[Math]::Max(1,[Math]::Min($zw,$zh))
        $zoom=[int][Math]::Max([int]$zoomPick.Minimum,[Math]::Min([int]$zoomPick.Maximum,$autoZoom))
        if([int]$zoomPick.Value -ne $zoom){$syncingZoom=$true;$zoomPick.Value=$zoom;$syncingZoom=$false}
      }
      $dispBmp=New-Object System.Drawing.Bitmap(($w*$zoom),($h*$zoom)); $g=[System.Drawing.Graphics]::FromImage($dispBmp)
      try{
        $g.InterpolationMode='NearestNeighbor'; $g.PixelOffsetMode='HighQuality'; $g.SmoothingMode='None'; $g.Clear([System.Drawing.Color]::FromArgb(18,18,18))
        $checkA=[System.Drawing.Color]::FromArgb(40,40,40); $checkB=[System.Drawing.Color]::FromArgb(55,55,55)
        for($py=0;$py -lt $h;$py++){ for($px=0;$px -lt $w;$px++){ $c=if((($px+$py)%2)-eq 0){$checkA}else{$checkB}; $br=New-Object System.Drawing.SolidBrush($c); try{$g.FillRectangle($br,$px*$zoom,$py*$zoom,$zoom,$zoom)} finally{$br.Dispose()} } }
        for($py=0;$py -lt $h;$py++){ for($px=0;$px -lt $w;$px++){ $src=$srcBmp.GetPixel($px,$py+($frame*$h)); if($src.A -gt 0){ $br2=New-Object System.Drawing.SolidBrush($src); try{$g.FillRectangle($br2,$px*$zoom,$py*$zoom,$zoom,$zoom)} finally{$br2.Dispose()} } } }
        $pen=New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(45,255,255,255)); try{ for($x=0;$x -le $w;$x++){ $g.DrawLine($pen,$x*$zoom,0,$x*$zoom,$h*$zoom) }; for($y=0;$y -le $h;$y++){ $g.DrawLine($pen,0,$y*$zoom,$w*$zoom,$y*$zoom) } } finally{$pen.Dispose()}
        $border=New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(180,120,180,255),2); try{$g.DrawRectangle($border,0,0,($w*$zoom)-1,($h*$zoom)-1)} finally{$border.Dispose()}
        if($editorState.HoverPx -ge 0 -and $editorState.HoverPx -lt $w -and $editorState.HoverPy -ge 0 -and $editorState.HoverPy -lt $h){ $hoverPen=New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(220,255,224,0),2); try{$g.DrawRectangle($hoverPen,($editorState.HoverPx*$zoom),($editorState.HoverPy*$zoom),$zoom-1,$zoom-1)} finally{$hoverPen.Dispose()} }
      } finally { $g.Dispose() }
      if($null -ne $canvas.Image){$canvas.Image.Dispose()}
      $canvas.Image=$dispBmp; $canvas.Width=$dispBmp.Width; $canvas.Height=$dispBmp.Height
      $canvas.Left=[Math]::Max(8,[int](($canvasHost.ClientSize.Width-$canvas.Width)/2)); $canvas.Top=[Math]::Max(8,[int](($canvasHost.ClientSize.Height-$canvas.Height)/2)); $lastRenderZoom=$zoom
      $frameInfo.Text=("{0}/{1}" -f $frame,[Math]::Max($editFrameCount-1,0)); $miniStatus.Text="Editing $workingPath | frame=$frame zoom=$zoom | hover=($($editorState.HoverPx),$($editorState.HoverPy)) | tools: paint/fill/pick/eraser $lastPaintMsg"
    }.GetNewClosure()

    $toCanvasPoint={ param([int]$mx,[int]$my,[bool]$fromHost) if($fromHost){ [pscustomobject]@{X=($mx-$canvas.Left);Y=($my-$canvas.Top)} } else { [pscustomobject]@{X=$mx;Y=$my} } }.GetNewClosure()

    $applyAt={
      param([int]$mx,[int]$my,[bool]$fromHost)
      $pt=& $toCanvasPoint $mx $my $fromHost; $cx=[int]$pt.X; $cy=[int]$pt.Y; if($cx -lt 0 -or $cy -lt 0 -or $cx -ge $canvas.Width -or $cy -ge $canvas.Height){return}
      $zoom=[int]$lastRenderZoom; $px=[int][Math]::Floor(($cx)/$zoom); $py=[int][Math]::Floor(($cy)/$zoom); if($px -lt 0 -or $px -ge $spec.FrameW -or $py -lt 0 -or $py -ge $spec.FrameH){return}
      try{
        $ay=$py+([int]$framePick.Value*[int]$spec.FrameH)
        if($eyeDropper.Checked){
          $picked=$srcBmp.GetPixel($px,$ay)
          if($picked.A -eq 0){
            $eraser.Checked=$true
          } else {
            $eraser.Checked=$false
            $pick=[System.Drawing.Color]::FromArgb(255,$picked.R,$picked.G,$picked.B)
            & $setDrawColor $pick
          }
          $lastPaintMsg=("| pick x={0} y={1}" -f $px,$py)
        }
        elseif($fillTool.Checked){
          $fillTarget=$srcBmp.GetPixel($px,$ay); $fillReplace=if($eraser.Checked){[System.Drawing.Color]::FromArgb(0,0,0,0)}else{[System.Drawing.Color]::FromArgb(255,[int]$script:integratedDrawColor.R,[int]$script:integratedDrawColor.G,[int]$script:integratedDrawColor.B)}
          if($fillTarget.ToArgb() -ne $fillReplace.ToArgb()){
            $w=[int]$spec.FrameW; $h=[int]$spec.FrameH; $baseY=[int]$framePick.Value*[int]$spec.FrameH
            $q=New-Object 'System.Collections.Generic.Queue[System.Drawing.Point]'; $seen=New-Object 'System.Collections.Generic.HashSet[int]'
            $q.Enqueue([System.Drawing.Point]::new($px,$py))
            while($q.Count -gt 0){
              $pt2=$q.Dequeue(); $x2=[int]$pt2.X; $y2=[int]$pt2.Y
              if($x2 -lt 0 -or $x2 -ge $w -or $y2 -lt 0 -or $y2 -ge $h){continue}
              $k=$y2*$w+$x2; if(-not $seen.Add($k)){continue}
              $yy=$baseY+$y2; $cur=$srcBmp.GetPixel($x2,$yy); if($cur.ToArgb() -ne $fillTarget.ToArgb()){continue}
              $srcBmp.SetPixel($x2,$yy,$fillReplace)
              $q.Enqueue([System.Drawing.Point]::new($x2-1,$y2)); $q.Enqueue([System.Drawing.Point]::new($x2+1,$y2)); $q.Enqueue([System.Drawing.Point]::new($x2,$y2-1)); $q.Enqueue([System.Drawing.Point]::new($x2,$y2+1))
            }
          }
          $lastPaintMsg=("| fill x={0} y={1}" -f $px,$py)
        }
        elseif($eraser.Checked){
          $srcBmp.SetPixel($px,$ay,[System.Drawing.Color]::FromArgb(0,0,0,0)); $lastPaintMsg=("| erase x={0} y={1}" -f $px,$py)
        }
        else {
          $paintColor=$null
          if($script:integratedDrawColor -is [System.Drawing.Color]){
            $paintColor=[System.Drawing.Color]::FromArgb(255,[int]$script:integratedDrawColor.R,[int]$script:integratedDrawColor.G,[int]$script:integratedDrawColor.B)
          } elseif(($global:GlorgingActiveMapR -as [int]) -or ($global:GlorgingActiveMapG -as [int]) -or ($global:GlorgingActiveMapB -as [int])){
            $paintColor=[System.Drawing.Color]::FromArgb(255,[int]$global:GlorgingActiveMapR,[int]$global:GlorgingActiveMapG,[int]$global:GlorgingActiveMapB)
          } elseif([int]$script:integratedSelectedSourceArgb -ne 0){
            $srcC=[System.Drawing.Color]::FromArgb([int]$script:integratedSelectedSourceArgb)
            $paintColor=[System.Drawing.Color]::FromArgb(255,[int]$srcC.R,[int]$srcC.G,[int]$srcC.B)
          } else {
            $paintColor=[System.Drawing.Color]::FromArgb(255,255,128,64)
          }
          $paintSource=[string]$script:integratedColorSource
          if([string]::IsNullOrWhiteSpace($paintSource)){ $paintSource='direct' }
          Write-PreviewLog ("PaintAction color=#{0:X2}{1:X2}{2:X2} source={3}" -f $paintColor.R,$paintColor.G,$paintColor.B,$paintSource)
          $srcBmp.SetPixel($px,$ay,$paintColor); $lastPaintMsg=("| paint x={0} y={1}" -f $px,$py)
        }
      } catch {
        $miniStatus.Text="Edit failed: $($_.Exception.Message)"
        return
      }
      & $render
    }.GetNewClosure()

    $updateHover={
      param([int]$mx,[int]$my,[bool]$fromHost)
      $pt=& $toCanvasPoint $mx $my $fromHost; $cx=[int]$pt.X; $cy=[int]$pt.Y; $newPx=-1; $newPy=-1
      if($cx -ge 0 -and $cy -ge 0 -and $cx -lt $canvas.Width -and $cy -lt $canvas.Height){
        $zoom=[int]$lastRenderZoom; $newPx=[int][Math]::Floor(($cx)/$zoom); $newPy=[int][Math]::Floor(($cy)/$zoom)
        if($newPx -lt 0 -or $newPx -ge $spec.FrameW -or $newPy -lt 0 -or $newPy -ge $spec.FrameH){$newPx=-1;$newPy=-1}
      }
      if($newPx -ne $editorState.HoverPx -or $newPy -ne $editorState.HoverPy){$editorState.HoverPx=$newPx;$editorState.HoverPy=$newPy;& $render}
    }.GetNewClosure()

    $applyMapBtn.Add_Click({
      $dpApply=$defaultFlow.Controls
      $cpApply=$customFlow.Controls
      $isCompleteApply=($cpApply.Count -gt 0 -and $dpApply.Count -eq $cpApply.Count)
      if($isCompleteApply){
        for($k=0;$k -lt $cpApply.Count;$k++){
          $ct=$cpApply[$k]
          $tag=$ct.Tag
          if(($tag -isnot [System.Collections.IDictionary]) -or (-not $tag.ContainsKey('Filled')) -or (-not [bool]$tag['Filled'])){ $isCompleteApply=$false; break }
        }
      }
      if(-not $isCompleteApply){ $miniStatus.Text='Fill all custom mapping slots before applying.'; return }
      $colorMap=@{}
      for($i=0;$i -lt $cpApply.Count;$i++){
        $srcCtl=$dpApply[$i]
        $dstTag=$cpApply[$i].Tag
        if(($null -eq $srcCtl) -or ($dstTag -isnot [System.Collections.IDictionary]) -or (-not $dstTag.ContainsKey('TargetArgb'))){ continue }
        $targetArgb=[int]$dstTag.TargetArgb
        $srcArgb=0
        if($dstTag.ContainsKey('SourceArgb')){
          $srcArgb=[int]$dstTag.SourceArgb
        } else {
          $srcArgb=[int]([System.Drawing.Color]::FromArgb(255,[int]$srcCtl.BackColor.R,[int]$srcCtl.BackColor.G,[int]$srcCtl.BackColor.B).ToArgb())
        }
        $colorMap[$srcArgb]=$targetArgb
        # Support iterative re-apply: if slot was previously applied to another color,
        # allow remapping from that last applied color to the new target.
        if($dstTag.ContainsKey('LastAppliedArgb')){
          $lastApplied=[int]$dstTag.LastAppliedArgb
          if($lastApplied -ne $srcArgb){
            $colorMap[$lastApplied]=$targetArgb
          }
        }
      }
      $changed=0
      $maxY=[int]($editFrameCount*[int]$spec.FrameH)
      for($y=0;$y -lt $maxY;$y++){
        for($x=0;$x -lt [int]$spec.FrameW;$x++){
          $p=$srcBmp.GetPixel($x,$y); if($p.A -le 0){continue}
          $sk=[int]([System.Drawing.Color]::FromArgb(255,$p.R,$p.G,$p.B).ToArgb())
          if(-not $colorMap.ContainsKey($sk)){continue}
          $dst=[System.Drawing.Color]::FromArgb([int]$colorMap[$sk])
          $srcBmp.SetPixel($x,$y,[System.Drawing.Color]::FromArgb($p.A,$dst.R,$dst.G,$dst.B))
          $changed++
        }
      }
      & $render
      $script:integratedMapApplied=$true
      for($i=0;$i -lt $cpApply.Count;$i++){
        $dstTag=$cpApply[$i].Tag
        if(($dstTag -is [System.Collections.IDictionary]) -and $dstTag.ContainsKey('TargetArgb')){
          $dstTag.LastAppliedArgb=[int]$dstTag.TargetArgb
          $cpApply[$i].Tag=$dstTag
        }
      }
      $miniStatus.Text="Applied map across strip. Pixels changed: $changed"
      Write-PreviewLog ("ApplyMap changed={0} mapEntries={1} applyEnabledNow={2}" -f $changed,$colorMap.Count,($getApplyEnabled.Invoke()))
    }.GetNewClosure())

    $analyzeBtn.Add_Click({ & $analyzePalette }.GetNewClosure())

    $clearCustomBtn.Add_Click({
      for($i=0;$i -lt $defaultPalette.Count;$i++){ $mappedTargets[$i]=0; $mappedFilled[$i]=$false }
      $script:integratedUiFilledSlots=@{}
      & $renderCustomPalette
      $null=$invokeUpdateApplyEnabled.Invoke()
      $miniStatus.Text='Custom mapping cleared.'
    }.GetNewClosure())

    $eyeDropper.Add_CheckedChanged({ if($eyeDropper.Checked){$fillTool.Checked=$false;$eraser.Checked=$false} }.GetNewClosure())
    $fillTool.Add_CheckedChanged({ if($fillTool.Checked){$eyeDropper.Checked=$false} }.GetNewClosure())
    $eraser.Add_CheckedChanged({ if($eraser.Checked){$eyeDropper.Checked=$false} }.GetNewClosure())
    $openDrawColorPicker={
      Write-PreviewLog "DrawColorPicker open"
      $drawColorDialog.Color=[System.Drawing.Color]::FromArgb(255,[int]$drawSwatch.BackColor.R,[int]$drawSwatch.BackColor.G,[int]$drawSwatch.BackColor.B)
      Set-ColorDialogPaletteSafe -dialog $drawColorDialog -colors $script:customPalette
      $res=Show-ColorDialogSafe -dialog $drawColorDialog -owner $form
      if($res -eq [System.Windows.Forms.DialogResult]::OK){
        $picked=[System.Drawing.Color]::FromArgb(255,$drawColorDialog.Color.R,$drawColorDialog.Color.G,$drawColorDialog.Color.B)
        & $setDrawColor $picked
        $script:integratedDrawArgb=[int]$picked.ToArgb()
        $script:integratedActiveMapArgb=[int]$picked.ToArgb()
        $global:GlorgingActiveMapArgb=[int]$picked.ToArgb()
        $global:GlorgingActiveMapR=[int]$picked.R
        $global:GlorgingActiveMapG=[int]$picked.G
        $global:GlorgingActiveMapB=[int]$picked.B
        $script:integratedPickedArgb=[int]$picked.ToArgb()
        $script:integratedHasPickedColor=$true
        $script:integratedColorSource='picker'
        $script:integratedPickerPrimary=$true
        Update-CustomPalette -colorToAdd $picked -savedRoot $libRootText.Text -savedExe $libExeText.Text
        Sync-CustomPaletteFromDialog -dialog $drawColorDialog -savedRoot $libRootText.Text -savedExe $libExeText.Text -preferredColor $picked
        $miniStatus.Text=('Draw color set to {0}' -f (& $colorToHex $picked))
        Write-PreviewLog ("DrawColorPicker OK => {0}" -f (& $colorToHex $picked))
      } else {
        Write-PreviewLog ("DrawColorPicker canceled result={0}" -f [string]$res)
      }
    }.GetNewClosure()
    $drawSwatch.Add_Click({ & $openDrawColorPicker }.GetNewClosure())
    $drawInfo.Add_Click({ & $openDrawColorPicker }.GetNewClosure())
    $drawLabel.Add_Click({ & $openDrawColorPicker }.GetNewClosure())

    $canvas.Add_MouseDown({ param($s,$e) if($e.Button -ne [System.Windows.Forms.MouseButtons]::Left){return}; $mouseDown=$true; $canvas.Capture=$true; & $applyAt $e.X $e.Y $false; if($eyeDropper.Checked -or $fillTool.Checked){$mouseDown=$false;$canvas.Capture=$false} }.GetNewClosure())
    $canvas.Add_MouseMove({ param($s,$e) & $updateHover $e.X $e.Y $false; if($mouseDown){& $applyAt $e.X $e.Y $false} }.GetNewClosure())
    $canvas.Add_MouseUp({ $mouseDown=$false; $canvas.Capture=$false }.GetNewClosure())
    $canvas.Add_MouseLeave({ $editorState.HoverPx=-1; $editorState.HoverPy=-1; & $render }.GetNewClosure())

    $framePick.Add_ValueChanged({ & $render }.GetNewClosure())
    $zoomPick.Add_ValueChanged({ if(-not $syncingZoom -and $fitCheck.Checked){$fitCheck.Checked=$false}else{& $render} }.GetNewClosure())
    $fitCheck.Add_CheckedChanged({ & $render }.GetNewClosure())
    $canvasHost.Add_Resize({ & $render }.GetNewClosure())

    $prevFrameBtn.Add_Click({ if($framePick.Value -gt $framePick.Minimum){$framePick.Value=$framePick.Value-1}else{$framePick.Value=$framePick.Maximum} }.GetNewClosure())
    $nextFrameBtn.Add_Click({ if($framePick.Value -lt $framePick.Maximum){$framePick.Value=$framePick.Value+1}else{$framePick.Value=$framePick.Minimum} }.GetNewClosure())
    $zoomOutBtn.Add_Click({ $fitCheck.Checked=$false; if($zoomPick.Value -gt $zoomPick.Minimum){$zoomPick.Value=$zoomPick.Value-1} }.GetNewClosure())
    $zoomInBtn.Add_Click({ $fitCheck.Checked=$false; if($zoomPick.Value -lt $zoomPick.Maximum){$zoomPick.Value=$zoomPick.Value+1} }.GetNewClosure())

    $saveBtn.Add_Click({ try{$srcBmp.Save($workingPath,[System.Drawing.Imaging.ImageFormat]::Png);$miniStatus.Text="Saved: $workingPath";Render-Selection}catch{[void][System.Windows.Forms.MessageBox]::Show($form,"Save failed:`n$($_.Exception.Message)","Integrated Editor",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)} }.GetNewClosure())
    $backBtn.Add_Click({ if($null -ne $canvas.Image){$canvas.Image.Dispose();$canvas.Image=$null}; if($null -ne $srcBmp){$srcBmp.Dispose()}; if($null -ne $origBmp){$origBmp.Dispose()}; $integratedEditorHost.Visible=$false; $editorHelp.Visible=$true; $autoPlay.Checked=$prevAutoPlay; Render-Selection }.GetNewClosure())

    & $applyEditorSplit
    & $setDrawColor $script:integratedDrawColor
    & $analyzePalette
    & $render
    Start-Sleep -Milliseconds 40
    & $render
    if($seededFromReference){Render-Selection}
  } finally {
    $integratedEditorHost.ResumeLayout()
  }
}
function Ensure-LibreSpriteSource {
  param([string]$rootPath)
  $targetRoot = [System.IO.Path]::GetFullPath($rootPath)
  $parentDir = Split-Path -Parent $targetRoot
  if ([string]::IsNullOrWhiteSpace($parentDir)) { return $false }
  Ensure-Directory $parentDir
  try {
    if (-not (Test-Path (Join-Path $targetRoot ".git") -PathType Container)) {
      git clone https://github.com/LibreSprite/LibreSprite.git $targetRoot | Out-Null
    } else {
      git -C $targetRoot pull --ff-only | Out-Null
    }
    return $true
  } catch {
    return $false
  }
}

function Try-Build-LibreSpriteExe {
  param([string]$rootPath)
  if ([string]::IsNullOrWhiteSpace($rootPath) -or -not (Test-Path (Join-Path $rootPath "CMakeLists.txt") -PathType Leaf)) {
    return ""
  }
  try {
    cmake --version | Out-Null
    if ($LASTEXITCODE -ne 0) { return "" }
  } catch {
    return ""
  }

  $buildDir = Join-Path $rootPath "build"
  Ensure-Directory $buildDir

  $hasNinja = $false
  try {
    ninja --version | Out-Null
    $hasNinja = ($LASTEXITCODE -eq 0)
  } catch {
    $hasNinja = $false
  }

  try {
    if ($hasNinja) {
      cmake -S $rootPath -B $buildDir -G Ninja
    } else {
      cmake -S $rootPath -B $buildDir
    }
    if ($LASTEXITCODE -ne 0) { return "" }

    cmake --build $buildDir --config Release
    if ($LASTEXITCODE -ne 0) { return "" }
  } catch {
    return ""
  }

  return Find-LibreSpriteExeAuto -rootPath $rootPath
}

function Try-Download-LibreSpritePortable {
  param([string]$rootPath)
  try {
    $downloadRoot = Join-Path $rootPath "prebuilt"
    $extractRoot = Join-Path $downloadRoot "latest"
    Ensure-Directory $downloadRoot
    if (Test-Path $extractRoot -PathType Container) {
      Remove-Item -Path $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    Ensure-Directory $extractRoot

    $api = "https://api.github.com/repos/LibreSprite/LibreSprite/releases/latest"
    $release = Invoke-RestMethod -Uri $api -UseBasicParsing
    if ($null -eq $release -or $null -eq $release.assets) { return "" }

    $asset = $null
    foreach ($a in $release.assets) {
      if ($a.name -match '(?i)(win|windows).*\.zip$' -and $a.browser_download_url -match '^https?://') {
        $asset = $a
        break
      }
    }
    if ($null -eq $asset) { return "" }

    $zipPath = Join-Path $downloadRoot $asset.name
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -UseBasicParsing
    Expand-Archive -Path $zipPath -DestinationPath $extractRoot -Force
    $exeList = @(Get-ChildItem -Path $extractRoot -Recurse -Filter "libresprite.exe" -File -ErrorAction SilentlyContinue)
    if ($exeList.Count -eq 0) { return "" }
    $bestExe = $null
    foreach ($e in $exeList) {
      if ($null -eq $bestExe -or $e.LastWriteTime -gt $bestExe.LastWriteTime) { $bestExe = $e }
    }
    if ($null -eq $bestExe) { return "" }
    return [System.IO.Path]::GetFullPath($bestExe.FullName)
  } catch {
    return ""
  }
}

function Update-LibreSpriteStatus {
  $root = $libRootText.Text
  $exe = $libExeText.Text
  $srcOk = Test-Path (Join-Path $root ".git") -PathType Container
  $exeOk = $false
  if (-not [string]::IsNullOrWhiteSpace($exe)) {
    $exeOk = (Test-Path $exe -PathType Leaf)
  }
  $editorStatus.Text = "Status: source=$srcOk | exe=$exeOk | settings=$settingsPath"
  if ($exeOk) {
    Save-PreviewSettings -savedRoot $root -savedExe $exe
  }
}

function Set-EditorStatus {
  param([string]$message, [bool]$busy = $false)
  $editorStatus.Text = ("Status: {0}" -f $message)
  $form.UseWaitCursor = $busy
  $integratedEditButton.Enabled = (-not $busy)
  $editAssetButton.Enabled = (-not $busy)
  $form.Refresh()
  [System.Windows.Forms.Application]::DoEvents()
}

function Ensure-LibreSpriteExeAvailable {
  Set-EditorStatus -message "Finding LibreSprite EXE..." -busy $true
  $exe = $libExeText.Text
  $ok = (-not [string]::IsNullOrWhiteSpace($exe)) -and (Test-Path $exe -PathType Leaf)
  if ($ok) {
    Save-PreviewSettings -savedRoot $libRootText.Text -savedExe $exe
    Set-EditorStatus -message "Found existing LibreSprite EXE." -busy $false
    return $exe
  }

  Set-EditorStatus -message "Checking known build paths..." -busy $true
  $exe = Resolve-LibreSpriteExe -rootPath $libRootText.Text -explicitExe $exe
  if (-not [string]::IsNullOrWhiteSpace($exe) -and (Test-Path $exe -PathType Leaf)) {
    $libExeText.Text = $exe
    Save-PreviewSettings -savedRoot $libRootText.Text -savedExe $exe
    Set-EditorStatus -message "Found LibreSprite EXE in build paths." -busy $false
    return $exe
  }

  Set-EditorStatus -message "Searching filesystem for libresprite.exe..." -busy $true
  $exe = Find-LibreSpriteExeAuto -rootPath $libRootText.Text
  if (-not [string]::IsNullOrWhiteSpace($exe) -and (Test-Path $exe -PathType Leaf)) {
    $libExeText.Text = $exe
    Save-PreviewSettings -savedRoot $libRootText.Text -savedExe $exe
    Set-EditorStatus -message "Found LibreSprite EXE by search." -busy $false
    return $exe
  }

  Set-EditorStatus -message "No EXE found. Bootstrapping source/build..." -busy $true
  if (-not (Test-Path (Join-Path $libRootText.Text ".git") -PathType Container)) {
    Set-EditorStatus -message "Cloning/updating LibreSprite source..." -busy $true
    [void](Ensure-LibreSpriteSource -rootPath $libRootText.Text)
  }
  Set-EditorStatus -message "Re-checking for EXE after source setup..." -busy $true
  $exe = Find-LibreSpriteExeAuto -rootPath $libRootText.Text
  if ([string]::IsNullOrWhiteSpace($exe)) {
    Set-EditorStatus -message "Building LibreSprite (this can take a while)..." -busy $true
    $exe = Try-Build-LibreSpriteExe -rootPath $libRootText.Text
  }
  if (-not [string]::IsNullOrWhiteSpace($exe) -and (Test-Path $exe -PathType Leaf)) {
    $libExeText.Text = $exe
    Save-PreviewSettings -savedRoot $libRootText.Text -savedExe $exe
    Set-EditorStatus -message "LibreSprite EXE is ready." -busy $false
    return $exe
  }

  Set-EditorStatus -message "Build EXE not found. Downloading portable release..." -busy $true
  $exe = Try-Download-LibreSpritePortable -rootPath $libRootText.Text
  if (-not [string]::IsNullOrWhiteSpace($exe) -and (Test-Path $exe -PathType Leaf)) {
    $libExeText.Text = $exe
    Save-PreviewSettings -savedRoot $libRootText.Text -savedExe $exe
    Set-EditorStatus -message "Downloaded LibreSprite and found EXE." -busy $false
    return $exe
  }

  Set-EditorStatus -message "Could not auto-locate/build/download LibreSprite EXE. Use Editor > Advanced." -busy $false
  return ""
}

function Ensure-SelectedAssetForEditing {
  if ($assetList.SelectedIndex -lt 0) { return $null }
  $spec = $assetSpecs[$assetList.SelectedIndex]
  if ($null -eq $spec) { return $null }

  $assetPath = Join-Path $overrideText.Text $spec.RelPath
  if (-not (Test-Path $assetPath -PathType Leaf)) {
    $refCandidate = Join-Path $referenceText.Text $spec.RelPath
    if (Test-Path $refCandidate -PathType Leaf) {
      Ensure-Directory (Split-Path -Parent $assetPath)
      Copy-Item $refCandidate $assetPath -Force
    }
  }
  if (-not (Test-Path $assetPath -PathType Leaf)) {
    return $null
  }
  return [pscustomobject]@{
    Path = $assetPath
    Spec = $spec
  }
}

function Stop-EmbeddedLibreSprite {
  if ($null -ne $script:embeddedLibreProc) {
    try {
      if (-not $script:embeddedLibreProc.HasExited) {
        $script:embeddedLibreProc.CloseMainWindow() | Out-Null
        Start-Sleep -Milliseconds 180
      }
      if (-not $script:embeddedLibreProc.HasExited) {
        $script:embeddedLibreProc.Kill()
      }
    } catch {}
  }
  $script:embeddedLibreProc = $null
  $script:embeddedLibreHwnd = [IntPtr]::Zero
  $script:embeddedAssetPath = ""
  $script:embeddedAssetWriteUtc = [datetime]::MinValue
}

function Resize-EmbeddedLibreSprite {
  if ($script:embeddedLibreHwnd -eq [IntPtr]::Zero) { return }
  $w = [Math]::Max(1, $advancedEditorHost.ClientSize.Width)
  $h = [Math]::Max(1, $advancedEditorHost.ClientSize.Height)
  [void][NativeWin]::MoveWindow($script:embeddedLibreHwnd, 0, 0, $w, $h, $true)
}

function Start-EmbeddedLibreSprite {
  param([string]$exePath, [string]$assetPath)
  Stop-EmbeddedLibreSprite
  $advancedEditorHost.Visible = $true
  foreach ($ctl in @($advancedEditorHost.Controls)) { $ctl.Dispose() }
  $advancedEditorHost.Controls.Clear()

  $proc = $null
  try {
    $proc = Start-Process -FilePath $exePath -ArgumentList ('"{0}"' -f $assetPath) -WorkingDirectory (Split-Path -Parent $exePath) -PassThru
  } catch {
    [void][System.Windows.Forms.MessageBox]::Show($form, "Failed to launch LibreSprite:`n$($_.Exception.Message)", "LibreSprite", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    return $false
  }
  if ($null -eq $proc) { return $false }

  $hwnd = [IntPtr]::Zero
  for ($i = 0; $i -lt 80; $i++) {
    Start-Sleep -Milliseconds 125
    try { $proc.Refresh() } catch {}
    if ($proc.HasExited) { break }
    if ($proc.MainWindowHandle -ne [IntPtr]::Zero) {
      $hwnd = $proc.MainWindowHandle
      break
    }
  }
  if ($hwnd -eq [IntPtr]::Zero) {
    $editorStatus.Text = "Status: LibreSprite launched externally (window handle not detected for embed)."
    return $true
  }

  $GWL_STYLE = -16
  $WS_CHILD = 0x40000000
  $WS_VISIBLE = 0x10000000
  $WS_CAPTION = 0x00C00000
  $WS_THICKFRAME = 0x00040000
  $WS_MINIMIZEBOX = 0x00020000
  $WS_MAXIMIZEBOX = 0x00010000
  $WS_SYSMENU = 0x00080000

  [void][NativeWin]::SetParent($hwnd, $advancedEditorHost.Handle)
  $style = [NativeWin]::GetWindowLong($hwnd, $GWL_STYLE)
  $style = ($style -band (-bnot ($WS_CAPTION -bor $WS_THICKFRAME -bor $WS_MINIMIZEBOX -bor $WS_MAXIMIZEBOX -bor $WS_SYSMENU))) -bor $WS_CHILD -bor $WS_VISIBLE
  [void][NativeWin]::SetWindowLong($hwnd, $GWL_STYLE, $style)
  [void][NativeWin]::ShowWindow($hwnd, 5)

  $script:embeddedLibreProc = $proc
  $script:embeddedLibreHwnd = $hwnd
  $script:embeddedAssetPath = $assetPath
  try {
    $script:embeddedAssetWriteUtc = (Get-Item $assetPath).LastWriteTimeUtc
  } catch {
    $script:embeddedAssetWriteUtc = [datetime]::MinValue
  }
  Resize-EmbeddedLibreSprite
  return $true
}

function Update-FramePreview {
  if ($null -eq $script:currentSpec) { return }

  if ($script:currentSpec.Kind -ne "strip") {
    Set-ImageBox $frameReference.Picture $null
    Set-ImageBox $frameOverride.Picture $null
    $frameLabel.Text = "Frame: n/a"
    if ($null -ne $script:currentRefStrip) {
      Set-ImageBox $liveReference.Picture ([System.Drawing.Bitmap]$script:currentRefStrip.Clone())
    } else {
      Set-ImageBox $liveReference.Picture $null
    }
    if ($null -ne $script:currentOverrideStrip) {
      Set-ImageBox $liveOverride.Picture ([System.Drawing.Bitmap]$script:currentOverrideStrip.Clone())
    } else {
      Set-ImageBox $liveOverride.Picture $null
    }
    return
  }

  $maxFrame = [Math]::Max($script:currentSpec.Frames - 1, 0)
  if ($script:currentFrameIndex -gt $maxFrame) { $script:currentFrameIndex = 0 }

  $refFrame = New-FrameBitmap -stripBmp $script:currentRefStrip -frameIndex $script:currentFrameIndex -frameW $script:currentSpec.FrameW -frameH $script:currentSpec.FrameH -frameCount $script:currentSpec.Frames
  $ovrFrame = New-FrameBitmap -stripBmp $script:currentOverrideStrip -frameIndex $script:currentFrameIndex -frameW $script:currentSpec.FrameW -frameH $script:currentSpec.FrameH -frameCount $script:currentSpec.Frames
  Set-ImageBox $frameReference.Picture $refFrame
  Set-ImageBox $frameOverride.Picture $ovrFrame
  $frameLabel.Text = ("Frame: {0} / {1}" -f $script:currentFrameIndex, $maxFrame)
  if ($null -ne $refFrame) {
    Set-ImageBox $liveReference.Picture ([System.Drawing.Bitmap]$refFrame.Clone())
  } else {
    Set-ImageBox $liveReference.Picture $null
  }
  if ($null -ne $ovrFrame) {
    Set-ImageBox $liveOverride.Picture ([System.Drawing.Bitmap]$ovrFrame.Clone())
  } else {
    Set-ImageBox $liveOverride.Picture $null
  }
}

function Render-Selection {
  if ($assetList.SelectedIndex -lt 0) { return }

  Dispose-CurrentStripState
  $script:currentSpec = $assetSpecs[$assetList.SelectedIndex]
  $script:currentFrameIndex = 0
  $frameSlider.Minimum = 0
  $frameSlider.Maximum = [Math]::Max($script:currentSpec.Frames - 1, 0)
  $frameSlider.Value = 0

  $overridePath = Join-Path $overrideText.Text $script:currentSpec.RelPath
  $referencePath = $null
  if (-not [string]::IsNullOrWhiteSpace($referenceText.Text)) {
    $referencePath = Join-Path $referenceText.Text $script:currentSpec.RelPath
  }

  $script:currentOverrideStrip = Load-BitmapSafe $overridePath
  if ($null -ne $referencePath) {
    $script:currentRefStrip = Load-BitmapSafe $referencePath
  }

  Set-ImageBox $stripReference.Picture $null
  Set-ImageBox $stripOverride.Picture $null

  if ($null -ne $script:currentRefStrip) {
    Set-ImageBox $stripReference.Picture ([System.Drawing.Bitmap]$script:currentRefStrip.Clone())
  }
  if ($null -ne $script:currentOverrideStrip) {
    Set-ImageBox $stripOverride.Picture ([System.Drawing.Bitmap]$script:currentOverrideStrip.Clone())
  }

  $refSizeOk = Test-ExpectedSize -bmp $script:currentRefStrip -expectedW $script:currentSpec.ExpectedW -expectedH $script:currentSpec.ExpectedH
  $ovrSizeOk = Test-ExpectedSize -bmp $script:currentOverrideStrip -expectedW $script:currentSpec.ExpectedW -expectedH $script:currentSpec.ExpectedH

  $refSizeTxt = if ($null -eq $script:currentRefStrip) { "missing" } else { "{0}x{1}" -f $script:currentRefStrip.Width, $script:currentRefStrip.Height }
  $ovrSizeTxt = if ($null -eq $script:currentOverrideStrip) { "missing" } else { "{0}x{1}" -f $script:currentOverrideStrip.Width, $script:currentOverrideStrip.Height }
  $overrideWarning = ""
  if ($null -eq $script:currentOverrideStrip) {
    $overrideWarning = "WARNING: Override file missing. Save from Editor, then press F5."
  } elseif (-not $ovrSizeOk) {
    $overrideWarning = ("WARNING: Override size mismatch. Expected {0}x{1}, got {2}. Live Override may be blank." -f $script:currentSpec.ExpectedW, $script:currentSpec.ExpectedH, $ovrSizeTxt)
  }

  $statusLabel.Text = @(
    ("Preview Tool: {0}" -f $previewVersion),
    ("Script: {0}" -f $MyInvocation.MyCommand.Path),
    ("Game: {0}" -f $GameRoot),
    ("Style: {0}" -f $styleCombo.SelectedItem),
    ("Selected: {0}" -f $script:currentSpec.Display),
    ("Expected: {0}x{1} ({2} frame(s), {3}x{4} each)" -f $script:currentSpec.ExpectedW, $script:currentSpec.ExpectedH, $script:currentSpec.Frames, $script:currentSpec.FrameW, $script:currentSpec.FrameH),
    ("Reference: {0} [{1}] ({2})" -f $referencePath, $refSizeTxt, ($(if ($refSizeOk) { "OK" } else { "check" }))),
    ("Override:  {0} [{1}] ({2})" -f $overridePath, $ovrSizeTxt, ($(if ($ovrSizeOk) { "OK" } else { "check" }))),
    ($(if ([string]::IsNullOrWhiteSpace($overrideWarning)) { "Tip: set Reference Root to another ModAssets export for A/B diff; leave empty for override-only checks." } else { $overrideWarning })),
    ("Quick action: use 'Open Current Override File' to verify the exact file path being edited.")
  ) -join [Environment]::NewLine

  Update-FramePreview
} 

$assetList.Add_SelectedIndexChanged({ Render-Selection })
$reloadButton.Add_Click({ Render-Selection })

$overrideBrowse.Add_Click({
  $picked = Select-Folder -initialPath $overrideText.Text
  if ($null -ne $picked) {
    $overrideText.Text = $picked
    Render-Selection
  }
})

$referenceBrowse.Add_Click({
  $picked = Select-Folder -initialPath $referenceText.Text
  if ($null -ne $picked) {
    $script:autoReferenceByStyle = $false
    $referenceText.Text = $picked
    Render-Selection
  }
})

$gameBrowse.Add_Click({
  $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
  $dialog.Description = "Select game install folder (must contain Data\Styles)"
  if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    if (-not (Test-GameRoot $dialog.SelectedPath)) {
      [void][System.Windows.Forms.MessageBox]::Show($form, "Invalid folder. Data\Styles not found.", "Invalid Game Folder", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
      return
    }
    $GameRoot = [System.IO.Path]::GetFullPath($dialog.SelectedPath)
    if ($gameCombo.Items.IndexOf($GameRoot) -lt 0) { [void]$gameCombo.Items.Add($GameRoot) }
    $gameCombo.SelectedItem = $GameRoot
    if (Ensure-BaselineExportAllStyles -gameRootPath $GameRoot -owner $form) {
      Set-ReferenceRootForStyle -styleName ([string]$styleCombo.SelectedItem)
      if ([string]::IsNullOrWhiteSpace($overrideText.Text) -or $overrideText.Text -notlike "*\Data\ModAssets\Packs\*") {
        $overrideText.Text = Join-Path $GameRoot ("Data\ModAssets\Packs\{0}" -f $PackName)
      }
      Ensure-Directory $overrideText.Text
      Ensure-Directory (Join-Path $overrideText.Text "UI")
      Ensure-Directory (Join-Path $overrideText.Text "Lemmings")
      Render-Selection
    }
  }
})

$gameCombo.Add_SelectedIndexChanged({
  $selected = [string]$gameCombo.SelectedItem
  if (-not [string]::IsNullOrWhiteSpace($selected) -and (Test-GameRoot $selected)) {
    $GameRoot = [System.IO.Path]::GetFullPath($selected)
    [void](Ensure-BaselineExportAllStyles -gameRootPath $GameRoot -owner $form)
    Set-ReferenceRootForStyle -styleName ([string]$styleCombo.SelectedItem)
    if ([string]::IsNullOrWhiteSpace($overrideText.Text) -or $overrideText.Text -notlike "*\Data\ModAssets\Packs\*") {
      $overrideText.Text = Join-Path $GameRoot ("Data\ModAssets\Packs\{0}" -f $PackName)
      Ensure-Directory $overrideText.Text
      Ensure-Directory (Join-Path $overrideText.Text "UI")
      Ensure-Directory (Join-Path $overrideText.Text "Lemmings")
    }
    Render-Selection
  }
})

$styleCombo.Add_SelectedIndexChanged({
  Set-ReferenceRootForStyle -styleName ([string]$styleCombo.SelectedItem)
  Render-Selection
})

$ensureBaselineButton.Add_Click({
  if (Ensure-BaselineExportAllStyles -gameRootPath $GameRoot -owner $form) {
    Set-ReferenceRootForStyle -styleName ([string]$styleCombo.SelectedItem)
    Render-Selection
  }
})

$openPackButton.Add_Click({ Open-ActivePackFolder })
$launchGameButton.Add_Click({ Launch-GameExe })
$openOverrideAssetButton.Add_Click({ Open-CurrentOverrideAsset })

$libRootBrowse.Add_Click({
  $picked = Select-Folder -initialPath $libRootText.Text
  if ($null -ne $picked) {
    $libRootText.Text = $picked
    if ([string]::IsNullOrWhiteSpace($libExeText.Text) -or -not (Test-Path $libExeText.Text -PathType Leaf)) {
      $libExeText.Text = Resolve-LibreSpriteExe -rootPath $libRootText.Text -explicitExe ""
    }
    Save-PreviewSettings -savedRoot $libRootText.Text -savedExe $libExeText.Text
    Update-LibreSpriteStatus
  }
})

$libExeBrowse.Add_Click({
  $picked = Select-ExecutableFile -title "Select LibreSprite EXE" -initialDir (Split-Path -Parent $libRootText.Text)
  if ($null -ne $picked) {
    $libExeText.Text = $picked
    Save-PreviewSettings -savedRoot $libRootText.Text -savedExe $libExeText.Text
    Update-LibreSpriteStatus
  }
})

$cloneUpdateButton.Add_Click({
  $editorStatus.Text = "Status: cloning/updating LibreSprite..."
  $form.Refresh()
  if (Ensure-LibreSpriteSource -rootPath $libRootText.Text) {
    $libExeText.Text = Resolve-LibreSpriteExe -rootPath $libRootText.Text -explicitExe $libExeText.Text
    $editorStatus.Text = "Status: LibreSprite source is ready."
    Save-PreviewSettings -savedRoot $libRootText.Text -savedExe $libExeText.Text
  } else {
    $editorStatus.Text = "Status: failed to clone/update LibreSprite source."
  }
  Update-LibreSpriteStatus
})

$openSourceButton.Add_Click({
  Ensure-Directory $libRootText.Text
  Start-Process -FilePath "explorer.exe" -ArgumentList ('"{0}"' -f $libRootText.Text) | Out-Null
})

$launchLibreButton.Add_Click({
  $exe = $libExeText.Text
  $exeOk = (-not [string]::IsNullOrWhiteSpace($exe)) -and (Test-Path $exe -PathType Leaf)
  if (-not $exeOk) {
    $picked = Select-ExecutableFile -title "Select LibreSprite EXE" -initialDir (Split-Path -Parent $libRootText.Text)
    if ($null -ne $picked) { $libExeText.Text = $picked; $exe = $picked }
    $exeOk = (-not [string]::IsNullOrWhiteSpace($exe)) -and (Test-Path $exe -PathType Leaf)
    if (-not $exeOk) {
      [void][System.Windows.Forms.MessageBox]::Show($form, "LibreSprite executable not found. Build LibreSprite first or browse to libresprite.exe.", "LibreSprite", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
      return
    }
  }
  Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe) | Out-Null
  Update-LibreSpriteStatus
})

$editAssetButton.Add_Click({
  try {
    Set-EditorStatus -message "Preparing selected asset..." -busy $true
    $selected = Ensure-SelectedAssetForEditing
    if ($null -eq $selected) {
      Set-EditorStatus -message "No selectable asset found." -busy $false
      [void][System.Windows.Forms.MessageBox]::Show($form, "Select an asset in Preview first. If override is missing, reference must exist so it can be seeded.", "Editor", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
      return
    }
    $exe = Ensure-LibreSpriteExeAvailable
    if ([string]::IsNullOrWhiteSpace($exe)) {
      Set-EditorStatus -message "LibreSprite EXE unavailable." -busy $false
      [void][System.Windows.Forms.MessageBox]::Show($form, "LibreSprite EXE not found. Use Editor > Advanced to set source/exe.", "Editor", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
      return
    }
    Set-EditorStatus -message "Launching LibreSprite in Advanced panel..." -busy $true
    if (Start-EmbeddedLibreSprite -exePath $exe -assetPath $selected.Path) {
      Set-EditorStatus -message ("Embedded LibreSprite active: {0}" -f $selected.Path) -busy $false
      $tabControl.SelectedTab = $editorTab
      $editorTabs.SelectedTab = $editorAdvancedTab
    } else {
      Set-EditorStatus -message "LibreSprite launch did not complete." -busy $false
    }
  } catch {
    Set-EditorStatus -message "Advanced launch failed." -busy $false
    [void][System.Windows.Forms.MessageBox]::Show($form, "Advanced launch failed:`n$($_.Exception.Message)", "Editor", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
  }
})

$integratedEditButton.Add_Click({
  try {
    if ($assetList.SelectedIndex -lt 0) {
      [void][System.Windows.Forms.MessageBox]::Show($form, "Select an asset in the Preview tab first.", "Integrated Editor", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
      return
    }
    $spec = $assetSpecs[$assetList.SelectedIndex]
    $assetPath = Get-SelectedAssetPath
    Open-IntegratedPixelEditor -assetPath $assetPath -spec $spec
    Set-EditorStatus -message "Mini editor ready." -busy $false
  } catch {
    Set-EditorStatus -message "Editor launch failed." -busy $false
    Write-PreviewLog ("Open-IntegratedPixelEditor ERROR: {0}" -f $_.Exception.ToString())
    [void][System.Windows.Forms.MessageBox]::Show($form, "Editor launch failed:`n$($_.Exception.Message)", "Editor", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    $integratedEditorHost.Visible = $false
    $editorHelp.Visible = $true
  }
})

$frameSlider.Add_ValueChanged({
  $script:currentFrameIndex = $frameSlider.Value
  Update-FramePreview
})

$advancedEditorHost.Add_Resize({
  Resize-EmbeddedLibreSprite
})

$timer.Add_Tick({
  if (-not [string]::IsNullOrWhiteSpace($script:embeddedAssetPath) -and (Test-Path $script:embeddedAssetPath -PathType Leaf)) {
    try {
      $curWrite = (Get-Item $script:embeddedAssetPath).LastWriteTimeUtc
      if ($curWrite -ne $script:embeddedAssetWriteUtc) {
        $script:embeddedAssetWriteUtc = $curWrite
        if ($assetList.SelectedIndex -ge 0) {
          $selectedNow = Join-Path $overrideText.Text $assetSpecs[$assetList.SelectedIndex].RelPath
          if ([System.StringComparer]::OrdinalIgnoreCase.Equals($selectedNow, $script:embeddedAssetPath)) {
            Render-Selection
          }
        }
      }
    } catch {}
  }
  if ($null -eq $script:currentSpec) { return }
  if ($tabControl.SelectedTab -ne $previewTab) { return }
  if (-not $autoPlay.Checked) { return }
  if ($script:currentSpec.Kind -ne "strip") { return }
  if ($script:currentSpec.Frames -le 1) { return }

  $next = $script:currentFrameIndex + 1
  if ($next -ge $script:currentSpec.Frames) { $next = 0 }
  $script:currentFrameIndex = $next
  $frameSlider.Value = $script:currentFrameIndex
})

$form.KeyPreview = $true
$form.Add_KeyDown({
  param($sender, $eventArgs)
  if ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::F5) {
    Render-Selection
    $eventArgs.Handled = $true
  }
})

$form.Add_FormClosed({
  Stop-EmbeddedLibreSprite
  Dispose-CurrentStripState
  foreach ($pb in @($liveReference.Picture, $liveOverride.Picture, $stripReference.Picture, $stripOverride.Picture, $frameReference.Picture, $frameOverride.Picture)) {
    if ($null -ne $pb.Image) { $pb.Image.Dispose(); $pb.Image = $null }
  }
})

if (-not (Ensure-BaselineExportAllStyles -gameRootPath $GameRoot -owner $form)) {
  $statusLabel.Text = "Baseline export failed. Use 'Ensure Baseline' after fixing exporter/build."
}
Set-ReferenceRootForStyle -styleName ([string]$styleCombo.SelectedItem)
Update-LibreSpriteStatus

if ($assetList.Items.Count -gt 0) {
  $startIndex = 0
  if (-not [string]::IsNullOrWhiteSpace($StartAsset)) {
    for ($ix = 0; $ix -lt $assetSpecs.Count; $ix++) {
      $spec = $assetSpecs[$ix]
      if ($spec.Id -ieq $StartAsset -or $spec.Display -like "*$StartAsset*") {
        $startIndex = $ix
        break
      }
    }
  }
  $assetList.SelectedIndex = $startIndex
}

[void]$form.ShowDialog()


