#!/usr/bin/env sh
# 把 dist/*.apk 作为附件发布到当前 tag 对应的 CNB Release。
# 依赖：CNB_TOKEN（流水线内置临时令牌）、python3、curl、git。
set -eu

TAG=${1:-}
if [ -z "$TAG" ]; then
  TAG=$(git describe --tags --exact-match 2>/dev/null || true)
fi
if [ -z "$TAG" ]; then
  echo "当前提交没有 tag，跳过发布"
  exit 0
fi

API=https://api.cnb.cool
REPO=haoxuanhaoxuan/OpenList-Client
TOKEN=${CNB_TOKEN:-}
if [ -z "$TOKEN" ]; then
  echo "FAIL: 缺少 CNB_TOKEN，无法上传发行附件"
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "FAIL: 镜像缺少 python3，无法解析 JSON"
  exit 1
fi

pick() { python3 -c "import sys,json;d=json.load(sys.stdin);d=d.get('data',d) if isinstance(d,dict) else {};print(d$1)"; }
release_id() { python3 -c "import sys,json;d=json.load(sys.stdin);d=d.get('data',d) if isinstance(d,dict) else {};print(d.get('id',''))"; }
list_assets() { python3 -c "import sys,json;d=json.load(sys.stdin);d=d.get('data',d) if isinstance(d,dict) else {};[print('-',a.get('name'),a.get('size_in_byte'),a.get('browser_download_url')) for a in d.get('assets',[])]"; }

echo "== 发布 Release $TAG =="
RID=""
i=1
while [ "$i" -le 12 ]; do
  BODY=$(curl -sS -m 30 -H "Authorization: Bearer $TOKEN" -H "Accept: application/json" \
    "$API/$REPO/-/releases/tags/$TAG" || true)
  RID=$(printf '%s' "$BODY" | release_id 2>/dev/null || true)
  if [ -n "$RID" ]; then break; fi
  echo "Release 尚未就绪，${i}/12 次重试…"
  i=$((i + 1))
  sleep 15
done
if [ -z "$RID" ]; then
  echo "FAIL: 找不到 tag $TAG 对应的 Release（请先在 CNB 创建发行版）"
  exit 1
fi
echo "release_id=$RID"

for FILE in dist/*.apk; do
  [ -f "$FILE" ] || continue
  NAME=$(basename "$FILE")
  SIZE=$(wc -c < "$FILE" | tr -d ' ')
  echo "--> 上传 $NAME ($SIZE 字节)"
  UP=$(curl -sS -m 60 -X POST \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -H "Accept: application/json" \
    -d "{\"asset_name\":\"$NAME\",\"size\":$SIZE,\"overwrite\":true}" \
    "$API/$REPO/-/releases/$RID/asset-upload-url")
  UPLOAD_URL=$(printf '%s' "$UP" | pick "['upload_url']")
  VERIFY_URL=$(printf '%s' "$UP" | pick "['verify_url']")
  curl -sS -m 1800 -X PUT -H "Content-Type: application/octet-stream" \
    --data-binary "@$FILE" "$UPLOAD_URL" -o /dev/null -w "PUT %{http_code}\n"
  curl -sS -m 120 -X POST -H "Authorization: Bearer $TOKEN" "$VERIFY_URL" -o /dev/null -w "CONFIRM %{http_code}\n"
  echo "OK: $NAME"
done

echo "== 已发布资产 =="
curl -sS -m 30 -H "Authorization: Bearer $TOKEN" -H "Accept: application/json" \
  "$API/$REPO/-/releases/tags/$TAG" | list_assets
