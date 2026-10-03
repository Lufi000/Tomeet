#!/bin/zsh
# 把主 checkout 里被 .gitignore 排除、worktree 拿不到的资源软链进来：
#   books/**/*.epub|*.mp3                 书籍 fixture（测试 / 真机验证用）
#   Tomeet/Tomeet/Services/Secrets.swift  BFF token，缺了会直接编译失败
#
# 用法：在 worktree 根目录执行 ./scripts/link-worktree-assets.sh
set -eu

WT="$(cd "$(dirname "$0")/.." && pwd)"

# 主 checkout 路径从 git 推导：`git worktree list` 的第一条恒为主 checkout。
# 不要写死机器路径 —— 原来写死的那个指向另一台机器，在本机跑会静默空转（find 找不到
# 目录，一律报 0，看着像成功）。
MAIN="$(git -C "$WT" worktree list --porcelain | awk '/^worktree /{print substr($0, 10); exit}')"
if [ -z "$MAIN" ]; then
  echo "✗ 推导主 checkout 路径失败（git worktree list 没有输出）" >&2
  exit 1
fi

if [ "$WT" = "$MAIN" ]; then
  echo "已经在主 checkout（$MAIN），无需链接。"
  exit 0
fi

linked=0
skipped=0
missing=0

# 软链 MAIN/$1 → WT/$1。源缺失记入 missing，由调用方决定是否致命。
link_one() {
  local rel="$1" src="$MAIN/$1" dst="$WT/$1"

  if [ ! -e "$src" ]; then
    echo "✗ 主 checkout 缺 $rel" >&2
    missing=$((missing + 1))
    return 0
  fi
  if [ -e "$dst" ]; then     # 已存在（真文件或有效软链）→ 不动它
    skipped=$((skipped + 1))
    return 0
  fi
  if [ -L "$dst" ]; then     # 悬空软链（源被删过）→ 重建
    rm -f "$dst"
  fi
  mkdir -p "$(dirname "$dst")"
  ln -s "$src" "$dst"
  echo "✓ $rel"
  linked=$((linked + 1))
}

echo "主 checkout: $MAIN"
echo "worktree:    $WT"

# Secrets.swift 是编译期依赖：主 checkout 里没有它时必须响亮失败，否则 worktree 会以
# 「Cannot find 'Secrets' in scope」这种看不出根因的样子挂掉。
link_one "Tomeet/Tomeet/Services/Secrets.swift"

# 书籍 fixture：缺了不影响编译，只影响依赖真实书籍的测试，所以只警告不失败。
books_found=0
while IFS= read -r -d '' f; do
  books_found=$((books_found + 1))
  link_one "${f#$MAIN/}"
done < <(find "$MAIN/books" \( -name "*.epub" -o -name "*.mp3" \) -print0 2>/dev/null)

echo "已链接 $linked 个，跳过 $skipped 个已存在"

if [ "$books_found" -eq 0 ]; then
  echo "⚠️  主 checkout 的 books/ 下没有任何 *.epub / *.mp3 —— 编译不受影响，但依赖真实书籍的测试会缺 fixture。" >&2
fi

if [ "$missing" -gt 0 ]; then
  echo "✗ 有 $missing 个源文件在主 checkout 里不存在，补齐后再跑一次本脚本。" >&2
  exit 1
fi