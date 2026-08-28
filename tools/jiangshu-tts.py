#!/usr/bin/env python3
"""讲书稿 → 音频 管道。

用法:
    python3 tools/jiangshu-tts.py <input.jiangshu.md> [-o OUTPUT.mp3] [--backend edge] [--voice VOICE]

默认输出到 <输入去 .jiangshu.md>.jiangshu.mp3（与输入同目录）。
edge 后端（edge-tts，免费）：单次提交全文，流式写 mp3。
"""
import argparse
import asyncio
import re
import sys
import tempfile
from pathlib import Path


def extract_narration(md_text: str) -> str:
    """提取 '## 正文' 之后的口播文本，剥离 markdown 标记与舞台提示。"""
    match = re.search(r"^##\s*正文.*$", md_text, flags=re.MULTILINE)
    body = md_text[match.end():] if match else md_text

    lines = []
    for line in body.splitlines():
        line = line.strip()
        if not line or line == "---":
            continue
        if re.fullmatch(r"[（(].*[）)]", line):
            continue  # 整行括号 = 舞台提示
        line = re.sub(r"\*\*(.+?)\*\*", r"\1", line)   # 加粗
        line = re.sub(r"(?<!\w)\*(.+?)\*(?!\w)", r"\1", line)  # 斜体
        line = re.sub(r"#+\s*", "", line)               # 标题井号（含行内残留井号）
        line = re.sub(r"^>\s*", "", line)               # 引用
        line = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", line)  # 图片/链接
        if line:
            lines.append(line)
    return "\n\n".join(lines)


def chunk_text(text: str, limit: int = 1800) -> list[str]:
    """按段落边界切分，每块不超过 limit 字符；单段超限则硬切。"""
    chunks: list[str] = []
    current = ""
    for para in text.split("\n\n"):
        while len(para) > limit:
            if current:
                chunks.append(current)
                current = ""
            chunks.append(para[:limit])
            para = para[limit:]
        candidate = f"{current}\n\n{para}" if current else para
        if len(candidate) <= limit:
            current = candidate
        else:
            chunks.append(current)
            current = para
    if current:
        chunks.append(current)
    return chunks


async def synthesize_edge(text: str, voice: str, out_path: Path) -> None:
    import edge_tts

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        suffix=".mp3", dir=out_path.parent, delete=False
    ) as tmp:
        tmp_path = Path(tmp.name)
    try:
        communicate = edge_tts.Communicate(text, voice)
        with open(tmp_path, "wb") as f:
            async for chunk in communicate.stream():
                if chunk["type"] == "audio":
                    f.write(chunk["data"])
        tmp_path.replace(out_path)  # 原子改名，不留半成品
    finally:
        tmp_path.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="讲书稿 → 音频")
    parser.add_argument("input", type=Path, help="*.jiangshu.md 路径")
    parser.add_argument("-o", "--output", type=Path, default=None)
    parser.add_argument("--backend", default="edge", choices=["edge", "minimax"])
    parser.add_argument("--voice", default="zh-CN-YunxiNeural")
    args = parser.parse_args()

    if args.backend == "minimax":
        print("minimax 后端尚未实现——第一版请用 edge（默认）。", file=sys.stderr)
        return 2

    md_text = args.input.read_text(encoding="utf-8")
    text = extract_narration(md_text)
    if not text.strip():
        print("错误：提取后的正文为空，检查是否含 '## 正文' 标题。", file=sys.stderr)
        return 1

    out = args.output or args.input.with_suffix("").with_suffix(".jiangshu.mp3")
    print(f"正文 {len(text)} 字 → {out}（voice={args.voice}）")
    asyncio.run(synthesize_edge(text, args.voice, out))
    print(f"完成: {out} ({out.stat().st_size / 1024 / 1024:.1f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
