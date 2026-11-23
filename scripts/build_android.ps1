param([string]$JdkPath)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $JdkPath) {
    if ($env:JAVA_HOME -and (Test-Path -LiteralPath (Join-Path $env:JAVA_HOME 'bin\javac.exe'))) {
        $JdkPath = $env:JAVA_HOME
    } else {
        $localJava = Join-Path $projectRoot 'build\tools\java17'
        if (Test-Path -LiteralPath $localJava) {
            $candidate = Get-ChildItem -LiteralPath $localJava -Directory | Select-Object -First 1
            if ($candidate) { $JdkPath = $candidate.FullName }
        }
    }
}
if (-not $JdkPath -or -not (Test-Path -LiteralPath (Join-Path $JdkPath 'bin\javac.exe'))) {
    throw 'Provide a working JDK 17 or later: .\scripts\build_android.ps1 -JdkPath C:\path\to\jdk'
}
$previousJavaHome = $env:JAVA_HOME
Push-Location -LiteralPath $projectRoot
try {
    $env:JAVA_HOME = (Resolve-Path -LiteralPath $JdkPath).Path
    $versionMatch = [regex]::Match((Get-Content -LiteralPath pubspec.yaml -Raw), '(?m)^version:\s*([0-9.]+)\+(\d+)\s*$')
    if (-not $versionMatch.Success) { throw 'Set a version and build number in pubspec.yaml.' }
    $versionName = $versionMatch.Groups[1].Value
    $versionCode = $versionMatch.Groups[2].Value
    $localPropertiesPath = Join-Path $projectRoot 'android/local.properties'
    $localProperties = Get-Content -LiteralPath $localPropertiesPath -Raw
    foreach ($versionProperty in @{ 'flutter.versionName'=$versionName; 'flutter.versionCode'=$versionCode }.GetEnumerator()) {
        $pattern = '(?m)^' + [regex]::Escape($versionProperty.Key) + '=.*$'
        $line = $versionProperty.Key + '=' + $versionProperty.Value
        if ([regex]::IsMatch($localProperties,$pattern)) { $localProperties = [regex]::Replace($localProperties,$pattern,$line) }
        else { $localProperties = $localProperties.TrimEnd() + "`n" + $line + "`n" }
    }
    [IO.File]::WriteAllText($localPropertiesPath,$localProperties,[Text.UTF8Encoding]::new($false))
    $configFile = Join-Path $projectRoot 'config/client.json'
    $config = Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json
    $defines = @()
    foreach ($property in $config.PSObject.Properties) {
        if ($property.Name -notin @('GEMINI_PROXY_URL','NATIVE_API_URL')) { throw 'Only public endpoint URLs belong in client.json. Keep keys in .env.' }
        $defines += [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($property.Name)=$($property.Value)"))
    }
    $defineArgument = '-Pdart-defines=' + ($defines -join ',')
    # Direct Gradle builds can retain a stale Dart snapshot after a web build.
    # Recompile this task explicitly before packaging the Android application.
    & '.\android\gradlew.bat' -p android --console=plain $defineArgument :app:compileFlutterBuildDebug --rerun-tasks
    if ($LASTEXITCODE -ne 0) { throw 'Flutter Android compilation failed.' }
    & '.\android\gradlew.bat' -p android --console=plain $defineArgument assembleDebug
    if ($LASTEXITCODE -ne 0) { throw 'Android build failed.' }
    $apk = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-debug.apk'
    if (-not (Test-Path -LiteralPath $apk)) { throw 'Build finished but the APK was not found.' }
    $releaseFolder = Join-Path $projectRoot 'build/releases'
    New-Item -ItemType Directory -Path $releaseFolder -Force | Out-Null
    $versionedApk = Join-Path $releaseFolder "Planova-$versionName-debug.apk"
    Copy-Item -LiteralPath $apk -Destination $versionedApk -Force
    Write-Output "APK: $versionedApk (build $versionCode)"
} finally {
    $env:JAVA_HOME = $previousJavaHome
    Pop-Location
}
