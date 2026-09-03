import SwiftUI

private struct DesignSystemPreview: View {
    var body: some View {
        VStack(spacing: AppSpacing.large) {
            HStack {
                AccentSelectionButton("Unselected", isSelected: false) {}
                AccentSelectionButton("Selected", isSelected: true) {}
            }
            PrimaryActionButton("Save changes") {}
            PrimaryActionButton("Saving…", isLoading: true) {}
            HStack {
                PrimaryIconButton("Review transaction", iconName: "arrow-up") {}
                PrimaryActionButton("Try Again", appearance: .prominent) {}
            }
            PrimaryActionButton("Add account", appearance: .glass) {}
                .controlSize(.large)
        }
        .padding()
        .background(AppColor.background)
    }
}

#Preview("Design system — Light") {
    DesignSystemPreview()
        .preferredColorScheme(.light)
}

#Preview("Design system — Dark") {
    DesignSystemPreview()
        .preferredColorScheme(.dark)
}
