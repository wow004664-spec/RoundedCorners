#!/bin/zsh
# RoundedCorners 一键构建脚本：编译 App -> 打 DMG
set -euo pipefail
cd "$(dirname "$0")"

VERSION="1.1.0"
APP_NAME="RoundedCorners"
BUILD_DIR="build"
DIST_DIR="dist"
APP="$BUILD_DIR/$APP_NAME.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$DIST_DIR"

echo "==> 编译 $APP_NAME $VERSION"
swiftc -O -o "$APP/Contents/MacOS/$APP_NAME" main.swift

echo "==> 生成应用图标"
if [[ ! -f "$BUILD_DIR/icon_1024.png" ]]; then
    swift tools/make_icon.swift "$BUILD_DIR/icon_1024.png"
fi
mkdir -p "$BUILD_DIR/AppIcon.iconset"
for s in 16 32 128 256 512; do
    sips -z $s $s "$BUILD_DIR/icon_1024.png" --out "$BUILD_DIR/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    d=$((s*2))
    sips -z $d $d "$BUILD_DIR/icon_1024.png" --out "$BUILD_DIR/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> 写入 Info.plist 并签名"
cp Info.plist "$APP/Contents/Info.plist"
# 固定 designated requirement（绑定 bundle id 而非文件指纹）：
# 这样后续版本更新不会让系统已授予的辅助功能权限失效
codesign -s - -f --requirements '=designated => identifier "com.workbuddy.roundedcorners"' "$APP"

echo "==> 组装 DMG 内容"
DMG_STAGE="$BUILD_DIR/dmg"
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"
cp -R "$APP" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"

echo "==> 打包 DMG"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_PATH" | tail -1

echo "==> 完成: $DMG_PATH"
