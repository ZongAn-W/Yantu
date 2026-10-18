# 一次性配置：生成部署专用 SSH 密钥 -> 写入 ~/.ssh/config -> 打印需要粘贴到服务器的公钥
#
# 用法：npm run deploy:key
# 之后把打印出来的那行命令粘贴到阿里云 Workbench（服务器 root shell）执行一次即可。
[CmdletBinding()]
param(
    [string]$ServerHost = '47.116.63.161',
    [string]$ServerUser = 'root',
    [string]$SshAlias = 'yantu',
    [string]$KeyPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($KeyPath)) {
    $KeyPath = Join-Path $env:USERPROFILE '.ssh\id_ed25519_yantu'
}
$KeyPath = [IO.Path]::GetFullPath($KeyPath)
$sshDir = Split-Path -Parent $KeyPath
if (-not (Test-Path -LiteralPath $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
}

Write-Host "服务器:  $ServerUser@$ServerHost"
Write-Host "别名:    $SshAlias"
Write-Host "密钥:    $KeyPath"
Write-Host ''

# 1. 生成密钥（已有则复用）
if (Test-Path -LiteralPath $KeyPath) {
    Write-Host '已存在部署密钥，跳过生成。'
}
else {
    Write-Host '正在生成 SSH 部署密钥。' -ForegroundColor Cyan
    Write-Host '提示：passphrase（密码）直接按两次回车留空，否则自动部署会失败。'
    & ssh-keygen -t ed25519 -C 'yantu-deploy' -f $KeyPath
    if ($LASTEXITCODE -ne 0) { throw 'ssh-keygen 生成密钥失败' }
}
$publicKeyPath = "$KeyPath.pub"
if (-not (Test-Path -LiteralPath $publicKeyPath)) { throw "找不到公钥文件：$publicKeyPath" }
$publicKey = (Get-Content -LiteralPath $publicKeyPath -Raw).Trim()

# 2. 写入 ~/.ssh/config（如果还没有这个 Host）
$configPath = Join-Path $sshDir 'config'
$configText = ''
if (Test-Path -LiteralPath $configPath) { $configText = Get-Content -LiteralPath $configPath -Raw }
$aliasPattern = '(?m)^\s*Host\s+' + [regex]::Escape($SshAlias) + '\s*$'
if ($configText -notmatch $aliasPattern) {
    $keyForConfig = $KeyPath -replace '\\', '/'
    $block = "`r`nHost $SshAlias`r`n  HostName $ServerHost`r`n  User $ServerUser`r`n  IdentityFile $keyForConfig`r`n  IdentitiesOnly yes`r`n"
    Add-Content -LiteralPath $configPath -Value $block -Encoding UTF8
    Write-Host "已写入 SSH 配置：Host $SshAlias" -ForegroundColor Green
}
else {
    Write-Host "SSH 配置已包含 Host $SshAlias"
}

# 3. 打印一次性公钥安装命令
Write-Host ''
Write-Host '=== 一次性配置（在服务器上执行一次）===' -ForegroundColor Yellow
Write-Host '打开阿里云 Workbench（或任意 root shell），把下面这一整行粘贴执行：'
Write-Host ''
Write-Host "mkdir -p /root/.ssh && chmod 700 /root/.ssh && echo '$publicKey' >> /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys"
Write-Host ''
Write-Host '说明：'
Write-Host '  - 私钥只保存在本机，不会上传到服务器或仓库；'
Write-Host '  - 之后每次部署都靠这把密钥免密登录，不再需要密码。'

# 4. 立即测试
Write-Host ''
Write-Host '=== 连接测试 ===' -ForegroundColor Yellow
$probe = & ssh -o BatchMode=yes -o ConnectTimeout=12 -o StrictHostKeyChecking=accept-new $SshAlias 'echo SSH_OK' 2>&1
if ($LASTEXITCODE -eq 0 -and (($probe -join "`n") -match 'SSH_OK')) {
    Write-Host 'SSH 免密登录已生效，现在可以直接运行：npm run deploy' -ForegroundColor Green
}
else {
    Write-Host '尚未生效：请先在服务器执行上面那行命令，然后重新运行 npm run deploy:key 验证。' -ForegroundColor Yellow
}
