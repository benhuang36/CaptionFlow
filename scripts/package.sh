#!/usr/bin/env bash
#
# 打包 CaptionFlow 成可傳輸的 .app + zip。
#   - Release 建置(Debug 綁 DerivedData,不能搬到別台)
#   - 用 Apple Development 憑證簽章(穩定身分 → 螢幕錄製授權跨 build 保留)
#   - 壓成 zip
#
# 用法:
#   ./scripts/package.sh                  # 產出 dist/CaptionFlow.zip
#   SIGN_IDENTITY="Apple Development: ..." ./scripts/package.sh   # 指定簽章身分
#   OUTPUT=~/Desktop/CaptionFlow.zip ./scripts/package.sh        # 指定輸出位置
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

PROJECT="CaptionFlow.xcodeproj"
SCHEME="CaptionFlow"
CONFIG="Release"
DERIVED="build/release"
APP="$DERIVED/Build/Products/Release/CaptionFlow.app"
OUTPUT="${OUTPUT:-$ROOT/dist/CaptionFlow.zip}"

echo "▸ 重新產生 Xcode 專案 (xcodegen)…"
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate >/dev/null
else
  echo "  (略過:未安裝 xcodegen)"
fi

echo "▸ 建置 $CONFIG…"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -destination 'platform=macOS' -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" build CODE_SIGNING_ALLOWED=NO \
  >/dev/null

if [ ! -d "$APP" ]; then
  echo "✗ 找不到建置產物:$APP" >&2
  exit 1
fi

IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning \
    | awk -F'"' '/Apple Development/ {print $2; exit}')"
fi
if [ -z "$IDENTITY" ]; then
  echo "  ⚠ 找不到 Apple Development 憑證,改用 ad-hoc 簽章(授權無法跨 build 保留)" >&2
  IDENTITY="-"
fi

echo "▸ 簽章:$IDENTITY"
codesign --force --deep --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"

echo "▸ 打包 → $OUTPUT"
mkdir -p "$(dirname "$OUTPUT")"
rm -f "$OUTPUT"
ditto -c -k --keepParent "$APP" "$OUTPUT"

SIZE="$(du -h "$OUTPUT" | cut -f1)"
echo ""
echo "✓ 完成:$OUTPUT ($SIZE)"
echo ""
echo "傳到另一台 Mac(Apple Silicon + macOS 26)後,解壓並執行一次:"
echo "    xattr -dr com.apple.quarantine /路徑/CaptionFlow.app"
echo "然後即可開啟(首次需授權螢幕錄製、並會下載模型)。"
