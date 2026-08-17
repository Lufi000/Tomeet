import SwiftUI

/// 全屏深色阅读占位页（mvp.md §6）。真实阅读器后续用
/// UIPageViewController + .pageCurl 经 UIViewControllerRepresentable 接入。
struct ReaderPlaceholderView: View {
    let book: Book
    @Environment(\.dismiss) private var dismiss
    @State private var showMenu = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // 顶部：书名 + 关闭
                HStack {
                    Text(book.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding()

                Divider().overlay(Color.white.opacity(0.15))

                // 中央：章节 + 正文
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Chapter \(book.title)")
                            .font(.title2.bold())
                        ForEach(0..<6, id: \.self) { _ in
                            Text("这是一段占位正文。Milestone 1 不渲染真实 EPUB/PDF，本篇内容用于验证阅读器占位的导航闭环与排版。")
                                .font(.system(size: 17))
                                .lineSpacing(8)
                                .foregroundStyle(.white.opacity(0.92))
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // 底部：页码
                HStack {
                    Spacer()
                    Text("5 of 935")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                }
                .padding(.vertical, 8)
            }
            .foregroundStyle(.white)

            // 右下角圆形菜单
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    if showMenu {
                        readerMenu
                            .transition(.scale.combined(with: .opacity))
                    }
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showMenu.toggle()
                        }
                    } label: {
                        Image(systemName: "circle.grid.3x3.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white)
                    }
                }
                .padding(20)
            }
        }
    }

    private var readerMenu: some View {
        VStack(alignment: .leading, spacing: 4) {
            menuRow("Contents", trailing: "0%")
            menuRow("Search Book")
            menuRow("Themes & Settings")
            Divider().overlay(Color.white.opacity(0.2))
            HStack(spacing: 18) {
                circleButton("square.and.arrow.up")
                circleButton("lock.rotation")
                circleButton("arrow.left.and.right.righttriangle.left.righttriangle.right")
                circleButton("bookmark")
            }
            .padding(.top, 6)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.bottom, 12)
    }

    private func menuRow(_ title: String, trailing: String? = nil) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            if let trailing {
                Text(trailing).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func circleButton(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 18))
            .frame(width: 40, height: 40)
            .background(Circle().fill(.white.opacity(0.12)))
    }
}
