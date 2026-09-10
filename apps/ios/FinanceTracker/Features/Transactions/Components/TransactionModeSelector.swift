import SwiftUI

struct TransactionModeSelector: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let modes: [QuickTransactionMode]
    @Binding var selection: QuickTransactionMode

    var body: some View {
        buttons
            .padding(.horizontal, AppSpacing.extraSmall)
            .frame(height: AppControlSize.minimumTapTarget)
            .modifier(TransactionGlassSurface(shape: Capsule()))
            .modifier(TransactionModeSwipe(modes: modes, selection: $selection))
            .sensoryFeedback(.selection, trigger: selection)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Transaction type")
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
        // Measure a constant outer width independently of the animated buttons.
        HStack(spacing: 0) {
            Color.clear
                .frame(width: CGFloat(modes.count) * AppControlSize.minimumTapTarget,
                       height: AppControlSize.minimumTapTarget)
            modeTitle(selection)
                .padding(.trailing, AppSpacing.small)
        }
        .fixedSize(horizontal: true, vertical: false)
        .hidden()
        .overlay {
            GeometryReader { geometry in
                let titleWidth = max(0, geometry.size.width - CGFloat(modes.count) * AppControlSize.minimumTapTarget)
                HStack(spacing: 0) {
                    ForEach(modes) { mode in
                        modeButton(mode, titleWidth: titleWidth)
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: selection)
            }
        }
    }

    private var modeMenu: some View {
        Menu {
            Picker("Transaction type", selection: $selection) {
                ForEach(modes) { mode in
                    Label(mode.title, icon: mode.iconName)
                        .tag(mode)
                }
            }
        } label: {
            HStack(spacing: AppSpacing.compact) {
                AppIcon(selection.iconName, size: 16)
                    .foregroundStyle(selection.color)
                modeTitle(selection)
                AppIcon("nav-arrow-down", size: 12)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, AppSpacing.small)
            .frame(minHeight: AppControlSize.minimumTapTarget)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("Transaction type")
        .accessibilityValue(selection.title)
    }

    private func modeButton(_ mode: QuickTransactionMode, titleWidth: CGFloat) -> some View {
        Button {
            selection = mode
        } label: {
            HStack(spacing: 0) {
                AppIcon(mode.iconName, size: 16)
                    .foregroundStyle(mode.color)
                    .frame(width: AppControlSize.minimumTapTarget, height: AppControlSize.minimumTapTarget)
                // Keep every label alive and reveal it horizontally, without fading or reparenting icons.
                Text(mode.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: selection == mode ? titleWidth : 0, alignment: .leading)
                    .clipped()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ModeButtonStyle())
        .accessibilityLabel(mode.title)
        .accessibilityAddTraits(selection == mode ? .isSelected : [])
    }

    private func modeTitle(_ mode: QuickTransactionMode) -> some View {
        // Reserve the widest title so switching modes cannot resize the toolbar.
        ZStack {
            ForEach(modes) { candidate in
                Text(candidate.title)
                    .hidden()
            }
            Text(mode.title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private struct ModeButtonStyle: ButtonStyle {
        @Environment(\.isEnabled) private var isEnabled

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
        }
    }
}
