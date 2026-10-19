# 一键部署：本机构建 Flutter Web -> 打包 -> 上传 -> 服务器执行 upgrade-server.sh --check/--apply -> 健康检查
#
# 用法：
#   npm run deploy                    # 完整部署（先构建，再发布）
#   npm run deploy -- -CheckOnly      # 只做服务器只读检查，不改变任何东西
#   npm run deploy -- -SkipBuild      # 复用已有的 apps/flutter_client/build/web
#   npm run deploy -- -FullCheck      # 额外运行 npm test（Flutter 测试默认跳过）
#
# 首次使用先运行 npm run deploy:key 配置服务器 SSH 免密登录。
[CmdletBinding()]
param(
    [string]$ApiOrigin = 'https://47.116.63.161',
    [string]$SshTarget = 'yantu',
    [string]$ReleaseId = '',
    [string]$FlutterSdk = 'D:\tools\flutter',
    [string]$ProjectDir = '/opt/sjtu-study-planner',
    [switch]$CheckOnly,
    [switch]$FullCheck,
    [switch]$SkipBuild
)

Set-StrictMode -Version Latest
# 注意：Windows PowerShell 5.1 下 native 命令写 stderr 时，$ErrorActionPreference='Stop' 会直接抛错
# （scp 进度、ssh 提示都会走 stderr），所以这里用 Continue，失败靠显式退出码检查处理。
$ErrorActionPreference = 'Continue'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sshOptions = @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15', '-o', 'StrictHostKeyChecking=accept-new')
$tempFiles = New-Object System.Collections.Generic.List[string]

function Write-Step {
    param([string]$Message)
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Invoke-Checked {
    param([string]$What, [scriptblock]$Command)
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$What 失败（退出码 $LASTEXITCODE）"
    }
}

