import SwiftUI

struct TransactionModeSelector: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var selectionAnimation
    let modes: [QuickTransactionMode]
    @Binding var selection: QuickTransactionMode

    var body: some View {
        buttons
            .padding(AppSpacing.extraSmall)
            .modifier(TransactionGlassSurface(shape: RoundedRectangle(cornerRadius: AppRadius.extraLarge)))
            .frame(maxWidth: .infinity)
            .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: selection)
            .sensoryFeedback(.selection, trigger: selection)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Transaction type")
    }

    private var buttons: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                expandedButtons
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppSpacing.extraSmall) { modeButtons }
                        .fixedSize(horizontal: true, vertical: false)
                    expandedButtons
                }
            }
        }
    }

    private var modeButtons: some View {
        ForEach(modes) { mode in
            modeButton(mode)
        }
    }

    private var expandedButtons: some View {
        VStack(spacing: AppSpacing.extraSmall) {
            modeButton(selection)
            HStack(spacing: AppSpacing.extraSmall) {
                ForEach(modes.filter { $0 != selection }) { mode in
                    modeButton(mode)
                }
            }
        }
    }

    private func modeButton(_ mode: QuickTransactionMode) -> some View {
        Button {
            selection = mode
        } label: {
            HStack(spacing: AppSpacing.small) {
                AppIcon(mode.iconName, size: 20)
                    .foregroundStyle(mode.color)
                if selection == mode {
                    Text(mode.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, selection == mode ? AppSpacing.medium : AppSpacing.small)
            .frame(minWidth: AppControlSize.minimumTapTarget, minHeight: AppControlSize.minimumTapTarget)
            .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? AppSpacing.small : 0)
            .background {
                if selection == mode {
                    Capsule()
                        .fill(AppColor.controlFill)
                        .matchedGeometryEffect(id: "selected-kind", in: selectionAnimation)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(ModeButtonStyle())
        .accessibilityLabel(mode.title)
        .accessibilityAddTraits(selection == mode ? .isSelected : [])
    }

    private struct ModeButtonStyle: ButtonStyle {
        @Environment(\.isEnabled) private var isEnabled

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
        }
    }
}
