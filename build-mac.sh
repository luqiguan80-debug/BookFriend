#!/bin/bash
set -e
echo "══ 生成工程 ══"
xcodegen
echo "══ 编译 macOS 原生 ══"
xcodebuild -project ShuYou.xcodeproj -scheme ShuYouMac \
  -destination 'generic/platform=macOS' -configuration Debug build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  2>&1 | grep -E "error:|BUILD" | head -5
APP_DIR=$(xcodebuild -project ShuYou.xcodeproj -scheme ShuYouMac \
  -destination 'generic/platform=macOS' -configuration Debug -showBuildSettings \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>/dev/null \
  | grep " TARGET_BUILD_DIR" | awk '{print $3}')/BookFriend.app
echo "══ 启动: $APP_DIR ══"
pkill -f "BookFriend.app/Contents/MacOS" 2>/dev/null || true
sleep 0.5
open "$APP_DIR"
echo "══ 已启动 ══"
