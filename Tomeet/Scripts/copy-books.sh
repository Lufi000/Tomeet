#!/bin/sh
# 构建期把公版书（epub 解压 + 讲书音频）复制进 App bundle 的 Books/ 目录。
set -euo pipefail

SRC="$SRCROOT/../books/public_domain_books"
DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Books"

rm -rf "$DEST"
mkdir -p "$DEST"

# 递归查找所有 .epub，按文件名（去扩展名）解压到 Books/<name>/。
# 无效/损坏的 EPUB 会被跳过并打印警告，避免构建失败。
find "$SRC" -type f -name '*.epub' -print0 | while IFS= read -r -d '' epub; do
	name="$(basename "${epub%.epub}")"
	book_dir="$DEST/$name"
	if ! ditto -x -k "$epub" "$book_dir"; then
		echo "warning: skipping invalid or corrupt EPUB: $epub"
		rm -rf "$book_dir" || true
		continue
	fi
done

# 讲书音频：<book-id>.jiangshu.mp3 → Books/<book-id>/jiangshu.mp3
find "$SRC" -type f -name '*.jiangshu.mp3' -print0 | while IFS= read -r -d '' audio; do
	base="$(basename "$audio")"
	name="${base%.jiangshu.mp3}"
	mkdir -p "$DEST/$name"
	cp "$audio" "$DEST/$name/jiangshu.mp3"
done
