#!/usr/bin/env sh
# 把 dist/*.apk 作为附件发布到当前 tag 对应的 CNB Release。
# 依赖：CNB_TOKEN（流水线内置临时令牌）、python3、curl、git。
set -eu

API=https://api.cnb.cool
REPO=haoxuanhaoxuan/OpenList-Client
TOKEN=${CNB_TOKEN:-}

# tag 归一化：CNB 的浅克隆里 `git describe --exact-match` 可能返回
# `refs/tags/v1.0.1-0-g89825ed` 这种带前缀和距离后缀的字符串，这里统一清洗。
normalize_tag() {
  printf '%s' "$1" \
    | tr -d '\r' \
    | sed -e 's#^refs/tags/##' \
          -e 's#^refs/heads/##' \
          -e 's/-[0-9][0-9]*-g[0-9a-f][0-9a-f]*$//' \
          -e 's#^ *##' -e 's# *$##'
}

# 依次尝试：命令行参数 / CNB 环境变量 / git describe / git tag / pubspec 版本。
collect_tags() {
  { [ $# -gt 0 ] && printf '%s\n' "$1"
    printf '%s\n' "${CNB_TAG:-}"
    printf '%s\n' "${CNB_BRANCH:-}"
    git describe --tags --exact-match 2>/dev/null || true
    git tag --points-at HEAD 2>/dev/null || true
    printf 'v%s\n' "$(sed -n 's/^version: *\([0-9][^+ ]*\).*/\1/p' pubspec.yaml 2>/dev/null | head -1)"
  } | while IFS= read -r raw; do
        [ -n "$raw" ] || continue
        tag=$(normalize_tag "$raw")
        [ -n "$tag" ] || continue
        case "$tag" in
          v[0-9]*) printf '%s\n' "$tag" ;;
        esac
      done | awk '!seen[$0]++'
}

if [ -z "$TOKEN" ]; then
  echo "FAIL: 缺少 CNB_TOKEN，无法上传发行附件"
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "FAIL: 镜像缺少 python3，无法解析 JSON"
  exit 1
fi

release_id() { python3 -c "import sys,json;d=json.load(sys.stdin);d=d.get('data',d) if isinstance(d,dict) else {};print(d.get('id',''))"; }
pick() { python3 -c "import sys,json;d=json.load(sys.stdin);d=d.get('data',d) if isinstance(d,dict) else {};print(d$1)"; }
list_assets() { python3 -c "import sys,json;d=json.load(sys.stdin);d=d.get('data',d) if isinstance(d,dict) else {};[print('-',a.get('name'),a.get('size_in_byte'),a.get('browser_download_url')) for a in d.get('assets',[])]"; }

CANDIDATES=$(collect_tags "${1:-}")
if [ -z "$CANDIDATES" ]; then
  echo "当前提交没有可识别的 tag，跳过发布"
  exit 0
fi
echo "== 候选 tag =="
printf '%s\n' "$CANDIDATES" | sed 's/^/  - /'

echo "== 查找对应 Release =="
TAG=""
RID=""
i=1
while [ "$i" -le 8 ]; do
  for candidate in $CANDIDATES; do
    BODY=$(curl -sS -m 30 -H "Authorization: Bearer $TOKEN" -H "Accept: application/json" \
      "$API/$REPO/-/releases/tags/$candidate" || true)
    FOUND_ID=$(printf '%s' "$BODY" | release_id 2>/dev/null || true)
    if [ -n "$FOUND_ID" ]; then
      TAG="$candidate"
      RID="$FOUND_ID"
      break
    fi
  done
  [ -n "$RID" ] && break
  echo "Release 尚未就绪，${i}/8 次重试…"
  i=$((i + 1))
  sleep 15
done
if [ -z "$RID" ]; then
  echo "FAIL: 上述 tag 都没有对应的 Release（请先在 CNB 创建发行版）"
  exit 1
fi
echo "tag=$TAG release_id=$RID"

FOUND=0
for FILE in dist/*.apk dist/*.zip; do
  [ -f "$FILE" ] || continue
  FOUND=$((FOUND + 1))
  NAME=$(basename "$FILE")
  SIZE=$(wc -c < "$FILE" | tr -d ' ')
  echo "--> 上传 $NAME ($SIZE 字节)"
  UP=$(curl -sS -m 60 -X POST \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -H "Accept: application/json" \
    -d "{\"asset_name\":\"$NAME\",\"size\":$SIZE,\"overwrite\":true}" \
    "$API/$REPO/-/releases/$RID/asset-upload-url")
  UPLOAD_URL=$(printf '%s' "$UP" | pick "['upload_url']")
  VERIFY_URL=$(printf '%s' "$UP" | pick "['verify_url']")
  if [ -z "$UPLOAD_URL" ] || [ -z "$VERIFY_URL" ]; then
    echo "FAIL: 申请上传地址失败：$UP"
    exit 1
  fi
  PUT_CODE=$(curl -sS -m 1800 -X PUT -H "Content-Type: application/octet-stream" \
    --data-binary "@$FILE" "$UPLOAD_URL" -o /dev/null -w "%{http_code}")
  echo "PUT $PUT_CODE"
  if [ "$PUT_CODE" != "200" ]; then
    echo "FAIL: 文件上传失败（HTTP $PUT_CODE）"
    exit 1
  fi
  # 确认接口必须带 Accept: application/json，否则返回 406
  CFM_CODE=$(curl -sS -m 120 -X POST -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/json" "$VERIFY_URL" -o /dev/null -w "%{http_code}")
  echo "CONFIRM $CFM_CODE"
  if [ "$CFM_CODE" != "200" ]; then
    echo "FAIL: 附件确认失败（HTTP $CFM_CODE）"
    exit 1
  fi
  echo "OK: $NAME"
done
if [ "$FOUND" -eq 0 ]; then
  echo "FAIL: dist/ 下没有 apk/zip，构建产物未传递到发布阶段"
  exit 1
fi

echo "== 已发布资产 =="
curl -sS -m 30 -H "Authorization: Bearer $TOKEN" -H "Accept: application/json" \
  "$API/$REPO/-/releases/tags/$TAG" | list_assets
