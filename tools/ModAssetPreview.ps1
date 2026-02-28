param(
  [string]$OverrideRoot = "",
  [string]$ReferenceRoot = "",
  [string]$StartAsset = ""
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..")

if ([string]::IsNullOrWhiteSpace($OverrideRoot)) {
  $OverrideRoot = Join-Path $repoRoot "src\Data\ModAssets"
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
      return [System.Drawing.Bitmap]$raw.Clone()
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

  $panel.Controls.Add($picture)
  $panel.Controls.Add($label)

  return [pscustomobject]@{
    Panel = $panel
    Label = $label
    Picture = $picture
  }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Glorging Mod Asset Preview"
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
$toolbar.RowCount = 3
$toolbar.AutoSize = $true
$toolbar.Padding = New-Object System.Windows.Forms.Padding(8)
$toolbar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 120)))
$toolbar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
$toolbar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 90)))
$toolbar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 120)))
$toolbar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
$toolbar.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 120)))

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

$toolbar.Controls.Add($overrideLabel, 0, 0)
$toolbar.Controls.Add($overrideText, 1, 0)
$toolbar.Controls.Add($overrideBrowse, 2, 0)
$toolbar.Controls.Add($referenceLabel, 3, 0)
$toolbar.Controls.Add($referenceText, 4, 0)
$toolbar.Controls.Add($referenceBrowse, 5, 0)
$toolbar.Controls.Add($reloadButton, 0, 1)
$toolbar.Controls.Add($autoPlay, 1, 1)
$toolbar.Controls.Add($frameSlider, 4, 1)
$toolbar.Controls.Add($frameLabel, 5, 1)

$mainSplit = New-Object System.Windows.Forms.SplitContainer
$mainSplit.Dock = [System.Windows.Forms.DockStyle]::Fill
$mainSplit.Orientation = [System.Windows.Forms.Orientation]::Vertical
$mainSplit.FixedPanel = [System.Windows.Forms.FixedPanel]::Panel1
$mainSplit.Panel1MinSize = 260
$mainSplit.SplitterDistance = 320

$assetList = New-Object System.Windows.Forms.ListBox
$assetList.Dock = [System.Windows.Forms.DockStyle]::Fill
$assetList.IntegralHeight = $false
foreach ($spec in $assetSpecs) {
  [void]$assetList.Items.Add($spec.Display)
}

$mainSplit.Panel1.Controls.Add($assetList)

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
$liveGrid.Controls.Add($liveReference.Panel, 0, 0)
$liveGrid.Controls.Add($liveOverride.Panel, 1, 0)

$rightSplit = New-Object System.Windows.Forms.SplitContainer
$rightSplit.Dock = [System.Windows.Forms.DockStyle]::Fill
$rightSplit.Orientation = [System.Windows.Forms.Orientation]::Vertical
$rightSplit.FixedPanel = [System.Windows.Forms.FixedPanel]::None

$diagLayout = New-Object System.Windows.Forms.TableLayoutPanel
$diagLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
$diagLayout.ColumnCount = 3
$diagLayout.RowCount = 2
$diagLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 33.3333)))
$diagLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 33.3333)))
$diagLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 33.3333)))
$diagLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 50)))
$diagLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 50)))

$stripReference = New-PreviewBox "Reference Strip"
$stripOverride = New-PreviewBox "Override Strip"
$stripDiff = New-PreviewBox "Strip Diff"
$frameReference = New-PreviewBox "Reference Frame"
$frameOverride = New-PreviewBox "Override Frame"
$frameDiff = New-PreviewBox "Frame Diff"
$diagLayout.Controls.Add($stripReference.Panel, 0, 0)
$diagLayout.Controls.Add($stripOverride.Panel, 1, 0)
$diagLayout.Controls.Add($stripDiff.Panel, 2, 0)
$diagLayout.Controls.Add($frameReference.Panel, 0, 1)
$diagLayout.Controls.Add($frameOverride.Panel, 1, 1)
$diagLayout.Controls.Add($frameDiff.Panel, 2, 1)

$rightSplit.Panel1.Controls.Add($liveGrid)
$rightSplit.Panel2.Controls.Add($diagLayout)

$rightLayout.Controls.Add($rightSplit, 0, 0)
$mainSplit.Panel2.Controls.Add($rightLayout)

