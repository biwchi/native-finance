import SwiftUI

struct DeleteDataConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var confirmation = ""
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @FocusState private var isConfirmationFocused: Bool

    let title: String
    let explanation: String
    let delete: (String) async throws -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(explanation)
                    Text("This cannot be undone.")
                        .fontWeight(.semibold)
                }
                Section {
                    TextField("confirm", text: $confirmation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isConfirmationFocused)
                        .accessibilityLabel("Type confirm to allow deletion")
                        .disabled(isDeleting)
                } header: {
                    Text("Type confirm to continue")
                } footer: {
                    Text("Enter the exact word confirm in lowercase.")
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
                Section {
                    Button(role: .destructive) {
                        guard confirmation == "confirm", !isDeleting else { return }
                        isDeleting = true
                        errorMessage = nil
                        isConfirmationFocused = false
                        Task { await performDeletion() }
                    } label: {
                        HStack {
                            Text(title)
                            Spacer()
                            if isDeleting { ProgressView().tint(.secondary) }
                        }
                    }
                    .disabled(confirmation != "confirm" || isDeleting)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isDeleting)
                }
            }
            .interactiveDismissDisabled(isDeleting)
        }
    }

    @MainActor
    private func performDeletion() async {
        defer { isDeleting = false }
        do {
            try await delete(confirmation)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            confirmation = ""
        }
    }
}
