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
    $pubspec = Get-Content -Raw -Path "pubspec.yaml"
    if ($pubspec -match '(?m)^version:[ \t]*([0-9]+[.][0-9]+[.][0-9]+)') {
        $Version = $Matches[1]
    } else {
        throw "无法从 pubspec.yaml 解析版本号"
    }
}

# windows/ 平台目录不入库：由 Flutter 官方模板在本机/CI 生成，避免与当前 SDK 版本错配。
if (-not (Test-Path "windows\runner\main.cpp")) {
    Write-Host "==> 未发现 windows/ 工程，用 Flutter 官方模板生成" -ForegroundColor Cyan
    & $Flutter create --platforms=windows --org com.openlist --project-name openlist_client .
    if ($LASTEXITCODE -ne 0) { throw "flutter create --platforms=windows 失败" }
}

# 程序图标与 Android 启动图标同源（assets/windows/app_icon.ico，由 tool/gen_app_icons.py 生成）
$iconSrc = "assets\windows\app_icon.ico"
if (Test-Path $iconSrc) {
    Copy-Item $iconSrc "windows\runner\resources\app_icon.ico" -Force
    Write-Host "==> 已应用程序图标（与 Android 启动图标一致）"
}

Write-Host "== OpenList Client $Version · Windows x64 portable =="

# 设计稿硬隔离（永久规则）：编译前物理剔除 design/ 及其下所有文件。
# 不依赖 pubspec 白名单，也不依赖打包器"碰巧"不读它 —— 编译期该目录根本不存在。
if (Test-Path "design") {
    $cnt = (Get-ChildItem -Recurse -File "design" -ErrorAction SilentlyContinue | Measure-Object).Count
    Write-Host "==> 剔除 design/（$cnt 个文件）：仅视觉参照，永不参与编译" -ForegroundColor Cyan
    Remove-Item -Recurse -Force "design"
}

& $Flutter config --no-analytics | Out-Null
& $Flutter --version
if ($LASTEXITCODE -ne 0) { throw "flutter --version 失败" }
& $Flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get 失败" }
& $Flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "flutter build windows 失败" }

$bundle = "build\windows\x64\runner\Release"
if (-not (Test-Path $bundle)) { throw "构建产物不存在：$bundle" }

# 设计稿隔离断言：design/ 编译期必须不存在，且不应出现在资源里
if (Test-Path "design") { throw "FAIL: 编译结束后 design/ 仍存在，剔除步骤未生效" }
if (Test-Path (Join-Path $bundle "data\flutter_assets\design")) {
    throw "FAIL: 设计稿进入了 flutter_assets"
}

New-Item -ItemType Directory -Force -Path dist | Out-Null
$name = "OpenList-Client-$Version-windows-x64-portable"
$stage = Join-Path "dist" $name
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
Copy-Item -Recurse $bundle $stage
New-Item -ItemType Directory -Force -Path (Join-Path $stage "userdata") | Out-Null

$zip = Join-Path "dist" "$name.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Compress-Archive -Path "$stage\*" -DestinationPath $zip -Force
Remove-Item -Recurse -Force $stage

$hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
"$hash  $name.zip" | Out-File -Encoding ascii "$zip.sha256"
Write-Host "OK: $zip ($((Get-Item $zip).Length) 字节)"
Write-Host "SHA256: $hash"
