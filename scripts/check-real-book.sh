#!/bin/zsh
# 用真实的《复杂》EPUB 验证解析器（章节目录 / 脚注角标 / 插图）。
#
# 为什么单独跑：解析器只依赖 Foundation，可以脱离 Xcode 和模拟器直接编译 ——
# 改解析逻辑时几秒就能拿到真实书的结论，不用等几分钟的 xcodebuild。
#
# 用法：./scripts/check-real-book.sh [epub 路径]
set -euo pipefail

WT="$(cd "$(dirname "$0")/.." && pwd)"
EPUB="${1:-$WT/books/Copyrighte_books/第一推动丛书·综合系列：复杂.epub}"

if [ ! -f "$EPUB" ]; then
  echo "找不到 EPUB：$EPUB"
  echo "（epub 被 .gitignore 排除，新 worktree 需要先跑 ./scripts/link-worktree-assets.sh）"
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ditto -x -k "$EPUB" "$WORK/book"

swiftc -O \
  -o "$WORK/parse-check" \
  "$WT/Tomeet/Tomeet/Models/Reader/ReaderLocation.swift" \
  "$WT/Tomeet/Tomeet/Models/Reader/BookDocument.swift" \
  "$WT/Tomeet/Tomeet/Services/EPUBParser.swift" \
  "$WT/scripts/parse-check/main.swift" \
  2>&1 | grep -v "^$" || true

"$WORK/parse-check" "$WORK/book"
