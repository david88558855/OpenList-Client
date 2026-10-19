#!/usr/bin/env bash
# 生成 Windows 平台工程（Flutter 官方模板），随后即可 flutter build windows。
set -euo pipefail
FLUTTER=${FLUTTER:-flutter}
"$FLUTTER" create --platforms=windows --org com.openlist --project-name openlist_client .
"$FLUTTER" pub get
echo "完成。运行 flutter run -d windows 或 flutter build windows --release"
