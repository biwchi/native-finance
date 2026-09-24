import SwiftUI

struct TransactionModeSelector: View {
    let modes: [QuickTransactionMode]
    @Binding var selection: QuickTransactionMode

    var body: some View {
        IconToggleSelector(
            options: modes,
            selection: $selection,
            accessibilityLabel: "Transaction type",
            title: \QuickTransactionMode.title,
            iconName: \QuickTransactionMode.iconName,
            color: \QuickTransactionMode.color,
            accessibilityIdentifier: { "transactionType-\($0.rawValue)" }
        )
            .modifier(TransactionModeSwipe(modes: modes, selection: $selection))
    }
}

struct IconToggleSelector<Option: Identifiable & Hashable>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let options: [Option]
    @Binding var selection: Option
    let accessibilityLabel: String
    let title: (Option) -> String
    let iconName: (Option) -> String
    let color: (Option) -> Color
    let accessibilityIdentifier: (Option) -> String

    var body: some View {
        buttons
            .frame(height: AppControlSize.minimumTapTarget)
            .modifier(TransactionGlassSurface(shape: Capsule(), isToolbarControl: true))
            .sensoryFeedback(.selection, trigger: selection)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityLabel)
            // A form or toolbar animation must not change the selector's timing.
            .transaction { $0.animation = nil }
    }

    private var buttons: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                modeMenu
            } else {
                ViewThatFits(in: .horizontal) {
                    inlineButtons
                    modeMenu
                }
            }
        }
    }

    private var inlineButtons: some View {
        // Reserve one title alongside the icon slots, independent of the selection.
        HStack(spacing: 0) {
            Color.clear
                .frame(width: CGFloat(options.count) * AppControlSize.minimumTapTarget,
                       height: AppControlSize.minimumTapTarget)
            OptionTitle(option: selection, options: options, title: title)
                .padding(.trailing, AppSpacing.extraSmall)
        }
        .fixedSize(horizontal: true, vertical: false)
        .hidden()
        .overlay {
            GeometryReader { geometry in
                AnimatedOptions(
                    options: options,
                    selection: $selection,
                    titleWidth: max(0, geometry.size.width - CGFloat(options.count) * AppControlSize.minimumTapTarget),
                    title: title,
                    iconName: iconName,
                    color: color,
                    accessibilityIdentifier: accessibilityIdentifier,
                    animatableData: SelectionWeights(options.map { $0 == selection ? 1 : 0 })
                )
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selection)
            }
        }
    }

    private var modeMenu: some View {
        Menu {
            Picker("Transaction type", selection: $selection) {
                ForEach(options) { option in
                    Label(title(option), icon: iconName(option))
                        .tag(option)
                }
            }
        } label: {
            HStack(spacing: AppSpacing.compact) {
                AppIcon(iconName(selection), size: 16)
                    .foregroundStyle(color(selection))
                OptionTitle(option: selection, options: options, title: title)
                AppIcon("nav-arrow-down", size: 12)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, AppSpacing.medium)
            .frame(minHeight: AppControlSize.minimumTapTarget)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(title(selection))
    }

    /// All changing geometry and label opacity are calculated from the same animation clock.
    private struct AnimatedOptions: View, Animatable {
        @Environment(\.isEnabled) private var isEnabled
        let options: [Option]
        @Binding var selection: Option
        let titleWidth: CGFloat
        let title: (Option) -> String
        let iconName: (Option) -> String
        let color: (Option) -> Color
        let accessibilityIdentifier: (Option) -> String
        var animatableData: SelectionWeights

        private var iconWidth: CGFloat { AppControlSize.minimumTapTarget }

        private func weight(for option: Option) -> Double {
            guard let index = options.firstIndex(of: option), animatableData.values.indices.contains(index) else { return 0 }
            return animatableData.values[index]
        }

        var body: some View {
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: iconWidth + titleWidth - AppSpacing.extraSmall * 2,
                           height: iconWidth - AppSpacing.extraSmall * 2)
                    .offset(x: options.enumerated().reduce(AppSpacing.extraSmall) { offset, item in
                        offset + CGFloat(item.offset) * iconWidth * weight(for: item.element)
                    }, y: AppSpacing.extraSmall)
                    .opacity(isEnabled ? 1 : 0.4)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                ForEach(options) { option in
                    let index = options.firstIndex(of: option) ?? 0
                    let precedingTitleWidth = options.prefix(index).reduce(0.0) { $0 + weight(for: $1) } * titleWidth
                    optionButton(option)
                        .offset(x: CGFloat(index) * iconWidth + precedingTitleWidth)
                }
            }
            .frame(width: CGFloat(options.count) * iconWidth + titleWidth,
                   height: iconWidth, alignment: .topLeading)
            // These values already contain the interpolated frame. Do not animate them again
            // inside a Button, its style, or its Text, including when a press ends mid-transition.
            .transaction { $0.animation = nil }
        }

        private func optionButton(_ option: Option) -> some View {
            Button {
                selection = option
            } label: {
                ZStack(alignment: .leading) {
                    AppIcon(iconName(option), size: 16, relativeTo: .caption)
                        .foregroundStyle(color(option))
                        .frame(width: iconWidth, height: iconWidth)
                    Text(title(option))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: max(0, titleWidth - AppSpacing.extraSmall))
                        .foregroundStyle(.primary)
                        .offset(x: iconWidth - AppSpacing.small)
                        .opacity(weight(for: option))
                        .accessibilityHidden(true)
                }
                .frame(width: iconWidth + weight(for: option) * titleWidth,
                       height: iconWidth, alignment: .leading)
                .clipped()
                .contentShape(Rectangle())
            }
            .buttonStyle(ModeButtonStyle())
            .accessibilityLabel(title(option))
            .accessibilityIdentifier(accessibilityIdentifier(option))
            .accessibilityAddTraits(selection == option ? .isSelected : [])
        }
    }

    private struct OptionTitle: View {
        let option: Option
        let options: [Option]
        let title: (Option) -> String

        var body: some View {
            ZStack {
                ForEach(options) { candidate in
                    Text(title(candidate))
                        .hidden()
                }
            }
            .overlay { Text(title(option)) }
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }

    private struct ModeButtonStyle: ButtonStyle {
        @Environment(\.isEnabled) private var isEnabled

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
        }
    }
}

private struct SelectionWeights: VectorArithmetic {
    var values: [Double]

    init(_ values: [Double]) {
        self.values = values
    }

    static var zero: Self { Self([]) }

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(combine(lhs.values, rhs.values, +))
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        Self(combine(lhs.values, rhs.values, -))
    }

    mutating func scale(by rhs: Double) {
        values = values.map { $0 * rhs }
    }

    var magnitudeSquared: Double {
        values.reduce(0) { $0 + $1 * $1 }
    }

    private static func combine(
        _ lhs: [Double],
        _ rhs: [Double],
        _ operation: (Double, Double) -> Double
    ) -> [Double] {
        (0..<max(lhs.count, rhs.count)).map { index in
            operation(lhs.indices.contains(index) ? lhs[index] : 0, rhs.indices.contains(index) ? rhs[index] : 0)
        }
    }
}
