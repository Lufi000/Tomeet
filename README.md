# Tomeet

**Meet the mind inside every book.**

Tomeet is a high-quality AI reading app for iPhone. It helps you read with a paper-like page experience, listen to AI-generated book companions that make ideas easier to absorb, and talk with a book whenever something is unclear — turning reading into personal understanding.

This is not a social product. The focus is the relationship between the reader and the ideas inside each book.

## What it does

- **Read** — A native page-curl reading experience that feels like turning a physical book
- **Listen** — AI book companions (summary-style narration) that help you digest a book’s core ideas, in the spirit of apps like Fan Deng Reading or podcast-style listening
- **Ask** — Chat with the book at any time to clarify concepts, apply ideas to your own situation, and replace one-way reading with dialogue

Over time, conversations with books become notes and personal knowledge you can return to.

## Tech stack

- SwiftUI + SwiftData
- iOS / iPhone first
- Native Apple UI patterns (NavigationStack, sheets, system controls)
- Page curl via `UIPageViewController` (`.pageCurl`) wrapped for SwiftUI

## Current focus

Milestone 2 ships the real EPUB reader: TextKit pagination, `UIPageViewController` `.pageCurl`, chapter Contents jump, and `(chapter, charOffset)` position persistence. Books are seeded from 4 public-domain EPUBs extracted into the bundle at build time. AI companion audio and book chat remain for later milestones.

## Status

Early development. Milestone 1 (Home + Library skeleton) is complete. Milestone 2 reader core is implemented on `feature/reader-m2`. Product direction and MVP scope live in `docs/design/`.
