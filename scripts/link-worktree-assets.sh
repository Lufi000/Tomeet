#!/bin/zsh
# 把主 checkout 里被 .gitignore 排除的书籍资源（*.epub / *.mp3）软链进当前 worktree。
# 这些文件不进 git，所以新 worktree 拿不到，测试和真机验证都会缺 fixture。
# 用法：在 worktree 根目录执行 ./scripts/link-worktree-assets.sh
set -eu

WT="$(cd "$(dirname "$0")/.." && pwd)"
MAIN="/Users/poplardumb/Documents/tree/projects/Tomeet"

if [ "$WT" = "$MAIN" ]; then
  echo "已经在主 checkout，无需链接。"
  exit 0
fi

linked=0
while IFS= read -r -d '' f; do
  rel="${f#$MAIN/}"
  if [ ! -e "$WT/$rel" ]; then
    mkdir -p "$(dirname "$WT/$rel")"
    ln -s "$f" "$WT/$rel"
    linked=$((linked + 1))
  fi
done < <(find "$MAIN/books" \( -name "*.epub" -o -name "*.mp3" \) -print0 2>/dev/null)

echo "已链接 $linked 个资源文件到 $WT"
