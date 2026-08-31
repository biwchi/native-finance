import SwiftUI

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore
    @AppStorage("lastTransactionAccountID") private var lastAccountID = ""

    @StateObject private var viewModel = AddTransactionViewModel()
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isPresentingNewCategory = false

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                quickEntrySection
                detailsSection

                if let categoryError = transactionStore.categoryErrorMessage,
                   transactionStore.categories.isEmpty {
                    Section {
                        Label(categoryError, systemImage: "wifi.exclamationmark")
                            .foregroundStyle(.orange)
                    } footer: {
                        Text("You can still save the transaction without a category.")
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New transaction")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Group {
                    if #available(iOS 26.0, *) {
                        submitButton
                            .buttonStyle(.glassProminent)
                    } else {
                        submitButton
                            .buttonStyle(.borderedProminent)
                    }
                }
                .controlSize(.large)
                .tint(.accentColor)
                .disabled(!viewModel.canSave || isSaving)
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(.bar)
            }
        }
        .task {
            await accountStore.loadAccounts()
            viewModel.configureAccount(
                selectedAccountID: accountStore.selectedAccountID,
                lastUsedAccountID: UUID(uuidString: lastAccountID),
                accounts: accountStore.accounts
            )
            await transactionStore.loadCategories()
            viewModel.refreshCategoryResolution(categories: transactionStore.categories)
        }
        .onChange(of: transactionStore.categories) { _, categories in
            viewModel.refreshCategoryResolution(categories: categories)
        }
        .sheet(isPresented: $isPresentingNewCategory) {
            NewTransactionCategoryView(kind: viewModel.kind) { category in
                viewModel.selectCreatedCategory(category)
            }
            .environmentObject(transactionStore)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    private var accountSection: some View {
        Section("Account") {
            if accountStore.accounts.isEmpty {
                ContentUnavailableView(
                    "No accounts",
                    systemImage: "creditcard",
                    description: Text("Create an account before adding a transaction.")
                )
            } else {
                Picker("Account", selection: accountBinding) {
                    Text("Choose account")
                        .tag(UUID?.none)

                    ForEach(accountStore.accounts) { account in
                        Label(account.name, systemImage: account.icon)
                            .tag(Optional(account.id))
                    }
                }
                .pickerStyle(.navigationLink)
            }
        }
    }

    private var quickEntrySection: some View {
        Section {
            TextField(
                "12.50 coffee yesterday",
                text: commandBinding,
                axis: .vertical
            )
            .lineLimit(2...4)
            .textInputAutocapitalization(.never)
        } header: {
            Text("Quick entry")
        } footer: {
            Text("Use + before an amount for income. Dates and times are read from English text.")
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Amount", source: viewModel.amountSource)

                HStack {
                    TextField("0.00", text: amountBinding)
                        .keyboardType(.decimalPad)
                        .font(.body.monospacedDigit())

                    if let currency = selectedAccount?.currency {
                        Text(currency)
                            .foregroundStyle(.secondary)
                    }
                }

                if viewModel.amountConflict {
                    conflictLabel("More than one amount was found. Enter the amount below.")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Type", source: viewModel.kindSource)
                Picker("Type", selection: kindBinding) {
                    ForEach(TransactionKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Description", source: viewModel.descriptionSource)
                TextField("What was it for?", text: descriptionBinding, axis: .vertical)
                    .lineLimit(1...3)
            }

            LabeledContent {
                Menu {
                    Button("No category") {
                        viewModel.setCategoryID(nil)
                    }

                    ForEach(categoriesForKind) { category in
                        Button {
                            viewModel.setCategoryID(category.id)
                        } label: {
                            HStack {
                                Text(category.name)
                                if viewModel.categoryID == category.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }

                    Divider()

                    Button {
                        isPresentingNewCategory = true
                    } label: {
                        Label("New category", systemImage: "plus")
                    }
                } label: {
                    HStack(spacing: 5) {
                        if transactionStore.isLoadingCategories || viewModel.isResolvingCategory {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(selectedCategory?.name ?? "None")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                }
            } label: {
                fieldLabel("Category", source: viewModel.categorySource)
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Date and time", source: viewModel.dateSource)
                DatePicker(
                    "Date and time",
                    selection: dateBinding,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()

                if viewModel.dateConflict {
                    conflictLabel("Conflicting or invalid dates were found. Choose the date and time below.")
                }
            }

            TextField("Note", text: noteBinding, axis: .vertical)
                .lineLimit(1...4)
        }
    }

    private var submitButton: some View {
        Button {
            Task {
                await save()
            }
        } label: {
            HStack {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                }
                Text("Add transaction")
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var selectedAccount: Account? {
        accountStore.accounts.first { $0.id == viewModel.accountID }
    }

    private var categoriesForKind: [TransactionCategory] {
        transactionStore.categories(for: viewModel.kind)
    }

    private var selectedCategory: TransactionCategory? {
        transactionStore.categories.first { $0.id == viewModel.categoryID }
    }

    private var accountBinding: Binding<UUID?> {
        Binding(
            get: { viewModel.accountID },
            set: { accountID in
                viewModel.setAccountID(accountID)
                viewModel.setCommand(
                    viewModel.command,
                    categories: transactionStore.categories,
                    currencyCode: accountStore.accounts.first(where: { $0.id == accountID })?.currency
                )
            }
        )
    }

    private var commandBinding: Binding<String> {
        Binding(
            get: { viewModel.command },
            set: { command in
                viewModel.setCommand(
                    command,
                    categories: transactionStore.categories,
                    currencyCode: selectedAccount?.currency
                )
            }
        )
    }

    private var amountBinding: Binding<String> {
        Binding(
            get: { viewModel.amountText },
            set: viewModel.setAmountText
        )
    }

    private var kindBinding: Binding<TransactionKind> {
        Binding(
            get: { viewModel.kind },
            set: { kind in
                viewModel.setKind(kind, categories: transactionStore.categories)
            }
        )
    }

    private var descriptionBinding: Binding<String> {
        Binding(
            get: { viewModel.description },
            set: { description in
                viewModel.setDescription(
                    description,
                    categories: transactionStore.categories
                )
            }
        )
    }

    private var noteBinding: Binding<String> {
        Binding(get: { viewModel.note }, set: viewModel.setNote)
    }

    private var dateBinding: Binding<Date> {
        Binding(get: { viewModel.occurredAt }, set: viewModel.setOccurredAt)
    }

    @ViewBuilder
    private func fieldLabel(_ title: String, source: DraftFieldSource) -> some View {
        HStack(spacing: 6) {
            Text(title)
            if source.isSuggested {
                Text("Suggested")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.tint.opacity(0.12), in: Capsule())
            }
        }
    }

    private func conflictLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
    }

    private func save() async {
        guard
            let accountID = viewModel.accountID,
            let amount = viewModel.canonicalAmount()
        else {
            return
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await transactionStore.createTransaction(
                CreateTransactionRequest(
                    accountId: accountID,
                    kind: viewModel.kind,
                    amount: amount,
                    categoryId: viewModel.categoryID,
                    description: optionalText(viewModel.description),
                    note: optionalText(viewModel.note),
                    occurredAt: viewModel.occurredAt
                )
            )
            lastAccountID = accountID.uuidString
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func optionalText(_ value: String) -> String? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}

private struct NewTransactionCategoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var transactionStore: TransactionStore

    let kind: TransactionKind
    let onCreated: (TransactionCategory) -> Void

    @State private var name = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    TextField("Name", text: $name)
                    LabeledContent("Type", value: kind.title)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New category")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            await create()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
    }

    private func create() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let category = try await transactionStore.createCategory(name: name, kind: kind)
            onCreated(category)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    AddTransactionView()
        .environmentObject(AccountStore())
        .environmentObject(TransactionStore())
}
