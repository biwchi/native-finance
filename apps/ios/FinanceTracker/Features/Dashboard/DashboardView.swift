import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)

                VStack(spacing: 8) {
                    Text("Finance Tracker")
                        .font(.largeTitle.bold())

                    Text("Your accounts and transactions will appear here.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                backendStatus

                Button("Check again") {
                    Task {
                        await viewModel.checkBackend()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.state == .loading)
            }
            .padding(24)
            .navigationTitle("Overview")
            .accountSelectorToolbar()
        }
        .task {
            guard viewModel.state == .idle else { return }
            await viewModel.checkBackend()
        }
    }

    @ViewBuilder
    private var backendStatus: some View {
        switch viewModel.state {
        case .idle, .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text("Connecting to the backend")
            }

        case let .connected(service):
            Label("Connected to \(service)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)

        case let .failed(message):
            VStack(spacing: 8) {
                Label("Backend unavailable", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(AccountStore())
}
