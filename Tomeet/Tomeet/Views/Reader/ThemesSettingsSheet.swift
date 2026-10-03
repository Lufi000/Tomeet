import SwiftData
import SwiftUI

/// 主题与设置面板。布局对齐 Apple Books：
/// 字号胶囊 → 行距预设 + 自动夜间 → 主题网格 → Customize。
/// 不含亮度：亮度归系统管（控制中心 / 自动亮度），见 `ScreenBrightnessGuardTests`。
struct ThemesSettingsSheet: View {
    let settings: ReaderSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var showAdvanced = false

    private let fontStep: Double = 1
    private let minFontOffset: Double = -4
    private let maxFontOffset: Double = 6

    private var isDarkAppearance: Bool { colorScheme == .dark }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                titleBar
                ScrollView {
                    VStack(spacing: Spacing.xl) {
                        controlPill
                        themeGrid
                        customizeButton
                        if showAdvanced {
                            advancedSection
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(Spacing.lg)
                }
            }
            .background(Theme.panelSurface.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .onDisappear {
            try? modelContext.save()
        }
    }

    // MARK: - 标题栏

    /// 系统内联标题字体无法定制，标题与 Done 自己画。
    private var titleBar: some View {
        HStack {
            Text("Themes & Settings")
                .tText(.button, color: Theme.panelInk)
            Spacer()
            Button("Done") { dismiss() }
                .tText(.button, color: Theme.panelInk)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
    }

    // MARK: - 字号 + 行距 + 自动夜间

    private var controlPill: some View {
        HStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.lg) {
                fontSizeButton(isIncrease: false)
                Rectangle()
                    .fill(Theme.panelHairline)
                    .frame(width: 1, height: Spacing.xl)
                fontSizeButton(isIncrease: true)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Capsule().fill(.ultraThinMaterial))

            HStack(spacing: Spacing.lg) {
                spacingMenu
                Rectangle()
                    .fill(Theme.panelHairline)
                    .frame(width: 1, height: Spacing.xl)
                autoNightToggle
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Capsule().fill(.ultraThinMaterial))
        }
    }

    private func fontSizeButton(isIncrease: Bool) -> some View {
        Button {
            let delta = isIncrease ? fontStep : -fontStep
            let newValue = settings.fontSizeOffset + delta
            guard newValue >= minFontOffset && newValue <= maxFontOffset else { return }
            settings.fontSizeOffset = newValue
            save()
        } label: {
            Text("A")
                .tText(isIncrease ? .sectionTitle : .secondary, color: Theme.panelInk)
                .frame(width: Spacing.xxl, height: Spacing.xxl)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isIncrease ? "Increase text size" : "Decrease text size")
    }

