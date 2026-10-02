#!/bin/zsh
# 只跑一个测试，并报告耗时。用法：./scripts/run-one-test.sh 'TomeetTests/ChapterPagerTests/tinyContainerDoesNotHang'
set -uo pipefail

WT="$(cd "$(dirname "$0")/.." && pwd)"
SIM_UDID="${TOMEET_SIM_UDID:-B66F862D-190A-4242-A469-1A351979608E}"   # iPhone 17 Pro, iOS 26.2
ONLY="$1"

xcrun simctl boot "$SIM_UDID" 2>/dev/null || true

start=$(date +%s)
xcodebuild test \
  -scheme Tomeet \
  -project "$WT/Tomeet/Tomeet.xcodeproj" \
  -destination "platform=iOS Simulator,id=$SIM_UDID" \
  -derivedDataPath "$WT/.deriveddata" \
  -parallel-testing-enabled NO \
  -only-testing:"$ONLY" \
  > "/tmp/wt-one-test.log" 2>&1
rc=$?
end=$(date +%s)

echo "EXIT=$rc  耗时=$((end - start))s"
grep -E "Test run with|✘ Test |Failing tests:|crashed with signal" "/tmp/wt-one-test.log" | head -10