$failureMessage = $null
Push-Location $root
try {
    if ($ApiOrigin -notmatch '^https://[^/\s]+$') {
        throw "ApiOrigin 必须是不带路径的 https 地址，例如 https://47.116.63.161（当前：$ApiOrigin）"
    }
    $sha = (& git rev-parse --short HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw '读取 git HEAD 失败' }
    if ([string]::IsNullOrWhiteSpace($ReleaseId)) {
        $ReleaseId = (Get-Date -Format 'yyyyMMdd-HHmm') + '-' + $sha
    }
    if ($ReleaseId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') {
        throw "ReleaseId 只能包含字母、数字、点、下划线、短横线：$ReleaseId"
    }

    Write-Host "项目目录:   $root"
    Write-Host "发布 ID:    $ReleaseId"
    Write-Host "API 地址:   $ApiOrigin"
    Write-Host "服务器:     $SshTarget"
    Write-Host "模式:       $(if ($CheckOnly) { '只读检查（--check）' } else { '发布（--check + --apply）' })"

    # 1. SSH 连通性（失败时快速提示，而不是构建完才发现）
    Write-Step '检查服务器 SSH 免密登录'
    $probe = & ssh @sshOptions $SshTarget 'echo SSH_OK' 2>&1
    if (($LASTEXITCODE -ne 0) -or (($probe -join "`n") -notmatch 'SSH_OK')) {
        throw @'
无法免密 SSH 到服务器。请先运行一次：

    npm run deploy:key

然后按提示把公钥追加到服务器的 /root/.ssh/authorized_keys，再重试。
'@
    }
    $remoteHost = ((& ssh @sshOptions $SshTarget 'hostname') -join '').Trim()
    Write-Host "服务器连接正常：$remoteHost"

    # 2. 工作区状态提示（发布包使用当前工作区内容）
    $dirty = (& git status --porcelain) -join ''
    if ($dirty.Trim().Length -gt 0) {
        Write-Warning '工作区有未提交改动：发布包会包含当前工作区内容（与之前的手动发布一致）。'
    }

    # 3. 本地检查
    Write-Step 'TypeScript 类型检查'
    Invoke-Checked 'npm run typecheck' { & npm run typecheck }
    if ($FullCheck) {
        Write-Step '单元测试（npm test）'
        Invoke-Checked 'npm test' { & npm test }
    }

    # 4. 构建 Flutter Web
    if ($SkipBuild) {
        Write-Step '跳过 Flutter Web 构建（使用现有 build/web）'
    }
    else {
        Write-Step '构建 Flutter Web（Release，API_BASE_URL 已编译进产物）'
        & (Join-Path $root 'apps/flutter_client/tool/build-release.ps1') -FlutterSdk $FlutterSdk -ApiBaseUrl $ApiOrigin -Target Web -Mode Release -SkipTests
    }
    if (-not (Test-Path -LiteralPath (Join-Path $root 'apps/flutter_client/build/web/main.dart.js'))) {
        throw '缺少 apps/flutter_client/build/web/main.dart.js，请先构建 Web 客户端'
    }

    # 5. 打包发布包（只含源码 + Web，不含 .env / 数据库 / 镜像）
    Write-Step '打包发布包'
    Invoke-Checked 'node tools/prepare-release.mjs' { & node (Join-Path $root 'tools/prepare-release.mjs') "--release-id=$ReleaseId" "--api-origin=$ApiOrigin" }
    $bundle = Join-Path $root "output/releases/study-planner-$ReleaseId.tar.gz"
    $bundleHash = "$bundle.sha256"
    if (-not (Test-Path -LiteralPath $bundle)) { throw "未生成发布包：$bundle" }
    $bundleName = Split-Path -Leaf $bundle
    $bundleSize = [math]::Round((Get-Item -LiteralPath $bundle).Length / 1MB, 1)
    Write-Host "发布包：$bundleName ($bundleSize MB)"

    # 6. 生成远程执行脚本（LF 换行，避免 Windows CRLF 破坏 bash）
    $remoteScript = @'
set -euo pipefail
release_id="__RELEASE_ID__"
project="__PROJECT_DIR__"
remote_tar="__REMOTE_TAR__"
remote_sha="__REMOTE_SHA__"
apply="__APPLY__"
test -s "$remote_tar" || { echo "release bundle not found: $remote_tar" >&2; exit 1; }
cd /tmp
sha256sum -c "$(basename "$remote_sha")" >/dev/null
echo "发布包校验通过"
mkdir -p "$project/releases/$release_id"
tar -xzf "$remote_tar" -C "$project/releases/$release_id"
echo ""
echo "=== upgrade-server.sh --check ==="
bash "$project/releases/$release_id/upgrade-server.sh" --check
if [ "$apply" = "1" ]; then
  echo ""
  echo "=== upgrade-server.sh --apply ==="
  bash "$project/releases/$release_id/upgrade-server.sh" --apply
  rm -f -- "$remote_tar"
  rm -f -- "$remote_sha"
fi
rm -f -- "__REMOTE_SCRIPT__"
echo "REMOTE_DEPLOY_DONE release=$release_id apply=$apply"
'@
    $remoteTar = "/tmp/" + $bundleName
    $remoteSha = $remoteTar + '.sha256'
    $remoteScriptPath = "/tmp/yantu-remote-deploy-$ReleaseId.sh"
    $applyFlag = if ($CheckOnly) { '0' } else { '1' }
    $remoteScript = $remoteScript.Replace('__RELEASE_ID__', $ReleaseId)
    $remoteScript = $remoteScript.Replace('__PROJECT_DIR__', $ProjectDir)
    $remoteScript = $remoteScript.Replace('__REMOTE_TAR__', $remoteTar)
    $remoteScript = $remoteScript.Replace('__REMOTE_SHA__', $remoteSha)
    $remoteScript = $remoteScript.Replace('__REMOTE_SCRIPT__', $remoteScriptPath)
    $remoteScript = $remoteScript.Replace('__APPLY__', $applyFlag)
    $localRemoteScript = Join-Path $env:TEMP ("yantu-remote-deploy-$ReleaseId.sh")
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($localRemoteScript, ($remoteScript -replace "`r`n", "`n"), $utf8NoBom)
    $tempFiles.Add($localRemoteScript)

    # 7. 上传
    Write-Step '上传发布包到服务器'
    Invoke-Checked 'scp 发布包' { & scp @sshOptions $bundle $bundleHash $localRemoteScript "${SshTarget}:/tmp/" }
    Write-Host '上传完成'

    # 8. 远程执行
    Write-Step $(if ($CheckOnly) { '服务器只读检查（不改变任何东西）' } else { '服务器发布（自动备份，失败自动回滚）' })
    & ssh @sshOptions $SshTarget "bash $remoteScriptPath"
    $remoteCode = $LASTEXITCODE
    if ($remoteCode -ne 0) {
        throw "服务器部署失败（退出码 $remoteCode）。查看上面的日志；服务器会自动回滚，备份在 $ProjectDir/backups/$ReleaseId-*"
    }

    # 9. 线上验证
    if (-not $CheckOnly) {
        Write-Step '验证线上 API（经 Nginx）'
        $healthUrl = "$ApiOrigin/api/health"
        $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
        if (-not $curl) { throw '找不到 curl.exe，无法验证线上 API' }
        $healthy = $false
        for ($attempt = 1; $attempt -le 30; $attempt++) {
            $rawCode = & curl.exe -k -s -o NUL -w '%{http_code}' --max-time 8 $healthUrl 2>$null
            $code = "$rawCode".Trim()
            if ($code -eq '200') { $healthy = $true; break }
            Start-Sleep -Seconds 2
        }
        if (-not $healthy) { throw "线上健康检查未通过：$healthUrl" }
        Write-Host "线上健康检查通过：$healthUrl -> 200"

        $rawVersion = & curl.exe -k -s --max-time 8 "$ApiOrigin/version.json" 2>$null
        $version = "$rawVersion".Trim()
        if ($version) { Write-Host "Web 版本信息：$version" }
    }

    Write-Host ''
    Write-Host '部署完成。' -ForegroundColor Green
    Write-Host "发布 ID：   $ReleaseId"
    Write-Host "服务器备份：$ProjectDir/backups/$ReleaseId-*"
    if (-not $CheckOnly) {
        Write-Host '下一步：浏览器 Ctrl+F5 强刷；如果是新注册流程，用真实邮箱发一次验证码确认 SMTP 正常。'
    }
}
catch {
    $failureMessage = $_.Exception.Message
}
finally {
    foreach ($file in $tempFiles) {
        if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
    }
    Pop-Location
}

if ($failureMessage) {
    Write-Host ''
    Write-Host "部署失败：$failureMessage" -ForegroundColor Red
    exit 1
}
