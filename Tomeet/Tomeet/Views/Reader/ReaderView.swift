import SwiftData
import SwiftUI

/// 全屏阅读器外壳：加载/错误/就绪三分支，支持悬浮菜单、目录与主题设置 Sheet。
struct ReaderView: View {
    let book: Book
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: ReaderViewModel
    @State private var showMenu = false
    @State private var showChrome = true
    @State private var chromeHideTask: Task<Void, Never>?
    @State private var showContents = false
    @State private var showThemes = false
    @State private var showListen = false

    init(book: Book) {
        self.book = book
        _viewModel = State(initialValue: ReaderViewModel(book: book))
    }

    var body: some View {
        ZStack {
            themeBackground.ignoresSafeArea()
            content
        }
        .foregroundStyle(themeForeground)
        .onAppear {
            let settings = ReaderSettings.fetchOrCreate(in: modelContext)
            viewModel.apply(settings: settings)
            applyBrightness(from: settings)
            viewModel.loadBook(pageSize: currentSize)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                viewModel.saveCurrentPosition()
            }
        }
        .sheet(isPresented: $showContents) {
            ContentsSheet(book: book, viewModel: viewModel)
        }
        .sheet(isPresented: $showThemes) {
            ThemesSettingsSheet(settings: viewModel.settings ?? ReaderSettings())
        }
        .fullScreenCover(isPresented: $showListen) {
            ListenPlayerView(book: book)
        }
        .onChange(of: showThemes) { _, isPresented in
            if !isPresented, let settings = viewModel.settings {
                viewModel.apply(settings: settings)
            }
        }
    }

    // MARK: - 主题颜色

    private var themeBackground: Color {
        viewModel.settings?.theme.backgroundColor ?? .black
    }

    private var themeForeground: Color {
        viewModel.settings?.theme.textColor ?? .white
    }

    private var chromeColor: Color {
        themeForeground.opacity(0.8)
    }

    // MARK: - 内容分支

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            ProgressView().tint(themeForeground)
        case .failed(let message):
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(themeForeground.opacity(0.6))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(themeForeground.opacity(0.8))
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
                    ReaderHostView(viewModel: viewModel, onToggleChrome: { toggleChrome() })
                        .frame(width: size.width, height: size.height)

                    if showChrome {
                        topBar
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        bottomBar
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        overlayButtons
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: showChrome)
                .onAppear {
                    viewModel.relayout(pageSize: size)
                    scheduleChromeHide()
                }
                .onChange(of: size) { _, newSize in
                    viewModel.relayout(pageSize: newSize)
                }
            }
        }
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(sectionLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(chromeColor.opacity(0.7))
                    .lineLimit(1)
                Text(currentChapterTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            Spacer()
            if book.hasAudio {
                Button {
                    showListen = true
                } label: {
                    Image(systemName: "headphones")
                        .font(.title3)
                        .foregroundStyle(chromeColor)
                }
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(chromeColor)
            }
        }
        .padding()
    }

    private var sectionLabel: String {
        guard let ref = viewModel.session?.pageMap.pageRef(globalIndex: viewModel.currentGlobalIndex) else {
            return book.title
        }
        let title = viewModel.session?.document.chapters[safe: ref.chapterIndex]?.title ?? book.title
        if title.hasPrefix("引言") || title.lowercased().contains("introduction") {
            return "引言"
        }
        if title.isEmpty {
            return book.title
        }
        return "章节"
    }

    private var currentChapterTitle: String {
        guard let ref = viewModel.session?.pageMap.pageRef(globalIndex: viewModel.currentGlobalIndex),
              let title = viewModel.session?.document.chapters[safe: ref.chapterIndex]?.title,
              !title.isEmpty else {
            return book.title
        }
        return title
    }

    private var bottomBar: some View {
        HStack {
            Spacer()
            Text("\(viewModel.currentGlobalIndex + 1) / \(viewModel.totalPages)")
                .font(.caption)
                .foregroundStyle(themeForeground.opacity(0.5))
                .monospacedDigit()
                .padding(.trailing, 8)
        }
        .padding(.vertical, 8)
    }

    private var currentSize: CGSize {
        UIScreen.main.bounds.size
    }

    // MARK: - 悬浮菜单

    private var readerMenu: some View {
        VStack(alignment: .trailing, spacing: 8) {
            pillButton(
                title: "Contents · \(Int((book.readingProgress * 100).rounded()))%",
                icon: "list.bullet"
            ) {
                showMenu = false
                showContents = true
            }

            pillButton(title: "Themes & Settings", icon: "textformat") {
                showMenu = false
                showThemes = true
            }
        }
        .padding(.bottom, 12)
    }

    private func pillButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(themeForeground)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().stroke(themeForeground.opacity(0.12), lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
    }

    private var overlayButtons: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                if showMenu {
                    readerMenu
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showMenu.toggle()
                    }
                    scheduleChromeHide()
                } label: {
                    Image(systemName: "circle.grid.3x3.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(themeForeground)
                }
            }
            .padding(20)
        }
    }

    // MARK: - Chrome visibility

    private func toggleChrome() {
        showChrome.toggle()
        if showChrome {
            scheduleChromeHide()
        } else {
            showMenu = false
            chromeHideTask?.cancel()
        }
    }

    private func scheduleChromeHide() {
        chromeHideTask?.cancel()
        chromeHideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                showMenu = false
                showChrome = false
            }
        }
    }

    // MARK: - 亮度

    private func applyBrightness(from settings: ReaderSettings) {
        guard settings.hasCustomBrightness else { return }
        UIScreen.main.brightness = CGFloat(settings.brightness)
    }
}

// MARK: - Array helper

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
