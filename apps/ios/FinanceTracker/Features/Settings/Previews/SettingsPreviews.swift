import SwiftUI

#Preview {
    NavigationStack { SettingsView() }
        .environmentObject(TransactionStore())
}
