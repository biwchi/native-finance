import SwiftUI

struct AccentSelectionButton: View {
    @Environment(\.isEnabled) private var isEnabled

    let title: String
    let isSelected: Bool
    let action: () -> Void

    init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .frame(maxWidth: .infinity, minHeight: 40)
                .foregroundStyle(isSelected && isEnabled ? AppColor.onAccent : Color.primary)
                .background(
                    isSelected ? AppColor.accent : Color.clear,
                    in: RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
