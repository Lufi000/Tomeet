#!/bin/zsh
# 只编译（含测试 target），不启动模拟器。
#
# 为什么需要它：本机同时有多个 Claude session 在跑同一个工程，模拟器是共享资源，
# 几个 session 同时 boot 模拟器会把 CoreSimulator 服务搞僵（表现为测试宿主 0% CPU
# 静置、连 `simctl log show` 都超时）。编译走 generic destination，完全不碰模拟器，
# 是安全的快速验证手段。跑测试请用 ./scripts/wt-test.sh。
#
# 用法：./scripts/wt-build.sh
set -uo pipefail

WT="$(cd "$(dirname "$0")/.." && pwd)"

xcodebuild build-for-testing \
  -scheme Tomeet \
  -project "$WT/Tomeet/Tomeet.xcodeproj" \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$WT/.deriveddata"
