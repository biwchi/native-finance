import SwiftUI

#Preview {
    AddTransactionView()
        .environmentObject(AccountStore())
        .environmentObject(TransactionStore())
}

#Preview("Glass controls · Light") {
    VStack(spacing: AppSpacing.large) {
        ForEach(QuickTransactionMode.allCases) { mode in
            TransactionModeSelector(modes: QuickTransactionMode.allCases, selection: .constant(mode))
        }
        TransactionModeSelector(modes: QuickTransactionMode.allCases, selection: .constant(.expense))
            .disabled(true)
        PrimaryActionButton("Add transaction", appearance: .glass) {}
            .controlSize(.large)
        PrimaryActionButton("Saving…", isLoading: true, appearance: .glass) {}
            .controlSize(.large)
    }
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Glass controls · Dark") {
    VStack(spacing: AppSpacing.large) {
        ForEach(QuickTransactionMode.allCases) { mode in
            TransactionModeSelector(modes: QuickTransactionMode.allCases, selection: .constant(mode))
        }
        TransactionModeSelector(modes: QuickTransactionMode.allCases, selection: .constant(.expense))
            .disabled(true)
        PrimaryActionButton("Add transaction", appearance: .glass) {}
            .controlSize(.large)
        PrimaryActionButton("Saving…", isLoading: true, appearance: .glass) {}
            .controlSize(.large)
    }
    .padding()
    .preferredColorScheme(.dark)
}
