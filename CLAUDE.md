# Tomeet

## 产品定位（已确认 · 2026-08-17）

**一句话**：一款高质量的 AI 阅读 App —— 让你与书随时对话，并把阅读转化为个人理解。

**不是**社交软件。定位是"**Meet the mind inside every book**"（与书中的思想相遇）。

核心能力：
- 向书提问（ask the book）
- 追问不理解的概念（dig into concepts）
- 结合读者自己的处境，让书给出解释
- 比较不同书籍的观点
- 把与书的对话沉淀为笔记和个人知识（notes & personal knowledge）
- 之后能重新遇见曾经读过的思想
- 支持在阅读中练习不同的语言

## 技术栈

- SwiftUI + SwiftData（Xcode 工程 scaffold 已在 `Tomeet/`，含 SwiftData `Item` 示例）
- iOS / iPhone 优先

## 已确认的技术决策

- **翻页效果**：原生 `UIPageViewController` `.pageCurl` 翻书效果（Apple Books 式卷页），
  通过 `UIViewControllerRepresentable` 包进 SwiftUI。不用 SwiftUI 纯滑动翻页。
- **导航结构**：采用原生 `TabView` 底部 TabBar，包含 **Home** 与 **Library** 两个标签页。
  当前实现位于 `Tomeet/RootView.swift`；顶部不再使用分段选择器/分区导航。
- **AI 定位**：阅读器核心体验是与书的 AI 对话，不只是翻页阅读。AI 对话功能是产品重心。
- **AI 后端**：DeepSeek 经自家 BFF 代理（`https://tomeet-api.smallbeebee.com`，Go 源码在 `bff/`，部署在阿里云 ECS :8088，systemd `tomeet-bff`）。App 持 `X-App-Token`（`Secrets.swift`，gitignored）；DeepSeek key 只存服务器 `/opt/tomeet-bff/.env`。

## 第一个里程碑

**底部 Tab 框架（Home + Library）+ 书架网格（SwiftData）**

- 先搭出 Home / Library 底部 Tab 骨架 + 书架网格，用假数据/占位看结构
- 翻书阅读器、AI 对话都在骨架稳定之后再接入