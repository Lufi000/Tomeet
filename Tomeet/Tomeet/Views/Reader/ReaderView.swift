import SwiftData
import SwiftUI

/// ReaderView 菜单模型：章节行 + 固定占位行。
extension ReaderView {
    /// Contents 菜单行：真实章节（跳转）或占位行（不跳转）。
    struct ContentsRow: Equatable {
        let title: String
        let jumpable: Bool
        /// 章节目标（占位行为 nil）
        let chapterIndex: Int?
    }

    static let placeholderMenuRowCount = 2  // Search Book / Themes & Settings
    static let placeholderCircleButtonCount = 4  // share / rotate / reading mode / bookmark
    static func contentsRows(chapters: [Chapter]) -> [ContentsRow] {
        chapters.enumerated().map { index, chapter in
            ContentsRow(title: chapter.title, jumpable: true, chapterIndex: index)
        } + [
            ContentsRow(title: "Search Book", jumpable: false, chapterIndex: nil),
            ContentsRow(title: "Themes & Settings", jumpable: false, chapterIndex: nil),
        ]
    }
}

/// 全屏深色阅读器外壳：加载/错误/就绪三分支，Contents 章节跳转，三级保存时机。
struct ReaderView: View {
    let book: Book
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: ReaderViewModel
    @State private var showMenu = false

    init(book: Book) {
        self.book = book
        _viewModel = State(initialValue: ReaderViewModel(book: book))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .foregroundStyle(.white)
        .onAppear {
            viewModel.loadBook(pageSize: currentSize)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                viewModel.saveCurrentPosition()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            ProgressView().tint(.white)
        case .failed(let message):
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.6))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("Retry") {
                    viewModel.loadBook(pageSize: currentSize)
                }
                .buttonStyle(.borderedProminent)
            }
        case .ready:
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    VStack(spacing: 0) {
                        topBar
                        ReaderHostView(viewModel: viewModel)
                            .frame(width: size.width, height: size.height - chromeHeight)
                        bottomBar
                    }
                    overlayButtons
                }
                .onAppear {
                    viewModel.relayout(pageSize: CGSize(width: size.width, height: size.height - chromeHeight))
                }
                .onChange(of: size) { _, newSize in
                    viewModel.relayout(pageSize: CGSize(width: newSize.width, height: newSize.height - chromeHeight))
                }
            }
        }
    }

    private var chromeHeight: CGFloat { 44 + 8 + 32 }

    private var topBar: some View {
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
    }

    private var bottomBar: some View {
        HStack {
            Spacer()
            Text("\(viewModel.currentGlobalIndex + 1) of \(viewModel.totalPages)")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var currentSize: CGSize {
        UIScreen.main.bounds.size
    }

    // MARK: - 右下角圆形菜单

    private var readerMenu: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(ReaderView.contentsRows(chapters: viewModel.session?.document.chapters ?? []).enumerated()), id: \.offset) { _, row in
                Button {
                    if let chapterIndex = row.chapterIndex {
                        viewModel.jump(toChapter: chapterIndex)
                        showMenu = false
                    }
                } label: {
                    HStack {
                        Text(row.title).font(.subheadline)
                        Spacer()
                        if row.jumpable, let index = row.chapterIndex {
                            Text("\(index + 1)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .disabled(row.jumpable == false)
            }
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

    private func circleButton(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 18))
            .frame(width: 40, height: 40)
            .background(Circle().fill(.white.opacity(0.12)))
    }

    private var overlayButtons: some View {
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
