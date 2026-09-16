# Stage and zip the Windows release assets: full client, launcher, pck (content) and runtime.
#
# Split out of the release runbook so `tools/release.sh` is one call rather than a wall of inline
# PowerShell. Nothing here opens a window.
#
# The pck/runtime split is what keeps a content update at ~24MB instead of ~62MB: the launcher
# pulls the pck every release and the runtime only when RUNTIME_VERSION.txt changes.
param(
	[Parameter(Mandatory = $true)][string]$Version,
	[Parameter(Mandatory = $true)][string]$Runtime
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$rel = Join-Path $root 'releases'
$bw = Join-Path $root 'builds\windows'
New-Item -ItemType Directory -Force $rel | Out-Null

function Stage([string]$name, [string[]]$files, [string]$zip) {
	$dir = Join-Path $rel $name
	if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
	New-Item -ItemType Directory -Force $dir | Out-Null
	foreach ($f in $files) { Copy-Item (Join-Path $bw $f) $dir }
	$out = Join-Path $rel $zip
	Compress-Archive -Path (Join-Path $dir '*') -DestinationPath $out -Force
	$mb = [math]::Round((Get-Item $out).Length / 1MB, 1)
	Write-Output ("  {0}  {1} MB" -f $zip, $mb)
	Remove-Item -Recurse -Force $dir
}

$dll = 'libgdsqlite.windows.template_release.x86_64.dll'
Stage 'client_stage' @('PhantomBadlandsClient.exe', 'PhantomBadlandsClient.pck', $dll, 'VERSION.txt', 'CREDITS.md') "phantom-badlands-client-v$Version.zip"
Stage 'launcher_stage' @('PhantomBadlandsLauncher.exe') 'phantom-badlands-launcher.zip'
Stage 'pck_stage' @('PhantomBadlandsClient.pck', 'VERSION.txt', 'CREDITS.md') "phantom-badlands-pck-v$Version.zip"
Stage 'runtime_stage' @('PhantomBadlandsClient.exe', $dll) "phantom-badlands-runtime-r$Runtime.zip"
