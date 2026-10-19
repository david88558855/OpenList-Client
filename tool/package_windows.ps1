# Windows 发行：安装版（Inno Setup）+ 便携版（zip）
param(
    [string]$Flutter = "flutter",
    [string]$Version = "1.0.0"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

if (-not (Test-Path "windows\runner\main.cpp")) {
    Write-Host "==> 未发现 windows/ 工程，先执行 tool/bootstrap_windows.ps1" -ForegroundColor Yellow
    & "$root\tool\bootstrap_windows.ps1" -Flutter $Flutter
}

& $Flutter build windows --release
$bundle = "build\windows\x64\runner\Release"
if (-not (Test-Path $bundle)) { throw "构建产物不存在：$bundle" }

$dist = "dist"
New-Item -ItemType Directory -Force -Path $dist | Out-Null

# 便携版：直接压缩 Release 目录，userdata/ 与 exe 同级
$portable = Join-Path $dist "OpenList-Client-$Version-portable"
if (Test-Path $portable) { Remove-Item -Recurse -Force $portable }
Copy-Item -Recurse $bundle $portable
New-Item -ItemType Directory -Force -Path (Join-Path $portable "userdata") | Out-Null
Compress-Archive -Path "$portable\*" -DestinationPath "$dist\OpenList-Client-$Version-portable.zip" -Force

# 安装版：Inno Setup（如已安装 ISCC）
$iscc = "C:/Program Files (x86)/Inno Setup 6/ISCC.exe"
if (Test-Path $iscc) {
    & $iscc "/DMyAppVersion=$Version" "installer\openlist-client.iss"
} else {
    Write-Host "未安装 Inno Setup，跳过安装版；便携版已生成。" -ForegroundColor Yellow
}

Get-ChildItem $dist | Format-Table Name, Length
