import SwiftUI

struct AssistantView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Ask about your money",
                iconName: "sparks",
                description: Text("The assistant will help you understand your finances.")
            )
            .scrollEdgeFades(background: AppColor.background)
            .accountSelectorToolbar()
        }
    }
}

#Preview {
    AssistantView()
        .environmentObject(AccountStore())
        .environmentObject(TransactionStore())
}
