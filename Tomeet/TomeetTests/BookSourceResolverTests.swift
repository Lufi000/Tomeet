import Foundation
import SwiftData
import Testing
@testable import Tomeet

@MainActor
struct BookSourceResolverTests {
    /// 未配置音频文件名时应返回 nil。
    @Test func audioURLIsNilWhenNoAudioFileName() {
        let book = Book(title: "T", author: "A", format: .epub)
        book.sourceFileName = "some-book"
        #expect(BookSourceResolver.audioURL(for: book) == nil)
    }

    /// App Support 中不存在音频文件时，应回退到 Bundle 内对应书源目录。
    /// 只断言路径形状，不断言文件真实存在（音频文件后续任务才生成）。
    @Test func audioURLFallsBackToBundle() {
        let book = Book(title: "T", author: "A", format: .epub)
        book.sourceFileName = "george-macdonald_if-i-had-a-father"
        book.audioFileName = "jiangshu.mp3"
        let url = BookSourceResolver.audioURL(for: book)
        #expect(url?.path.contains("Books/george-macdonald_if-i-had-a-father/jiangshu.mp3") == true)
    }

    /// 未配置书源文件名时，已解压目录解析应返回 nil。
    @Test func existingDirectoryIsNilWithoutSourceFileName() {
        let book = Book(title: "T", author: "A", format: .epub)
        #expect(BookSourceResolver.existingDirectoryURL(for: book) == nil)
    }

    /// App Support 中没有书源目录时，应回退到 Bundle 内对应目录（封面加载依赖此路径）。
    /// 测试宿主为 App，构建期 copy-books.sh 已把该公版书打进 bundle。
    @Test func existingDirectoryFallsBackToBundle() {
        let book = Book(title: "T", author: "A", format: .epub)
        book.sourceFileName = "george-macdonald_if-i-had-a-father"
        let url = BookSourceResolver.existingDirectoryURL(for: book)
        #expect(url?.path.contains("Books/george-macdonald_if-i-had-a-father") == true)
    }

    /// App Support 与 Bundle 都不存在的书源应返回 nil。
    @Test func existingDirectoryIsNilWhenMissingEverywhere() {
        let book = Book(title: "T", author: "A", format: .epub)
        book.sourceFileName = "no-such-book-anywhere"
        #expect(BookSourceResolver.existingDirectoryURL(for: book) == nil)
    }
}
