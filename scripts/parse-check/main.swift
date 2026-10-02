import Foundation

// 用真实的《复杂》EPUB 直接验证解析器 —— 比看截图可靠。
// 只依赖 Foundation，所以能脱离 Xcode / 模拟器单独编译运行。
//
// 用法：./scripts/check-real-book.sh

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("用法：parse-check <已解压的 EPUB 目录>\n".utf8))
    exit(2)
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

func line(_ text: String = "") { print(text) }

do {
    let document = try EPUBParser.parseBook(at: directory)

    line("书名: \(document.title)")
    line("作者: \(document.author ?? "(无)")")
    line("语言: \(document.language ?? "(无)")")
    line("章节数: \(document.chapters.count)")
    line("总字符: \(document.totalCharacters)")
    line("锚点数: \(document.anchors.count)")
    line()

    // bug 2：章节标题必须**各不相同**，否则目录每行都一样
    let titles = document.chapters.map(\.title)
    let uniqueTitles = Set(titles)
    line("=== 目录（前 20 章）===")
    for (index, title) in titles.prefix(20).enumerated() {
        line("  \(index + 1). \(title)")
    }
    line()
    line("标题去重后: \(uniqueTitles.count) / \(titles.count)")
    if uniqueTitles.count == 1, titles.count > 1 {
        line("❌ 所有章节标题相同 —— bug 2 未修复")
    } else if uniqueTitles.count < titles.count {
        line("⚠️  有重复标题（\(titles.count - uniqueTitles.count) 处）—— 目录里会出现同名行")
    } else {
        line("✅ 章节标题各不相同 —— bug 2 已修复")
    }
    line()

    // bug 5：脚注角标
    var noterefCount = 0
    var noterefIDs = Set<String>()
    for chapter in document.chapters {
        for block in chapter.blocks {
            for run in block.runs where run.noteID != nil {
                noterefCount += 1
                noterefIDs.insert(run.noteID!)
            }
        }
    }
    line("=== 脚注 ===")
    line("角标数: \(noterefCount)，涉及 \(noterefIDs.count) 个不同锚点")
    let resolvable = noterefIDs.filter { document.anchors[$0] != nil }.count
    line("能在锚点表里找到落点的: \(resolvable) / \(noterefIDs.count)")
    if noterefCount == 0 {
        line("⚠️  这本书没有脚注角标，换个有脚注的书验证 bug 5")
    } else if resolvable == 0 {
        line("❌ 角标全部无法跳转 —— bug 5 未修复")
    } else {
        line("✅ 角标可跳转 —— bug 5 已修复")
    }
    line()

    // bug 6：插图
    var imagePaths: [String] = []
    var missing = 0
    for chapter in document.chapters {
        for block in chapter.blocks {
            if case let .image(ref) = block {
                imagePaths.append(ref.path)
                let url = directory.appendingPathComponent(ref.path)
                if !FileManager.default.fileExists(atPath: url.path) { missing += 1 }
            }
        }
    }
    line("=== 插图 ===")
    line("图片块数: \(imagePaths.count)")
    line("文件缺失: \(missing)")
    for path in imagePaths.prefix(10) { line("  · \(path)") }
    if imagePaths.isEmpty {
        line("⚠️  这本书没有插图，换个有插图的书验证 bug 6")
    } else if missing == imagePaths.count {
        line("❌ 图片路径全部解析不到文件 —— bug 6 未修复")
    } else {
        line("✅ 图片可解析到文件 —— bug 6 已修复")
    }
    line()

    // 内联强调
    let emphasisCount = document.chapters
        .flatMap(\.blocks)
        .flatMap(\.runs)
        .filter { $0.emphasis != .none }
        .count
    line("内联强调 run 数: \(emphasisCount)")
} catch {
    line("解析失败: \(error)")
    exit(1)
}
