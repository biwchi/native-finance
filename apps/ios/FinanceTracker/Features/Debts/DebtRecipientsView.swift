import SwiftUI

struct DebtRecipientsView: View {
    private enum Editor: Identifiable {
        case create
        case edit(Debt)

        var id: String {
            switch self {
            case .create: "create"
            case let .edit(debt): debt.id.uuidString
            }
        }
    }

    private enum PresentedAlert: Identifiable {
        case delete(Debt)
        case outstandingLoans
        case error(String)

        var id: String {
            switch self {
            case let .delete(debt): "delete-\(debt.id)"
            case .outstandingLoans: "outstandingLoans"
            case .error: "error"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var transactionStore: TransactionStore
    var selection: Binding<UUID?>? = nil
    @State private var editor: Editor?
    @State private var editMode: EditMode = .inactive
    @State private var isUpdatingOrder = false
    @State private var deletingDebtID: UUID?
    @State private var presentedAlert: PresentedAlert?
    @State private var didCreateSelection = false

    var body: some View {
        NavigationStack {
            AppList {
                AppSection {
                    if transactionStore.debts.isEmpty {
                        ContentUnavailableView("No recipients", iconName: "user",
                            description: Text("Add someone to keep track of the money you lend them."))
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(transactionStore.debts) { debt in
                            recipientButton(debt)
                        }
                        .onMove(perform: moveRecipients)
                        .onDelete(perform: requestDeletion)
                        .moveDisabled(isBusy)
                        .deleteDisabled(isBusy)
                    }
                }
            }
            .animateListChanges(value: transactionStore.debts.map(\.id))
            .listStyle(.insetGrouped)
            .environment(\.editMode, $editMode)
            .navigationTitle("Debt recipients")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isBusy)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { AppIcon("xmark", size: AppControlSize.iconButtonGlyph) }
                        .accessibilityLabel("Close")
                        .disabled(isBusy)
                        .legacyToolbarIcon()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editMode.isEditing ? "Done" : "Edit") {
                        withAnimation {
                            editMode = editMode.isEditing ? .inactive : .active
                        }
                    }
                    .disabled(transactionStore.debts.isEmpty || isBusy)
                    .legacyToolbarControl()
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton("Add recipient") { editor = .create }
                    .disabled(isBusy)
                    .accessibilityIdentifier("addRecipientButton")
                    .padding(.horizontal, AppSpacing.extraLarge)
                    .padding(.vertical, AppSpacing.medium)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onChange(of: transactionStore.debts.isEmpty) { _, isEmpty in
            if isEmpty { editMode = .inactive }
        }
        .task { await transactionStore.loadDebts() }
        .appSheet(item: $editor, onDismiss: {
            if didCreateSelection { dismiss() }
        }) { destination in
            switch destination {
            case .create:
                DebtEditorView { debt in
                    if let selection {
                        selection.wrappedValue = debt.id
                        didCreateSelection = true
                    }
                }
            case let .edit(debt):
                DebtEditorView(debt: debt) { _ in }
            }
        }
        .alert(item: $presentedAlert) { alert in
            switch alert {
            case let .delete(debt):
                Alert(
                    title: Text("Delete \(debt.name)?"),
                    message: Text("This removes the recipient from your list. You can add them again later."),
                    primaryButton: .destructive(Text("Delete")) {
                        Task { await deleteRecipient(debt) }
                    },
                    secondaryButton: .cancel()
                )
            case .outstandingLoans:
                Alert(
                    title: Text("Recipient has outstanding loans"),
                    message: Text("Mark the loans as returned or move them to another recipient before deleting."),
                    dismissButton: .default(Text("OK"))
                )
            case let .error(message):
                Alert(title: Text("Couldn't update recipients"), message: Text(message), dismissButton: .default(Text("OK")))
            }
        }
    }

    private func recipientButton(_ debt: Debt) -> some View {
        let selectsRecipient = selection != nil && !editMode.isEditing
        let isSelected = selection?.wrappedValue == debt.id
        let count = transactionStore.debtTransactions.filter { ($0.debtId ?? $0.debt?.id) == debt.id }.count

        return Button {
            if selectsRecipient {
                selection?.wrappedValue = debt.id
                dismiss()
            } else {
                editor = .edit(debt)
            }
        } label: {
            HStack(spacing: AppSpacing.medium) {
                DebtIcon(debt: debt)
                VStack(alignment: .leading, spacing: 2) {
                    Text(debt.name)
                        .foregroundStyle(.primary)
                    Text(count == 0 ? "No outstanding loans" : "\(count) outstanding \(count == 1 ? "loan" : "loans")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: AppSpacing.small)
                if deletingDebtID == debt.id {
                    ProgressView()
                } else if !selectsRecipient {
                    AppIcon("nav-arrow-right", size: 12)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                } else if isSelected {
                    AppIcon("check", size: 17)
                        .foregroundStyle(AppColor.accent)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityAddTraits(selectsRecipient && isSelected ? .isSelected : [])
        .accessibilityHint(selectsRecipient ? "Select recipient and close" : "Edit recipient name, icon, and color")
        .circleSwipeActions(isEnabled: !isBusy && !editMode.isEditing) {
            CircleSwipeAction(title: "Delete", icon: "trash") {
                requestDeletion(debt)
            }
            CircleSwipeAction(title: "Edit", icon: "edit-pencil", tint: .gray) {
                editor = .edit(debt)
            }
        }
    }

    private var isBusy: Bool { isUpdatingOrder || deletingDebtID != nil }

    private func moveRecipients(from source: IndexSet, to destination: Int) {
        var reordered = transactionStore.debts
        reordered.move(fromOffsets: source, toOffset: destination)
        isUpdatingOrder = true
        Task {
            defer { isUpdatingOrder = false }
            do { try await transactionStore.reorderDebts(reordered) }
            catch { presentedAlert = .error(error.localizedDescription) }
        }
    }

    private func requestDeletion(at offsets: IndexSet) {
        guard let index = offsets.first, transactionStore.debts.indices.contains(index) else { return }
        requestDeletion(transactionStore.debts[index])
    }

    private func requestDeletion(_ debt: Debt) {
        if transactionStore.debtTransactions.contains(where: { ($0.debtId ?? $0.debt?.id) == debt.id }) {
            presentedAlert = .outstandingLoans
        } else {
            presentedAlert = .delete(debt)
        }
    }

    private func deleteRecipient(_ debt: Debt) async {
        guard !isBusy else { return }
        deletingDebtID = debt.id
        defer { deletingDebtID = nil }
        do {
            try await transactionStore.deleteDebt(debt)
            if selection?.wrappedValue == debt.id { selection?.wrappedValue = nil }
        } catch {
            presentedAlert = .error(error.localizedDescription)
        }
    }
}
