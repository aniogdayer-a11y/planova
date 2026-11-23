param([switch]$NoPub)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
try {
    # Flutter 3.32 does not track plugin dependencies for this cached target.
    # Regenerate the web entry point when building so new plugins are registered.
    $cacheRoot = Join-Path $projectRoot '.dart_tool/flutter_build'
    if (Test-Path -LiteralPath $cacheRoot) {
        foreach ($folder in Get-ChildItem -LiteralPath $cacheRoot -Directory) {
            $stamp = Join-Path $folder.FullName 'web_entrypoint.stamp'
            if (Test-Path -LiteralPath $stamp) { Remove-Item -LiteralPath $stamp }
        }
    }
    $arguments = @('build','web','--pwa-strategy=none','--no-web-resources-cdn','--dart-define-from-file=config/client.json')
    if ($NoPub) { $arguments += '--no-pub' }
    & flutter @arguments
    if ($LASTEXITCODE -ne 0) { throw 'Website build failed.' }
} finally { Pop-Location }
