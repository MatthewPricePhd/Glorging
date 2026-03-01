param(
  [switch]$FreshLog
)

$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "ModAssetPreview.ps1"
if (-not (Test-Path $scriptPath -PathType Leaf)) {
  throw "Missing script: $scriptPath"
}

$logPath = Join-Path $env:TEMP "ModAssetPreview.log"
if ($FreshLog -and (Test-Path $logPath -PathType Leaf)) {
  Remove-Item $logPath -Force
}

Start-Process -FilePath powershell -ArgumentList @(
  "-NoProfile",
  "-ExecutionPolicy", "Bypass",
  "-File", $scriptPath
) | Out-Null

Write-Output ("Launched: {0}" -f $scriptPath)
Write-Output ("Log: {0}" -f $logPath)
