#!/bin/zsh
# 等某一轮测试日志出现最终结论，然后打印结果。
# 用法：./scripts/wait-for-test-result.sh /tmp/tomeet-final.log
set -u

LOG="${1:-/tmp/tomeet-final.log}"

for _ in {1..120}; do
  if grep -qE "Test run with" "$LOG" 2>/dev/null; then break; fi
  sleep 15
done

echo "=== 汇总 ==="
grep -E "Test run with" "$LOG" | tail -2
grep -E "TEST SUCCEEDED|TEST FAILED" "$LOG" | tail -1
echo "=== 失败项 ==="
grep -E "Failing tests:" -A20 "$LOG" | tail -22
