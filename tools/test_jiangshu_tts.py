"""jiangshu-tts 文本提取测试。运行: python3 tools/test_jiangshu_tts.py"""
import importlib.util
import sys
from pathlib import Path

# 脚本文件名带连字符（jiangshu-tts.py），不能按模块名直接 import，用文件路径加载
_spec = importlib.util.spec_from_file_location(
    "jiangshu_tts", Path(__file__).parent / "jiangshu-tts.py"
)
jiangshu_tts = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(jiangshu_tts)
extract_narration = jiangshu_tts.extract_narration
chunk_text = jiangshu_tts.chunk_text

SAMPLE = """# 讲书稿：《某书》

**作者**：某人

---

## 解构简纲

**这本书解决了什么问题？** 简纲内容不该进正文。

## 正文（口播稿）

先问你一个问题，**可能有点扎心**：你跟你的父亲，说过心里话吗？

（停顿，语气放缓）

今天讲的这本书，# 不是标题
讲的就是这个位置。"对吧？"

---

第二段内容。
"""


def test_extract_narration():
    text = extract_narration(SAMPLE)
    assert "简纲" not in text, "正文之前的内容必须剔除"
    assert "可能有点扎心" in text
    assert "**" not in text, "markdown 加粗标记必须剥离"
    assert "停顿" not in text, "括号舞台提示必须剔除"
    assert "不是标题" in text
    assert "#" not in text, "井号必须剥离"
    assert "---" not in text
    assert "第二段内容。" in text


def test_chunk_text():
    paragraphs = [f"第{i}段。" + "字" * 100 for i in range(50)]
    text = "\n\n".join(paragraphs)
    chunks = chunk_text(text, limit=500)
    assert all(len(c) <= 500 for c in chunks), "每块不得超过 limit"
    assert "".join(chunks).replace("\n\n", "") == text.replace("\n\n", ""), "拼接后内容不得丢失"
    assert len(chunks) > 1


if __name__ == "__main__":
    test_extract_narration()
    test_chunk_text()
    print("all pipeline tests passed")
