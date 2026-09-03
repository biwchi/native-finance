import SwiftUI

struct TransactionModeSelector: View {
    let modes: [QuickTransactionMode]
    @Binding var selection: QuickTransactionMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(modes) { mode in
                modeButton(mode)
            }
        }
        .padding(3)
        .background(AppColor.controlFill, in: Capsule())
        .animation(.snappy(duration: 0.1), value: selection)
    }

    private func modeButton(_ mode: QuickTransactionMode) -> some View {
        let isSelected = selection == mode

        return Button {
            selection = mode
        } label: {
            HStack(spacing: AppSpacing.compact) {
                AppIcon(mode.iconName, size: 14)
                    .foregroundStyle(isSelected ? mode.color : .primary)
                    .accessibilityHidden(true)

                Text(mode.title)
                    .foregroundStyle(isSelected ? mode.color : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .frame(maxWidth: .infinity, minHeight: 42)
            .background {
                if isSelected {
                    Capsule()
                        .fill(mode.color.opacity(0.15))
                        .shadow(color: mode.color.opacity(0.18), radius: 2, y: 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