$form.Add_Shown({
  $targetDiagWidth = 260
  $target = $rightSplit.Width - $targetDiagWidth
  if ($target -gt 120 -and $target -lt ($rightSplit.Width - 120)) {
    $rightSplit.SplitterDistance = $target
  }
})

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
$statusLabel.Padding = New-Object System.Windows.Forms.Padding(8, 6, 8, 6)
$statusLabel.AutoSize = $true
$statusLabel.Text = "Status"

$rootLayout.Controls.Add($toolbar, 0, 0)
$rootLayout.Controls.Add($mainSplit, 0, 1)
$rootLayout.Controls.Add($statusLabel, 0, 2)
$form.Controls.Add($rootLayout)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 120
$timer.Enabled = $true

$currentSpec = $null
$currentRefStrip = $null
$currentOverrideStrip = $null
$currentFrameIndex = 0

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

function Update-FramePreview {
  if ($null -eq $script:currentSpec) { return }

  if ($script:currentSpec.Kind -ne "strip") {
    Set-ImageBox $frameReference.Picture $null
    Set-ImageBox $frameOverride.Picture $null
    Set-ImageBox $frameDiff.Picture $null
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
  $diffFrame = New-DiffBitmap -bmpA $refFrame -bmpB $ovrFrame

  Set-ImageBox $frameReference.Picture $refFrame
  Set-ImageBox $frameOverride.Picture $ovrFrame
  Set-ImageBox $frameDiff.Picture $diffFrame
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
  Set-ImageBox $stripDiff.Picture $null

  if ($null -ne $script:currentRefStrip) {
    Set-ImageBox $stripReference.Picture ([System.Drawing.Bitmap]$script:currentRefStrip.Clone())
  }
  if ($null -ne $script:currentOverrideStrip) {
    Set-ImageBox $stripOverride.Picture ([System.Drawing.Bitmap]$script:currentOverrideStrip.Clone())
  }
  Set-ImageBox $stripDiff.Picture (New-DiffBitmap -bmpA $script:currentRefStrip -bmpB $script:currentOverrideStrip)

  $refSizeOk = Test-ExpectedSize -bmp $script:currentRefStrip -expectedW $script:currentSpec.ExpectedW -expectedH $script:currentSpec.ExpectedH
  $ovrSizeOk = Test-ExpectedSize -bmp $script:currentOverrideStrip -expectedW $script:currentSpec.ExpectedW -expectedH $script:currentSpec.ExpectedH

  $refSizeTxt = if ($null -eq $script:currentRefStrip) { "missing" } else { "{0}x{1}" -f $script:currentRefStrip.Width, $script:currentRefStrip.Height }
  $ovrSizeTxt = if ($null -eq $script:currentOverrideStrip) { "missing" } else { "{0}x{1}" -f $script:currentOverrideStrip.Width, $script:currentOverrideStrip.Height }

  $statusLabel.Text = @(
    ("Selected: {0}" -f $script:currentSpec.Display),
    ("Expected: {0}x{1} ({2} frame(s), {3}x{4} each)" -f $script:currentSpec.ExpectedW, $script:currentSpec.ExpectedH, $script:currentSpec.Frames, $script:currentSpec.FrameW, $script:currentSpec.FrameH),
    ("Reference: {0} [{1}] ({2})" -f $referencePath, $refSizeTxt, ($(if ($refSizeOk) { "OK" } else { "check" }))),
    ("Override:  {0} [{1}] ({2})" -f $overridePath, $ovrSizeTxt, ($(if ($ovrSizeOk) { "OK" } else { "check" }))),
    "Tip: set Reference Root to another ModAssets export for A/B diff; leave empty for override-only checks."
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
    $referenceText.Text = $picked
    Render-Selection
  }
})

$frameSlider.Add_ValueChanged({
  $script:currentFrameIndex = $frameSlider.Value
  Update-FramePreview
})

$timer.Add_Tick({
  if ($null -eq $script:currentSpec) { return }
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
  Dispose-CurrentStripState
  foreach ($pb in @($liveReference.Picture, $liveOverride.Picture, $stripReference.Picture, $stripOverride.Picture, $stripDiff.Picture, $frameReference.Picture, $frameOverride.Picture, $frameDiff.Picture)) {
    if ($null -ne $pb.Image) { $pb.Image.Dispose(); $pb.Image = $null }
  }
})

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
