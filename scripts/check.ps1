# Runs every static check: lint, format, and strict type-check.
# Usage: ./scripts/check.ps1
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)

# Roblox API type definitions for luau-lsp, at the security level game scripts run with.
$types = ".luau-types/globalTypes.d.luau"
if (-not (Test-Path $types)) {
	New-Item -ItemType Directory -Force (Split-Path $types) | Out-Null
	$url = "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/1.70.1/scripts/globalTypes.None.d.luau"
	Invoke-WebRequest $url -OutFile $types -UseBasicParsing
}

$failed = @()

Write-Host "== selene"
selene src
if ($LASTEXITCODE -ne 0) { $failed += "selene" }

Write-Host "== stylua"
stylua --check src
if ($LASTEXITCODE -ne 0) { $failed += "stylua" }

# The sourcemap tells the type checker where each file sits in the game tree.
Write-Host "== luau-lsp"
rojo sourcemap default.project.json --output sourcemap.json
luau-lsp analyze --platform roblox --sourcemap sourcemap.json --definitions "@roblox=$types" --base-luaurc .luaurc src
if ($LASTEXITCODE -ne 0) { $failed += "luau-lsp" }

if ($failed.Count -gt 0) {
	Write-Host "FAILED: $($failed -join ', ')"
	exit 1
}
Write-Host "All checks passed."
