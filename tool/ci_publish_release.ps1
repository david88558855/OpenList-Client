# 把 dist/*.zip（Windows 便携版）作为附件发布到当前 tag 对应的 CNB Release。
# 依赖：CNB_TOKEN（流水线内置令牌）、git。
param([string]$Tag = "")
$ErrorActionPreference = "Stop"

$api = "https://api.cnb.cool"
$repo = "haoxuanhaoxuan/OpenList-Client"
$token = $env:CNB_TOKEN
if (-not $token) { throw "缺少 CNB_TOKEN，无法上传发行附件" }

function Normalize-Tag([string]$value) {
    if (-not $value) { return "" }
    $t = $value.Trim()
    $t = $t -replace '^refs/tags/', ''
    $t = $t -replace '^refs/heads/', ''
    $t = $t -replace '-\d+-g[0-9a-f]+$', ''
    return $t.Trim()
}

$candidates = @()
if ($Tag) { $candidates += $Tag }
if ($env:CNB_TAG) { $candidates += $env:CNB_TAG }
if ($env:CNB_BRANCH) { $candidates += $env:CNB_BRANCH }
try { $d = git describe --tags --exact-match 2>$null; if ($d) { $candidates += $d } } catch { }
$candidates = $candidates |
    ForEach-Object { Normalize-Tag $_ } |
    Where-Object { $_ -like 'v*' } |
    Select-Object -Unique
if (-not $candidates) { Write-Host "当前提交没有可识别的 tag，跳过发布"; exit 0 }
Write-Host "== 候选 tag: $($candidates -join ', ') =="

$headers = @{ Authorization = "Bearer $token"; Accept = "application/json" }
$releaseId = $null
$tagName = $null
for ($i = 1; $i -le 8 -and -not $releaseId; $i++) {
    foreach ($candidate in $candidates) {
        try {
            $rel = Invoke-RestMethod -Uri "$api/$repo/-/releases/tags/$candidate" -Headers $headers -Method Get
            $body = if ($rel.data) { $rel.data } else { $rel }
            if ($body.id) { $releaseId = $body.id; $tagName = $candidate; break }
        } catch {
            # 未就绪，继续尝试下一个候选
        }
    }
    if (-not $releaseId) {
        Write-Host "Release 尚未就绪，$i/8 次重试…"
        Start-Sleep -Seconds 15
    }
}
if (-not $releaseId) { throw "上述 tag 都没有对应的 Release（请先在 CNB 创建发行版）" }
Write-Host "tag=$tagName release_id=$releaseId"

$files = Get-ChildItem "dist\*.zip" -ErrorAction SilentlyContinue
if (-not $files) { throw "dist\ 下没有 zip，构建产物未传递到发布阶段" }

foreach ($file in $files) {
    $size = $file.Length
    Write-Host "--> 上传 $($file.Name) ($size 字节)"
    $payload = @{ asset_name = $file.Name; size = $size; overwrite = $true } | ConvertTo-Json
    $up = Invoke-RestMethod -Uri "$api/$repo/-/releases/$releaseId/asset-upload-url" -Headers $headers -Method Post -Body $payload -ContentType "application/json"
    if (-not $up.upload_url) { throw "申请上传地址失败" }
    Invoke-WebRequest -Uri $up.upload_url -Method Put -InFile $file.FullName -ContentType "application/octet-stream" | Out-Null
    Invoke-RestMethod -Uri $up.verify_url -Headers $headers -Method Post | Out-Null
    Write-Host "OK: $($file.Name)"
}

$rel = Invoke-RestMethod -Uri "$api/$repo/-/releases/tags/$tagName" -Headers $headers -Method Get
$body = if ($rel.data) { $rel.data } else { $rel }
Write-Host "== 已发布资产 =="
foreach ($asset in $body.assets) { Write-Host "- $($asset.name)" }
