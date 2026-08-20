import SwiftData
import SwiftUI

/// 主题与设置 Sheet：字号、亮度、主题网格、Customize。
struct ThemesSettingsSheet: View {
    let settings: ReaderSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let fontStep: Double = 1
    private let minFontOffset: Double = -4
    private let maxFontOffset: Double = 6

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    fontSizeSection
                    brightnessSection
                    themeGrid
                    customizeButton
                }
                .padding()
            }
            .navigationTitle("Themes & Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .background(Color(white: 0.15).ignoresSafeArea())
        }
        .onDisappear {
            try? modelContext.save()
        }
    }

    // MARK: - 字号

    private var fontSizeSection: some View {
        HStack(spacing: 16) {
            fontSizeButton(isIncrease: false)

            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 1, height: 28)

            fontSizeButton(isIncrease: true)

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 16))
                Image(systemName: "circle.righthalf.filled")
                    .font(.system(size: 16))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }

    private func fontSizeButton(isIncrease: Bool) -> some View {
        Button {
            let delta = isIncrease ? fontStep : -fontStep
            let newValue = settings.fontSizeOffset + delta
            guard newValue >= minFontOffset && newValue <= maxFontOffset else { return }
            settings.fontSizeOffset = newValue
            try? modelContext.save()
        } label: {
            Text(isIncrease ? "A" : "A")
                .font(.system(size: isIncrease ? 24 : 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 亮度

    private var brightnessSection: some View {
        HStack(spacing: 12) {
            Image(systemName: "sun.min")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)

            Slider(
                value: Binding(
                    get: { settings.brightness },
                    set: { newValue in
                        settings.brightness = newValue
                        settings.hasCustomBrightness = true
                        UIScreen.main.brightness = CGFloat(newValue)
                        try? modelContext.save()
                    }
                ),
                in: 0...1
            )
            .tint(.white)

            Image(systemName: "sun.max")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - 主题网格

    private var themeGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ],
            spacing: 12
        ) {
            ForEach(ReaderTheme.allCases) { theme in
                themeCard(theme)
            }
        }
    }

    private func themeCard(_ theme: ReaderTheme) -> some View {
        Button {
            settings.theme = theme
            try? modelContext.save()
        } label: {
            VStack(spacing: 8) {
                Text("大小")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(theme.textColor)
                Text(theme.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.textColor.opacity(0.8))
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(themeBorderColor(theme), lineWidth: themeBorderWidth(theme))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Customize

    private var customizeButton: some View {
        Button {} label: {
            HStack(spacing: 8) {
                Image(systemName: "gearshape")
                Text("Customize")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )
        }
        .buttonStyle(.plain)
    }

    private func themeBorderColor(_ theme: ReaderTheme) -> Color {
        if settings.theme == theme { return .white }
        return theme.previewUsesDarkAccents ? Color.black.opacity(0.15) : Color.white.opacity(0.15)
    }

    private func themeBorderWidth(_ theme: ReaderTheme) -> CGFloat {
        settings.theme == theme ? 3 : 0.5
    }
}
