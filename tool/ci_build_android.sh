#!/usr/bin/env sh
# 云端构建脚本：产物命名 + 校验和。
# 只在 CI 中执行；本地不编译（见 README「构建」）。
set -eu

FLUTTER=${FLUTTER:-flutter}
VERSION=$(sed -n 's/^version: *\([0-9][^+]*\).*/\1/p' pubspec.yaml | head -1)
[ -n "$VERSION" ] || VERSION=0.0.0

echo "== OpenList Client $VERSION · Android arm64 =="

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
