import SwiftUI

struct TransactionModeSelector: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let modes: [QuickTransactionMode]
    @Binding var selection: QuickTransactionMode

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: AppSpacing.extraSmall) {
                    buttons
                }
            } else {
                buttons
            }
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: selection)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Transaction type")
    }

    private var buttons: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: AppSpacing.compact) { modeButtons }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppSpacing.compact) { modeButtons }
                        .fixedSize(horizontal: true, vertical: false)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.compact) {
                        modeButtons
                    }
                }
            }
        }
    }

    private var modeButtons: some View {
        ForEach(modes) { mode in
            AccentSelectionButton(
                mode.title,
                isSelected: selection == mode,
                iconName: mode.iconName,
                appearance: .glass,
                selectionTint: mode.color
            ) {
                selection = mode
            }
        }
    }
}
