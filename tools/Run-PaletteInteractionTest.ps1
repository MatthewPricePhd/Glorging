param(
  [string]$LaunchScript = "",
  [switch]$SkipLaunch
)

$ErrorActionPreference = "Stop"

function Get-LatestEditorSession {
  param([string]$LogPath)

  if (-not (Test-Path $LogPath -PathType Leaf)) {
    return @()
  }

  $lines = Get-Content -Path $LogPath -Encoding UTF8
  if ($lines.Count -eq 0) { return @() }

  $startIdx = -1
  for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    if ($lines[$i] -like "*Open-IntegratedPixelEditor start*") {
      $startIdx = $i
      break
    }
  }

  if ($startIdx -lt 0) { return @() }
  return @($lines[$startIdx..($lines.Count - 1)])
}

function Show-SessionSummary {
  param([string[]]$SessionLines)

  $markers = @(
    "AnalyzeStrip clicked",
    "AnalyzeStrip result colors=",
    "DefaultMouseDown",
    "DefaultStep idx=",
    "DefaultStep argb=",
    "DefaultStep selectMapIndex done",
    "DefaultStep set script colors done",
    "DefaultStep drawSwatch set done",
    "DefaultStep drawInfo set done",
    "DefaultStep direct-ui done",
    "CustomMouseDown",
    "CustomStep slot=",
    "CustomSelect slot=",
    "CustomStep targetColor built",
    "CustomStep selectMapIndex done",
    "CustomStep direct-map done",
    "CustomSelect mapped slot="
  )

  Write-Host ""
  Write-Host "=== Session Marker Summary ==="
  foreach ($m in $markers) {
    $count = (@($SessionLines | Where-Object { $_ -like "*$m*" })).Count
    Write-Host ("{0,-40} {1}" -f $m, $count)
  }
  Write-Host "=============================="
  Write-Host ""
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$launchPath = if ([string]::IsNullOrWhiteSpace($LaunchScript)) {
  Join-Path $PSScriptRoot "Launch-ModAssetPreview.ps1"
} else {
  $LaunchScript
}

$logPath = Join-Path $env:TEMP "ModAssetPreview.log"

if (-not $SkipLaunch) {
  if (-not (Test-Path $launchPath -PathType Leaf)) {
    throw "Launch script not found: $launchPath"
  }
  & powershell -NoProfile -ExecutionPolicy Bypass -File $launchPath -FreshLog | Out-Host
}

Write-Host ""
Write-Host "Manual test steps:"
Write-Host "1) Open Basic Editor."
Write-Host "2) Click Default palette position 1."
Write-Host "3) Click Custom mapping position 1."
Write-Host "4) Press Enter here to collect results."
[void](Read-Host "Press Enter when done")

$session = Get-LatestEditorSession -LogPath $logPath
if ($session.Count -eq 0) {
  Write-Host "No editor session lines found in log: $logPath"
  exit 1
}

Show-SessionSummary -SessionLines $session

$outPath = Join-Path $repoRoot "tools\last-palette-interaction-session.log"
$session | Set-Content -Path $outPath -Encoding UTF8
Write-Host ("Saved latest session log to: {0}" -f $outPath)

Write-Host ""
Write-Host "Last 80 session lines:"
$tailCount = [Math]::Min(80, $session.Count)
$session[($session.Count - $tailCount)..($session.Count - 1)] | ForEach-Object { Write-Host $_ }
