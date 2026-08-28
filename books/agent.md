### 英文公共领域书籍

[standardebooks](https://standardebooks.org/)

| 来源 | 网址 | 特点 | 格式 |
|------|------|------|------|
| **Project Gutenberg** | gutenberg.org | 最老牌，6万+本，文学经典为主 | EPUB, Kindle, Plain Text |
| **Standard Ebooks** | standardebooks.org | 排版极其精美（接近商业出版品质），基于 Gutenberg 但重新校对排版 | EPUB |
| **Internet Archive** | archive.org/details/texts | 海量扫描版古籍和电子书，包括很多中文古籍 | EPUB, PDF, DJVU |
| **Wikisource** | wikisource.org | 维基媒体旗下，纯文本公共领域书籍 | 网页/HTML |
| **ManyBooks** | manybooks.net | 分类清晰，可下载多种格式 | EPUB, MOBI, PDF |
| **Open Library** | openlibrary.org | Internet Archive 的子项目，可借阅/下载公共领域书 | EPUB, PDF |

**推荐直接下载的书（经典测试用）**：
- 《Pride and Prejudice》（傲慢与偏见）
- 《The Great Gatsby》（了不起的盖茨比，美国已进入公版）
- 《Frankenstein》（科学怪人）
- 《Alice's Adventures in Wonderland》（爱丽丝梦游仙境）
- 《The Picture of Dorian Gray》（道林·格雷的画像）

---

### 中文公共领域书籍

| 来源 | 网址 | 说明 |
|------|------|------|
| **书格** | shuge.org | 中文古籍数字化，排版精美，免费下载 |
| **中国哲学书电子化计划** | ctext.org | 先秦两汉至近现代中文典籍，文本版 |
| **古登堡计划（中文）** | gutenberg.org/browse/languages/zh | 少量中文公版书 |
| **维基文库（中文）** | zh.wikisource.org | 中文公共领域文本，可导出 |
| **国家图书馆·中华古籍资源库** | nlc.cn | 古籍扫描图，部分开放 |

**推荐下载的书**：
- 《红楼梦》《三国演义》《水浒传》《西游记》（四大名著）
- 《鲁迅全集》（部分作品）
- 《围城》（钱钟书，已进入公版）
- 《倾城之恋》（张爱玲，部分作品）

---

### 快速获取方式

如果你只是想快速拿几本测试 Apple Books 的 EPUB 渲染，最简单的方式：

1. 打开 **standardebooks.org**
2. 随便选一本（比如 *Pride and Prejudice*）
3. 点击下载 **EPUB**（不带 DRM，直接可用）
4. 用 AirDrop 或文件共享发到 iPhone → 选择 "用 Books 打开"

---

# 讲书 Agent（jiangshu）工作流与成本估算

> 整理于 2026-08-27。讲书稿方法论见 `~/.claude/skills/book-talk-script/SKILL.md`，agent 定义见 `~/.claude/agents/jiangshu.md`。

## 工作流

1. **取书**：epub 解压 → 按 content.opf spine 顺序通读全部章节（"以书为据"，不凭印象虚构）
2. **解构**（樊登读书法四问）：解决了什么问题 → 写作背景 → 解决方案/论证过程 → 一句话价值升华
3. **取舍**：8 条精华标准（概念界定/问题严重/意外解释/递进/转折/不同侧面/心灵冲击/奇闻逸事）
4. **成稿**：坡道（无寒暄、最有价值内容前置）→ 背景 → 正文（按原书章节顺序、充分论证）→ 结尾（呼应+感召+诗意）
5. **红线**：原文照搬 ≤10%、不改书中观点、不夹私货
6. **交付**：`books/讲书稿-<书名>.md`，默认 30-40 分钟口播量（约 7000-9000 字）

## 一本书的 token 消耗

以《情绪鸡尾酒》（约 9.7 万字）实测：18 次工具调用，subagent 上报约 8.7 万 tokens（输出+推理）。

| 环节 | token 估算 | 说明 |
|---|---|---|
| 通读原书 | ~6 万输入 | 10 万字中文 ≈ 6 万 token（中文约 1.5 字/token） |
| 多轮上下文重发 | ~50-80 万输入（90%+ 可命中缓存） | agent 每轮带累积上下文重新提交，成本最大头 |
| 解构 + 成稿 + 推理 | ~3-9 万输出 | 讲书稿约 6 千 token，推理模型的"思考"也计输出 |

**关键点**：成本大头不是读书，而是十几轮反复重发的上下文——缓存命中率决定成本。

## Kimi K3 费用估算

K3 官方定价：输入（缓存命中）¥2/百万，输入（未命中）¥20/百万，输出 ¥100/百万。K3 强制推理，"思考"按输出计费。

| 场景 | 计算 | 成本/本 |
|---|---|---|
| 缓存命中良好（~90%） | 新输入 6 万×¥20/M + 缓存 70 万×¥2/M + 输出 5 万×¥100/M | ≈ ¥7.6 |
| 无缓存 | 输入 76 万×¥20/M + 输出 5 万×¥100/M | ≈ ¥20 |
| 推理量大（输出 9 万） | 缓存场景 | ≈ ¥11.6 |

**结论：一本书约 ¥8-20，缓存正常时 ¥10 以内；一年 52 本约 ¥400-1000。**

省钱杠杆：

1. 同一 agent 会话内连续处理多本书——skill 与格式约定都在缓存里，边际成本递减
2. 非核心环节降级：通读+解构用 K2.7 Code（输出 ¥27/百万），只把最终成稿交给 K3，可再省 40-50%

参考：[Kimi K3 Pricing](https://www.kimi.ai/resources/kimi-k3-pricing)、[Kimi K3 价格（中文）](https://www.kimi.ai/zh-hans/resources/kimi-k3-pricing)、[EvoLink - Kimi K3 API](https://evolink.ai/zh/kimi-k3)
