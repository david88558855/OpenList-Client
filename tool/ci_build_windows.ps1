# Windows 便携版构建：只产出 zip，不生成任何安装程序。
# 运行环境：Windows + Visual Studio（Desktop development with C++）+ Flutter SDK。
param(
    [string]$Flutter = "flutter",
    [string]$Version = ""
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

if (-not $Version) {
    $match = Select-String -Path "pubspec.yaml" -Pattern '^version:/s*([0-9]+/.[0-9]+/.[0-9]+)' | Select-Object -First 1
    if ($match) { $Version = $match.Matches[0].Groups[1].Value } else { $Version = "0.0.0" }
}

# windows/ 平台目录不入库：由 Flutter 官方模板在本机/CI 生成，避免与当前 SDK 版本错配。
if (-not (Test-Path "windows\runner\main.cpp")) {
    Write-Host "==> 未发现 windows/ 工程，用 Flutter 官方模板生成" -ForegroundColor Cyan
    & $Flutter create --platforms=windows --org com.openlist --project-name openlist_client .
    if ($LASTEXITCODE -ne 0) { throw "flutter create --platforms=windows 失败" }
}

Write-Host "== OpenList Client $Version · Windows x64 portable =="
& $Flutter config --no-analytics | Out-Null
& $Flutter --version
if ($LASTEXITCODE -ne 0) { throw "flutter --version 失败" }
& $Flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get 失败" }
& $Flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "flutter build windows 失败" }

$bundle = "build\windows\x64\runner\Release"
if (-not (Test-Path $bundle)) { throw "构建产物不存在：$bundle" }

# 设计稿隔离断言：design/ 不应出现在资源里
if (Test-Path (Join-Path $bundle "data\flutter_assets\design")) {
    throw "FAIL: 设计稿进入了 flutter_assets"
}

New-Item -ItemType Directory -Force -Path dist | Out-Null
$name = "OpenList-Client-$Version-windows-x64-portable"
$stage = Join-Path "dist" $name
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
Copy-Item -Recurse $bundle $stage
New-Item -ItemType Directory -Force -Path (Join-Path $stage "userdata") | Out-Null

$zip = "dist\$name.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path "$stage\*" -DestinationPath $zip -Force
Remove-Item -Recurse -Force $stage

$hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
"$hash  $name.zip" | Out-File -Encoding ascii "$zip.sha256"
Write-Host "OK: $zip ($((Get-Item $zip).Length) 字节)"
Write-Host "SHA256: $hash"
