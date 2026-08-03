#!/bin/bash
# 打包 macOS 本地分发版：Release 编译 → BookFriend Dev 签名 → dist/BookFriend-macOS.zip
# 注意：用 ShuYouMacLocal.entitlements（无 iCloud），否则自签名证书无 provisioning profile，
# 嵌了 iCloud entitlement 会被 Gatekeeper 拒绝启动；CloudKit 会自动退回纯本地模式。
set -e
cd "$(dirname "$0")"

echo "══ 生成工程 ══"
xcodegen

echo "══ 编译 Release ══"
xcodebuild -project ShuYou.xcodeproj -scheme ShuYouMac \
  -destination 'generic/platform=macOS' -configuration Release build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  2>&1 | grep -E "error:|BUILD" | head -5

APP_DIR=$(xcodebuild -project ShuYou.xcodeproj -scheme ShuYouMac \
  -destination 'generic/platform=macOS' -configuration Release -showBuildSettings \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>/dev/null \
  | grep " TARGET_BUILD_DIR" | awk '{print $3}')/BookFriend.app

echo "══ 签名并打包 ══"
mkdir -p dist
rm -rf dist/BookFriend.app dist/BookFriend-macOS.zip
cp -R "$APP_DIR" dist/
codesign --force --deep --sign "BookFriend Dev" \
  --entitlements Support/ShuYouMacLocal.entitlements \
  dist/BookFriend.app
codesign --verify --deep --strict dist/BookFriend.app
ditto -c -k --keepParent dist/BookFriend.app dist/BookFriend-macOS.zip

echo "══ 完成: dist/BookFriend-macOS.zip ══"
ls -lh dist/
