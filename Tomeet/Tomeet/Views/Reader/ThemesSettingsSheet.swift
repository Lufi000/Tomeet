import SwiftData
import SwiftUI

/// 主题与设置 Sheet：字号、亮度、主题网格、Customize。
struct ThemesSettingsSheet: View {
    let settings: ReaderSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showAdvanced = false

    private let fontStep: Double = 1
    private let minFontOffset: Double = -4
    private let maxFontOffset: Double = 6

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 系统内联标题字体无法定制，标题与 Done 自己画
                HStack {
                    Text("Themes & Settings")
                        .font(.splendid(.headline)).splendidTracking(.headline)
                    Spacer()
                    Button("Done") { dismiss() }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                ScrollView {
                    VStack(spacing: 24) {
                        fontSizeSection
                        brightnessSection
                        themeGrid
                        customizeButton
                        if showAdvanced {
                            advancedSection
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding()
                }
            }
            .background(Color(white: 0.15).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
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
                .font(.splendid(isIncrease ? .title2 : .callout, weight: .semibold)).splendidTracking(isIncrease ? .title2 : .callout)
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
                        UIScreen.current?.brightness = CGFloat(newValue)
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
                Text("Size")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(theme.textColor)
                Text(theme.displayName)
                    .font(.splendid(.caption, weight: .medium)).splendidTracking(.caption)
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
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showAdvanced.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: showAdvanced ? "chevron.up" : "gearshape")
                Text(showAdvanced ? "Hide Details" : "Customize")
                    .font(.splendid(.subheadline, weight: .semibold)).splendidTracking(.subheadline)
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

    private var advancedSection: some View {
        VStack(spacing: 20) {
            sliderRow(
                title: "Line Height",
                icon: "arrow.up.and.down.text.horizontal",
                value: Binding(
                    get: { settings.lineHeightMultiple },
                    set: { settings.lineHeightMultiple = $0; try? modelContext.save() }
                ),
                range: 1.0...2.0,
                step: 0.05
            )
            sliderRow(
                title: "Paragraph Spacing",
                icon: "text.line.last.and.arrowtriangle.forward",
                value: Binding(
                    get: { settings.paragraphSpacing },
                    set: { settings.paragraphSpacing = $0; try? modelContext.save() }
                ),
                range: 0...32,
                step: 2
            )
            stepperRow(
                title: "First-Line Indent",
                icon: "text.alignleft",
                value: Binding(
                    get: { settings.firstLineIndent },
                    set: { settings.firstLineIndent = $0; try? modelContext.save() }
                ),
                step: 0.5,
                range: 0...4
            )
            sliderRow(
                title: "Horizontal Margin",
                icon: "arrow.left.and.right.square",
                value: Binding(
                    get: { settings.horizontalMargin },
                    set: { settings.horizontalMargin = $0; try? modelContext.save() }
                ),
                range: 12...64,
                step: 2
            )
            sliderRow(
                title: "Vertical Margin",
                icon: "arrow.up.and.down.square",
                value: Binding(
                    get: { settings.verticalMargin },
                    set: { settings.verticalMargin = $0; try? modelContext.save() }
                ),
                range: 12...80,
                step: 2
            )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }

    private func sliderRow(title: String, icon: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.splendid(.subheadline, weight: .semibold)).splendidTracking(.subheadline)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.splendid(.caption).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
                .tint(.white)
        }
    }

    private func stepperRow(title: String, icon: String, value: Binding<Double>, step: Double, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.splendid(.subheadline, weight: .semibold)).splendidTracking(.subheadline)
            Spacer()
            Stepper(
                value: Binding(
                    get: { value.wrappedValue },
                    set: { newValue in
                        value.wrappedValue = min(max(newValue, range.lowerBound), range.upperBound)
                        try? modelContext.save()
                    }
                ),
                in: range,
                step: step
            ) {
                Text(String(format: "%.1f em", value.wrappedValue))
                    .font(.splendid(.caption).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func themeBorderColor(_ theme: ReaderTheme) -> Color {
        if settings.theme == theme { return .white }
        return theme.previewUsesDarkAccents ? Color.black.opacity(0.15) : Color.white.opacity(0.15)
    }

    private func themeBorderWidth(_ theme: ReaderTheme) -> CGFloat {
        settings.theme == theme ? 3 : 0.5
    }
}