    /// 行距/段距三档预设。裸滑块对读者没有意义，档位才能一眼做决定。
    private var spacingMenu: some View {
        Menu {
            Picker("Spacing", selection: spacingBinding) {
                ForEach(SpacingPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
        } label: {
            Image(systemName: "text.line.spacing")
                .tIcon(IconRole.control, weight: .semibold)
                .foregroundStyle(Theme.panelInk)
                .frame(width: Spacing.xxl, height: Spacing.xxl)
        }
        .accessibilityLabel("Line spacing")
    }

    private var spacingBinding: Binding<SpacingPreset> {
        Binding(
            get: { settings.spacingPreset },
            set: { settings.apply($0); save() }
        )
    }

    /// 自动夜间：跟随系统外观在浅色/深色主题间切换。
    private var autoNightToggle: some View {
        Button {
            settings.autoNightTheme.toggle()
            save()
        } label: {
            Image(systemName: "circle.righthalf.filled")
                .tIcon(IconRole.control, weight: .semibold)
                .foregroundStyle(settings.autoNightTheme ? Theme.accent : Theme.panelInkSecondary)
                .frame(width: Spacing.xxl, height: Spacing.xxl)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Auto night theme")
        .accessibilityValue(settings.autoNightTheme ? "On" : "Off")
    }

    // MARK: - 主题网格

    private var themeGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: Spacing.md
        ) {
            ForEach(ReaderTheme.allCases) { theme in
                themeCard(theme)
            }
        }
    }

    private func themeCard(_ theme: ReaderTheme) -> some View {
        let isSelected = settings.selectedTheme(isDarkAppearance: isDarkAppearance) == theme
        return Button {
            settings.setTheme(theme, isDarkAppearance: isDarkAppearance)
            save()
        } label: {
            VStack(spacing: Spacing.sm) {
                Text("大小")
                    .tText(.sectionTitle, color: theme.textColor)
                Text(theme.displayName)
                    .tText(.hint, color: theme.textColor.opacity(0.8))
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(theme.backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(
                        isSelected ? Theme.panelInk : themeBorderColor(theme),
                        lineWidth: isSelected ? 3 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    /// 未选中时的描边：Paper 是浅色，压在白面板上要用深色描边才看得见。
    private func themeBorderColor(_ theme: ReaderTheme) -> Color {
        theme.previewUsesDarkAccents ? Theme.solidInk.opacity(0.15) : Theme.panelHairline
    }

    // MARK: - Customize

    private var customizeButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showAdvanced.toggle()
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: showAdvanced ? "chevron.up" : "gearshape")
                    .tIcon(IconRole.control)
                Text(showAdvanced ? "Hide Details" : "Customize")
                    .tText(.button, color: Theme.panelInk)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
        }
        .buttonStyle(.plain)
    }

    /// 只留"每本书都可能想调"的边距与缩进；行距段距已由上面的预设覆盖。
    private var advancedSection: some View {
        VStack(spacing: Spacing.lg) {
            stepperRow(
                title: "First-Line Indent",
                icon: "text.alignleft",
                value: Binding(
                    get: { settings.firstLineIndent },
                    set: { settings.firstLineIndent = $0; save() }
                ),
                step: 0.5,
                range: 0...4
            )
            sliderRow(
                title: "Horizontal Margin",
                icon: "arrow.left.and.right.square",
                value: Binding(
                    get: { settings.horizontalMargin },
                    set: { settings.horizontalMargin = $0; save() }
                ),
                range: 12...64,
                step: 2
            )
            sliderRow(
                title: "Vertical Margin",
                icon: "arrow.up.and.down.square",
                value: Binding(
                    get: { settings.verticalMargin },
                    set: { settings.verticalMargin = $0; save() }
                ),
                range: 12...80,
                step: 2
            )
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }

    private func sliderRow(
        title: String,
        icon: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .tIcon(IconRole.badge)
                    .foregroundStyle(Theme.panelInkSecondary)
                Text(title)
                    .tText(.secondary, color: Theme.panelInk)
                Spacer()
                Text(String(format: "%.0f", value.wrappedValue))
                    .tText(.meta, color: Theme.panelInkSecondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: step)
                .tint(Theme.panelInk)
        }
    }

    private func stepperRow(
        title: String,
        icon: String,
        value: Binding<Double>,
        step: Double,
        range: ClosedRange<Double>
    ) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .tIcon(IconRole.badge)
                .foregroundStyle(Theme.panelInkSecondary)
            Text(title)
                .tText(.secondary, color: Theme.panelInk)
            Spacer()
            Stepper(
                value: Binding(
                    get: { value.wrappedValue },
                    set: { newValue in
                        value.wrappedValue = min(max(newValue, range.lowerBound), range.upperBound)
                        save()
                    }
                ),
                in: range,
                step: step
            ) {
                Text(String(format: "%.1f em", value.wrappedValue))
                    .tText(.meta, color: Theme.panelInkSecondary)
                    .monospacedDigit()
            }
        }
    }

    private func save() {
        try? modelContext.save()
    }
}
