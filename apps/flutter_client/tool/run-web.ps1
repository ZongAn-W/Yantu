[CmdletBinding()]
param(
    [string]$FlutterSdk = 'D:\tools\flutter',
    [ValidateRange(1024, 65535)]
    [int]$Port = 5180,
    [string]$ApiBaseUrl = 'http://127.0.0.1:8787',
    [ValidateSet('Debug', 'Release')]
    [string]$Mode = 'Debug',
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

$toolRoot = Join-Path $projectRoot '.dart_tool'
$cacheRoot = Join-Path $toolRoot 'pub-cache'
$logRoot = Join-Path $toolRoot 'startup-logs'
$statePath = Join-Path $toolRoot 'web-launcher.json'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$logPath = Join-Path $logRoot "web-$stamp.log"
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

    Write-Host "Project: $projectRoot"
    Write-Host "Flutter: $flutterExecutable"
    Write-Host "Dependency cache: $cacheRoot"
    Write-Host "Startup log: $logPath"
    Invoke-Flutter -FlutterArguments @('--version')

    $sdkVersion = Get-Content -Raw -LiteralPath (Join-Path $sdkRoot 'bin\cache\flutter.version.json') | ConvertFrom-Json
    $identity = $sdkVersion.frameworkRevision + '|' + $cacheRoot
    $previousIdentity = $null
    if (Test-Path -LiteralPath $statePath) {
        $previousIdentity = (Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json).identity
    }
    $configurationMatches = $false
    $packageConfigPath = Join-Path $toolRoot 'package_config.json'
    if (Test-Path -LiteralPath $packageConfigPath) {
        try {
            $previousConfig = Get-Content -Raw -LiteralPath $packageConfigPath | ConvertFrom-Json
            $configuredCache = ([Uri]$previousConfig.pubCache).LocalPath.TrimEnd('\')
            $configurationMatches = $configuredCache.Equals($cacheRoot, [StringComparison]::OrdinalIgnoreCase)
        }
        catch {
            Write-Host 'Package configuration will be regenerated.'
        }
    }
    if ($previousIdentity -ne $identity -or -not $configurationMatches) {
        # Preserve one complete build directory when the SDK or package location changes.
        $buildPath = [IO.Path]::GetFullPath((Join-Path $projectRoot 'build'))
        $backupPath = [IO.Path]::GetFullPath((Join-Path $toolRoot "web-recovery\build-$stamp"))
        $projectPrefix = $projectRoot.TrimEnd('\') + '\'
        foreach ($checkedPath in @($buildPath, $backupPath)) {
            if (-not $checkedPath.StartsWith($projectPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Cache path is outside the project: $checkedPath"
            }
        }
        if (Test-Path -LiteralPath $buildPath) {
            if ((Get-Item -LiteralPath $buildPath).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Refusing to move a linked build directory: $buildPath"
            }
            New-Item -ItemType Directory -Path (Split-Path -Parent $backupPath) -Force | Out-Null
            Move-Item -LiteralPath $buildPath -Destination $backupPath
            Write-Host "Previous build preserved: $backupPath"
        }
    }

    Invoke-Flutter -FlutterArguments @('pub', 'get', '--enforce-lockfile')
    $packageConfig = Get-Content -Raw -LiteralPath (Join-Path $toolRoot 'package_config.json') | ConvertFrom-Json
    foreach ($packageName in @('meta', 'vector_math', 'flutter_riverpod')) {
        $package = $packageConfig.packages | Where-Object { $_.name -eq $packageName }
        if (-not $package) {
            throw "The package configuration is missing $packageName. Log: $logPath"
        }
        $packagePath = ([Uri]$package.rootUri).LocalPath
        $cachePrefix = $cacheRoot.TrimEnd('\') + '\'
        if (-not $packagePath.StartsWith($cachePrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "The package resolves outside the isolated cache: $packagePath"
        }
        $libraryPath = Join-Path $packagePath "lib\$packageName.dart"
        if (-not (Test-Path -LiteralPath $libraryPath -PathType Leaf) -or (Get-Item -LiteralPath $libraryPath).Length -eq 0) {
            throw "A required package library is missing or empty: $libraryPath"
        }
    }
    @{ identity = $identity; sdk = $sdkRoot; cache = $cacheRoot } |
        ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8

    if (-not $PrepareOnly) {
        $runArguments = @('run', '-d', 'chrome', '--web-hostname=127.0.0.1', "--web-port=$Port", "--dart-define=API_BASE_URL=$ApiBaseUrl", '--no-pub', '--no-web-resources-cdn')
        if ($Mode -eq 'Release') {
            $runArguments += '--release'
        } else {
            # Flutter 3.47 DDC hot reload can retain stale IndexedDB notification types.
            $runArguments += '--no-web-experimental-hot-reload'
        }
        Invoke-Flutter -FlutterArguments $runArguments
    }
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
