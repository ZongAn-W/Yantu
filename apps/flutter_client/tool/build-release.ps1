[CmdletBinding()]
param(
    [string]$FlutterSdk = 'D:\tools\flutter',
    [string]$ApiBaseUrl = '',
    [ValidateSet('Web', 'Windows', 'Android', 'All')]
    [string]$Target = 'All',
    [ValidateSet('Debug', 'Release', 'Both')]
    [string]$Mode = 'Release',
    [switch]$SkipTests,
    [switch]$SkipAnalyze,
    [switch]$PrepareOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sdkRoot = [IO.Path]::GetFullPath($FlutterSdk)
$flutterExecutable = Join-Path $sdkRoot 'bin\flutter.bat'
if (-not (Test-Path -LiteralPath $flutterExecutable -PathType Leaf)) {
    throw "Flutter SDK was not found: $flutterExecutable. Set -FlutterSdk to its directory."
}
if ([string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
    throw 'ApiBaseUrl is required. Example: .\tool\build-release.ps1 -ApiBaseUrl https://api.example.com. The value is compiled into the client and must never contain a secret.'
}
if ($ApiBaseUrl -match '\s') {
    throw "ApiBaseUrl must not contain whitespace: '$ApiBaseUrl'."
}
if ($ApiBaseUrl -match '\.(pem|key|p12|jks|keystore)$') {
    throw "ApiBaseUrl looks like a credential path, not an API origin: '$ApiBaseUrl'."
}

$toolRoot = Join-Path $projectRoot '.dart_tool'
$cacheRoot = Join-Path $toolRoot 'pub-cache'
$logRoot = Join-Path $toolRoot 'build-logs'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$logPath = Join-Path $logRoot "build-$stamp.log"
$originalEnvironment = @{}
$originalConsoleEncoding = [Console]::OutputEncoding
$originalPipelineEncoding = $OutputEncoding
foreach ($name in @('Path', 'PUB_CACHE', 'PUB_HOSTED_URL', 'FLUTTER_STORAGE_BASE_URL', 'FLUTTER_ROOT')) {
    $originalEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

function Invoke-Flutter {
    param([string[]]$FlutterArguments)
    $previousPreference = $ErrorActionPreference
    try {
        # Forward both native streams as text for complete PowerShell 5 transcripts.
        $ErrorActionPreference = 'Continue'
        & $flutterExecutable @FlutterArguments 2>&1 | ForEach-Object {
            Write-Host $_.ToString()
        }
        $flutterExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($flutterExitCode -ne 0) {
        throw "flutter $($FlutterArguments -join ' ') failed (exit $flutterExitCode). Log: $logPath"
    }
}

$artifactRoot = Join-Path $projectRoot 'build'
$artifacts = [System.Collections.Generic.List[string]]::new()

function Add-Artifact {
    param([string]$Path, [string]$Description)
    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path
        $size = if ($item.PSIsContainer) {
            [math]::Round(((Get-ChildItem -LiteralPath $Path -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB), 2)
        }
        else {
            [math]::Round($item.Length / 1MB, 2)
        }
        $artifacts.Add(("{0}  ({1} MB)  {2}" -f $item.FullName, $size, $Description))
    }
    else {
        $artifacts.Add(("MISSING: {0}  {1}" -f $Path, $Description))
    }
}

$transcribing = $false
Push-Location $projectRoot
try {
    Start-Transcript -LiteralPath $logPath | Out-Null
    $transcribing = $true
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $OutputEncoding = [Console]::OutputEncoding
    $env:Path = (Join-Path $sdkRoot 'bin') + ';' + $env:Path
    $env:FLUTTER_ROOT = $sdkRoot
    $env:PUB_CACHE = $cacheRoot
    $env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
    $env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'

    Write-Host "Project:       $projectRoot"
    Write-Host "Flutter SDK:   $flutterExecutable"
    Write-Host "API base URL:  $ApiBaseUrl"
    Write-Host "Targets:       $Target ($Mode)"
    Write-Host "Build log:     $logPath"
    Invoke-Flutter -FlutterArguments @('--version')

    Invoke-Flutter -FlutterArguments @('pub', 'get', '--enforce-lockfile')

    if (-not $SkipAnalyze) {
        Invoke-Flutter -FlutterArguments @('analyze', '--no-pub')
    }
    if (-not $SkipTests) {
        Invoke-Flutter -FlutterArguments @('test', '--no-pub')
    }

    if ($PrepareOnly) {
        Write-Host 'PrepareOnly: dependencies, analysis and tests finished; no build executed.'
        return
    }

    $modes = switch ($Mode) {
        'Debug' { @('debug') }
        'Release' { @('release') }
        'Both' { @('debug', 'release') }
    }

    foreach ($buildMode in $modes) {
        if ($Target -in @('Web', 'All')) {
            $arguments = [System.Collections.Generic.List[string]]::new()
            $arguments.AddRange([string[]]@('build', 'web', '--no-pub', '--no-web-resources-cdn', "--dart-define=API_BASE_URL=$ApiBaseUrl"))
            if ($buildMode -eq 'release') { $arguments.Add('--release') } else { $arguments.Add('--debug') }
            Invoke-Flutter -FlutterArguments $arguments.ToArray()
            Add-Artifact (Join-Path $artifactRoot 'web\index.html') "Web entry ($buildMode)"
            Add-Artifact (Join-Path $artifactRoot 'web\main.dart.js') "Web bundle ($buildMode)"
            Add-Artifact (Join-Path $artifactRoot 'web\manifest.json') "Web PWA manifest ($buildMode)"
        }
        if ($Target -in @('Windows', 'All')) {
            $arguments = [System.Collections.Generic.List[string]]::new()
            $arguments.AddRange([string[]]@('build', 'windows', '--no-pub', "--dart-define=API_BASE_URL=$ApiBaseUrl"))
            if ($buildMode -eq 'release') { $arguments.Add('--release') } else { $arguments.Add('--debug') }
            Invoke-Flutter -FlutterArguments $arguments.ToArray()
            $runnerRoot = if ($buildMode -eq 'release') { 'windows\x64\runner\Release' } else { 'windows\x64\runner\Debug' }
            Add-Artifact (Join-Path $artifactRoot "$runnerRoot\sjtu_study_planner_client.exe") "Windows executable ($buildMode)"
            Add-Artifact (Join-Path $artifactRoot "$runnerRoot\data") "Windows data directory ($buildMode)"
        }
        if ($Target -in @('Android', 'All')) {
            $androidSdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } elseif ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { $null }
            if (-not $androidSdk) {
                Write-Warning 'Android SDK not configured (ANDROID_HOME / ANDROID_SDK_ROOT is unset). Skipping the Android build; install the SDK and run `flutter doctor` first.'
                $artifacts.Add('SKIPPED: Android build (no Android SDK on this machine)')
                continue
            }
            $arguments = [System.Collections.Generic.List[string]]::new()
            $arguments.AddRange([string[]]@('build', 'apk', '--no-pub', "--dart-define=API_BASE_URL=$ApiBaseUrl"))
            if ($buildMode -eq 'release') { $arguments.Add('--release') } else { $arguments.Add('--debug') }
            Invoke-Flutter -FlutterArguments $arguments.ToArray()
            $apkName = if ($buildMode -eq 'release') { 'app-release.apk' } else { 'app-debug.apk' }
            Add-Artifact (Join-Path $artifactRoot "app\outputs\flutter-apk\$apkName") "Android APK ($buildMode)"
        }
    }

    Write-Host ''
    Write-Host '=== Artifacts ==='
    foreach ($line in $artifacts) { Write-Host $line }
    Write-Host ''
    Write-Host "Build log: $logPath"
}
finally {
    [Console]::OutputEncoding = $originalConsoleEncoding
    $OutputEncoding = $originalPipelineEncoding
    foreach ($name in $originalEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $originalEnvironment[$name], 'Process')
    }
    if ($transcribing) {
        Stop-Transcript | Out-Null
    }
    Pop-Location
}
