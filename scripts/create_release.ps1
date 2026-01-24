# create_release.ps1
# Helper script to create a release package for Phantasia Revival
# Usage: .\create_release.ps1 -Version "1.0.1"

param(
    [Parameter(Mandatory=$true)]
    [string]$Version
)

$ProjectPath = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$ExportPath = "$ProjectPath\builds"
$ReleasePath = "$ProjectPath\releases"

# Create directories if they don't exist
New-Item -ItemType Directory -Force -Path $ExportPath | Out-Null
New-Item -ItemType Directory -Force -Path $ReleasePath | Out-Null

Write-Host "Creating release v$Version..." -ForegroundColor Cyan

# Update VERSION.txt
Set-Content -Path "$ProjectPath\VERSION.txt" -Value $Version
Write-Host "Updated VERSION.txt to $Version" -ForegroundColor Green

# Export paths
$GodotPath = "D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
$ClientExport = "$ExportPath\phantasia-client.exe"

Write-Host "Exporting client..." -ForegroundColor Yellow
& $GodotPath --headless --path $ProjectPath --export-release "Windows Desktop" $ClientExport

if (Test-Path $ClientExport) {
    Write-Host "Client exported successfully" -ForegroundColor Green

    # Create zip package
    $ZipName = "phantasia-client-v$Version.zip"
    $ZipPath = "$ReleasePath\$ZipName"

    # Files to include in release
    $FilesToZip = @(
        "$ExportPath\phantasia-client.exe",
        "$ExportPath\phantasia-client.pck",
        "$ProjectPath\VERSION.txt"
    )

    # Remove old zip if exists
    if (Test-Path $ZipPath) {
        Remove-Item $ZipPath
    }

    # Create zip
    Compress-Archive -Path $FilesToZip -DestinationPath $ZipPath

    Write-Host "Release package created: $ZipPath" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Go to your GitHub repository" -ForegroundColor White
    Write-Host "2. Click 'Releases' -> 'Create a new release'" -ForegroundColor White
    Write-Host "3. Set tag to: v$Version" -ForegroundColor White
    Write-Host "4. Upload: $ZipPath" -ForegroundColor White
    Write-Host "5. Publish the release" -ForegroundColor White
} else {
    Write-Host "Export failed!" -ForegroundColor Red
}
