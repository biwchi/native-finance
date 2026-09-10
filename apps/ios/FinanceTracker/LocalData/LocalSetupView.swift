import SwiftUI

struct LocalSetupView: View {
    @ObservedObject var repository: LocalFinanceRepository
    @ObservedObject var sync: SyncCoordinator
    var body: some View {
        VStack(spacing: 20) {
            Text("Prepare your finance data").font(.title2.bold())
            Text("Your accounts and history will be saved on this iPhone. After this first import, you can use the app offline.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            if let error = repository.storageError ?? sync.setupError {
                Text(error).foregroundStyle(AppColor.warningText)
                PrimaryActionButton("Try again") { sync.requestSync() }
                    .disabled(sync.isImporting || repository.database == nil)
            } else {
                ProgressView("Importing your data…")
            }
        }
        .padding(28)
    }
}
