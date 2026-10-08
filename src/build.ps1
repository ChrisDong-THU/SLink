# Compatibility entry point; new checkouts should use the root build.ps1.
& (Join-Path (Split-Path $PSScriptRoot) 'build.ps1') @args
if ($LASTEXITCODE) { exit $LASTEXITCODE }