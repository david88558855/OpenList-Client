#!/usr/bin/env sh
# 云端构建脚本：产物命名 + 校验和 + 设计稿隔离断言。
# 只在 CI 中执行；本地不编译（见 README「构建」）。
set -eu

FLUTTER=${FLUTTER:-flutter}
VERSION=$(sed -n 's/^version: *\([0-9][^+]*\).*/\1/p' pubspec.yaml | head -1)
[ -n "$VERSION" ] || VERSION=0.0.0

echo "== OpenList Client $VERSION · Android arm64 =="

# 设计稿硬隔离（永久规则）：编译前物理剔除 design/ 及其下所有文件。
# 不依赖 pubspec 白名单，也不依赖打包器"碰巧"不读它 —— 编译期该目录根本不存在。
if [ -d design ]; then
  echo "== 剔除 design/：$(find design -type f | wc -l | tr -d ' ') 个文件，"\
"$(du -sk design | cut -f1) KB（仅视觉参照，永不参与编译）=="
  rm -rf design
fi

"$FLUTTER" config --no-analytics
"$FLUTTER" --version
"$FLUTTER" pub get
"$FLUTTER" build apk --release --target-platform android-arm64

mkdir -p dist
OUT="dist/OpenList-Client-${VERSION}-android-arm64.apk"
cp build/app/outputs/flutter-apk/app-release.apk "$OUT"

if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$OUT" | tee "$OUT.sha256"
fi
ls -lh dist/

echo "== 设计稿隔离校验 =="
leaked=0
# design/ 在编译期必须已不存在（上一步剔除成功），否则视为规则失效
if [ -e design ]; then
  echo "FAIL: 编译结束后 design/ 仍存在，剔除步骤未生效"
  leaked=1
fi
if find build/flutter_assets -iname '*design*' 2>/dev/null | grep -q .; then
  echo "FAIL: flutter_assets 中出现设计稿"
  leaked=1
fi
if grep -qi "OpenList-Client-Design" build/flutter_assets/AssetManifest.json 2>/dev/null; then
  echo "FAIL: AssetManifest 声明了设计稿"
  leaked=1
fi
if command -v unzip >/dev/null 2>&1; then
  if unzip -l "$OUT" | grep -qi "OpenList-Client-Design"; then
    echo "FAIL: APK 中出现设计稿"
    leaked=1
  fi
fi
if [ "$leaked" -ne 0 ]; then
  exit 1
fi
echo "OK: 设计稿未进入任何构建产物"
