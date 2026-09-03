import SwiftUI

struct FinanceSectionHeader<Action: View>: View {
    let title: String
    @ViewBuilder let action: Action

    init(_ title: String, @ViewBuilder action: () -> Action) {
        self.title = title
        self.action = action()
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            action
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: AppControlSize.minimumTapTarget)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
        }
        .textCase(nil)
    }
}
