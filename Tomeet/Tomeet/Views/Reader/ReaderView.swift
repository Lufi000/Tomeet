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
    @State private var showContents = false
    @State private var showSearch = false
    @State private var showThemes = false

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
        .sheet(isPresented: $showSearch) {
            SearchBookSheet(book: book)
        }
        .sheet(isPresented: $showThemes) {
            ThemesSettingsSheet(settings: viewModel.settings ?? ReaderSettings())
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
                    .foregroundStyle(chromeColor)
            }
        }
        .padding()
    }

    private var bottomBar: some View {
        HStack {
            Spacer()
            Text("\(viewModel.currentGlobalIndex + 1) of \(viewModel.totalPages)")
                .font(.caption)
                .foregroundStyle(themeForeground.opacity(0.6))
            Spacer()
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

            pillButton(title: "Search Book", icon: "magnifyingglass") {
                showMenu = false
                showSearch = true
            }

            pillButton(title: "Themes & Settings", icon: "textformat") {
                showMenu = false
                showThemes = true
            }

            HStack(spacing: 12) {
                circleButton("square.and.arrow.up")
                circleButton("lock.rotation")
                circleButton("doc.text")
                circleButton("bookmark")
            }
            .padding(.top, 4)
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

    private func circleButton(_ systemImage: String) -> some View {
        Button {} label: {
            Image(systemName: systemImage)
                .font(.system(size: 18))
                .frame(width: 44, height: 44)
                .foregroundStyle(themeForeground)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().stroke(themeForeground.opacity(0.12), lineWidth: 0.5))
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
                } label: {
                    Image(systemName: "circle.grid.3x3.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(themeForeground)
                }
            }
            .padding(20)
        }
    }

    // MARK: - 亮度

    private func applyBrightness(from settings: ReaderSettings) {
        guard settings.hasCustomBrightness else { return }
        UIScreen.main.brightness = CGFloat(settings.brightness)
    }
}
