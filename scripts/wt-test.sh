#!/bin/zsh
# 在 worktree 里跑 Tomeet 测试。
#
# 为什么用独立 DerivedData：
#   默认 DerivedData 是「按工程路径」共享的，本机同时可能有别的 Claude session / Xcode
#   在跑同一个工程。两个 xcodebuild 并发写同一份 DerivedData 会互相污染，产出无法解释的
#   失败。给 worktree 一个专属路径就彻底隔离了。
#
# 为什么固定 simulator UDID：
#   本机有多台同名模拟器。按名字指定会启动错误的那台，测试以 `Mach error -308` 失败。
#   必须两边用同一个 UDID。
#
# 为什么用 iPhone 17 Pro 而不是 iPhone 17：
#   本机可能有别的 Claude session 在跑同一个工程，而模拟器是共享资源 ——
#   同一个 bundle id 被覆盖安装会把正在跑的测试宿主强杀，报成
#   "Test crashed with signal kill"，看起来像代码 bug。用一台独立设备避开争用。
#
# 用法：./scripts/wt-test.sh [额外的 xcodebuild 参数...]
set -uo pipefail

WT="$(cd "$(dirname "$0")/.." && pwd)"
SIM_UDID="${TOMEET_SIM_UDID:-B66F862D-190A-4242-A469-1A351979608E}"   # iPhone 17 Pro, iOS 26.2
DD="$WT/.deriveddata"

xcrun simctl boot "$SIM_UDID" 2>/dev/null || true

xcodebuild test \
  -scheme Tomeet \
  -project "$WT/Tomeet/Tomeet.xcodeproj" \
  -destination "platform=iOS Simulator,id=$SIM_UDID" \
  -derivedDataPath "$DD" \
  -parallel-testing-enabled NO \
  "$@"
