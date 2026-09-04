import SwiftUI

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore
    @AppStorage("lastTransactionAccountID") private var lastAccountID = ""

    let transaction: FinanceTransaction?
    let upcomingTransaction: UpcomingTransaction?
    let quickEntryDraft: QuickEntryDraft?
    let initialCommand: String?
    let initialAccountID: UUID?
    let onSaveDraft: ((QuickEntryDraft) -> Void)?

    @StateObject private var viewModel: AddTransactionViewModel
    @State private var navigationPath = NavigationPath()
    @State private var mode = QuickTransactionMode.expense
    @State private var amountExpression = AmountExpression()
    @State private var destinationAccountID: UUID?
    @State private var expandedCategoryID: UUID?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didApplyInitialCommand = false

    init(
        transaction: FinanceTransaction? = nil,
        upcomingTransaction: UpcomingTransaction? = nil,
        draft: QuickEntryDraft? = nil,
        initialCommand: String? = nil,
        initialAccountID: UUID? = nil,
        onSaveDraft: ((QuickEntryDraft) -> Void)? = nil
    ) {
        self.transaction = transaction
        self.upcomingTransaction = upcomingTransaction
        quickEntryDraft = draft
        self.initialCommand = initialCommand
        self.initialAccountID = initialAccountID
        self.onSaveDraft = onSaveDraft
        let original: (any EditableTransaction)?
        if let draft {
            original = draft
        } else if let upcomingTransaction {
            original = upcomingTransaction
        } else {
            original = transaction
        }
        _viewModel = StateObject(wrappedValue: AddTransactionViewModel(transaction: original))
        _mode = State(
            initialValue: draft?.mode ?? original.map(QuickTransactionMode.init) ?? .expense
        )
        _amountExpression = State(
            initialValue: AmountExpression(rawValue: original?.amount ?? "")
        )
        _destinationAccountID = State(initialValue: draft?.destinationAccountId)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            manualEntryContent
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                        .disabled(isSaving)
                    }
                }
                .interactiveDismissDisabled(isSaving)
                .navigationDestination(for: AddTransactionRoute.self) { route in
                    switch route {
                    case .categoryPicker:
                        CategoryPickerView(
                            selection: categoryBinding,
                            kind: viewModel.kind,
                            onSelect: selectCategory
                        )
                    case .details:
                        QuickTransactionDetailsView(
                            merchant: merchantBinding,
                            payee: payeeBinding,
                            note: noteBinding,
                            supportsRecurrence: mode != .transfer,
                            isRecurring: recurringBinding,
                            frequency: recurrenceFrequencyBinding,
                            hasEndDate: hasRecurrenceEndDateBinding,
                            endDate: recurrenceEndDateBinding
                        )
                    }
                }
        }
        .task {
            await accountStore.loadAccounts()
            viewModel.configureAccount(
                selectedAccountID: initialAccountID ?? accountStore.selectedAccountID,
                lastUsedAccountID: UUID(uuidString: lastAccountID),
                accounts: accountStore.accounts
            )
            chooseDestinationIfNeeded()
            await transactionStore.loadCategories()
            applyInitialCommandIfNeeded()
        }
        .alert(errorAlertTitle, isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Try again.")
        }
    }

    private var manualEntryContent: some View {
        VStack(spacing: 0) {
            if !isLockedTransferDraft {
                TransactionModeSelector(modes: availableModes, selection: $mode)
                    .onChange(of: mode) { _, newMode in
                        handleModeChange(newMode)
                    }
            }
            TransactionAmountPanel(expression: amountExpression, formattedAmount: displayAmount)
            TransactionMetadataBar(
                accounts: accountStore.accounts,
                selectedAccountID: viewModel.accountID,
                date: dateBinding,
                hasExtraDetails: hasExtraDetails
            ) { accountID in
                accountBinding.wrappedValue = accountID
                if mode == .transfer {
                    chooseDestinationIfNeeded()
                }
            }
            TransactionClassificationSelector(
                mode: mode,
                destinationItems: destinationAccountCarouselItems,
                destinationSelection: $destinationAccountID,
                categoryItems: categoryCarouselItems,
                expandedCategoryID: expandedCategoryID,
                expandedCategoryItems: expandedCategory.map(subcategoryCarouselItems),
                categorySelection: categoryCarouselBinding
            )
            TransactionKeypad { key in
                amountExpression.enter(key)
                viewModel.setAmountText(amountExpression.canonicalResult ?? "")
            }
            submitButton
        }
        .padding(.horizontal, AppSpacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.clear)
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var navigationTitle: String {
        if quickEntryDraft != nil { return "Edit draft" }
        if upcomingTransaction != nil { return "Edit recurring transaction" }
        if transaction != nil { return "Edit transaction" }
        return initialCommand == nil ? "New transaction" : "Review transaction"
    }

    private func applyInitialCommandIfNeeded() {
        guard
            !didApplyInitialCommand,
            !isEditing,
            let initialCommand,
            !initialCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        didApplyInitialCommand = true
        viewModel.setCommand(
            initialCommand,
            categories: transactionStore.categories,
            currencyCode: selectedAccount?.currency
        )
        mode = viewModel.kind == .income ? .income : .expense
        amountExpression = AmountExpression(rawValue: viewModel.amountText)
    }

    private var availableModes: [QuickTransactionMode] {
        if quickEntryDraft != nil {
            return accountStore.accounts.count > 1 ? QuickTransactionMode.allCases : [.expense, .income]
        }
        guard !isEditing else { return [.expense, .income] }
        return accountStore.accounts.count > 1 ? QuickTransactionMode.allCases : [.expense, .income]
    }

    private var isLockedTransferDraft: Bool {
        quickEntryDraft?.mode == .transfer
    }

    private var submitButton: some View {
        PrimaryActionButton(submitButtonTitle, isLoading: isSaving) {
            Task { await save() }
        }
        .disabled(isSubmitDisabled)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .padding(.horizontal, 10)
    }

    private var submitButtonTitle: String {
        if isEditing {
            return "Save changes"
        }
        return mode == .transfer ? "Transfer" : "Add transaction"
    }

    private var isSubmitDisabled: Bool {
        if let quickEntryDraft {
            return isSaving || !hasDraftChanges(from: quickEntryDraft)
        }
        return isSaving || originalTransaction.map { !viewModel.hasChanges(from: $0) } == true
    }

    private var isEditing: Bool { originalTransaction != nil }

    private var originalTransaction: (any EditableTransaction)? {
        if let quickEntryDraft { return quickEntryDraft }
        if let upcomingTransaction { return upcomingTransaction }
        return transaction
    }

    private var errorAlertTitle: String {
        if quickEntryDraft != nil { return "Couldn’t save draft" }
        return isEditing ? "Couldn’t save transaction" : "Couldn’t add transaction"
    }

    private var selectedAccount: Account? {
        accountStore.accounts.first { $0.id == viewModel.accountID }
    }

    private var destinationAccount: Account? {
        accountStore.accounts.first { $0.id == destinationAccountID }
    }

    private var destinationAccounts: [Account] {
        accountStore.accounts.filter { $0.id != viewModel.accountID }
    }

    private var destinationAccountCarouselItems: [CenteredSelectionCarouselItem<UUID>] {
        destinationAccounts.map { account in
            CenteredSelectionCarouselItem(
                id: account.id,
                title: account.name,
                iconName: account.icon,
                color: account.iconColor.color,
                accessibilityLabel: "Transfer to \(account.name)"
            )
        }
    }

    private var visibleCategories: [TransactionCategory] {
        let roots = transactionStore.rootCategories(for: viewModel.kind)
        guard let selected = transactionStore.categories.first(where: { $0.id == viewModel.categoryID }),
              !roots.contains(selected) else {
            return roots
        }
        return [selected] + roots
    }

    private var expandedCategory: TransactionCategory? {
        guard let expandedCategoryID,
              let category = transactionStore.categories.first(where: { $0.id == expandedCategoryID }),
              category.parentId == nil,
              !transactionStore.subcategories(of: category).isEmpty else {
            return nil
        }
        return category
    }

    private var categoryCarouselItems: [CenteredSelectionCarouselItem<QuickCategoryCarouselID>] {
        let all = CenteredSelectionCarouselItem(
            id: QuickCategoryCarouselID.all,
            title: "All",
            iconName: "view-grid",
            color: Color.primary,
            accessibilityLabel: "All categories",
            action: {
                navigationPath.append(AddTransactionRoute.categoryPicker)
            }
        )
        let uncategorized = CenteredSelectionCarouselItem(
            id: QuickCategoryCarouselID.uncategorized,
            title: "Uncategorized",
            iconName: "prohibition",
            color: Color.gray
        )
        let categories = visibleCategories.map { category in
            let hasSubcategories = !transactionStore.subcategories(of: category).isEmpty

            return CenteredSelectionCarouselItem(
                id: QuickCategoryCarouselID.category(category.id),
                title: category.name,
                iconName: category.displayIcon,
                color: category.displayColor,
                accessibilityLabel: hasSubcategories
                    ? "\(category.name), has subcategories. Select again to show them."
                    : category.name,
                selectedAccessoryIcon: hasSubcategories ? "nav-arrow-down" : nil,
                selectedAction: hasSubcategories ? {
                    expandSubcategories(for: category)
                } : nil
            )
        }
        return [all, uncategorized] + categories
    }

    private func subcategoryCarouselItems(
        for parent: TransactionCategory
    ) -> [CenteredSelectionCarouselItem<QuickCategoryCarouselID>] {
        let collapse = CenteredSelectionCarouselItem(
            id: QuickCategoryCarouselID.category(parent.id),
            title: parent.name,
            iconName: "nav-arrow-down",
            color: parent.displayColor,
            accessibilityLabel: "Use \(parent.name) and close subcategories",
            tapAction: {
                collapseSubcategories(to: parent)
            }
        )
        let subcategories = transactionStore.subcategories(of: parent).map { category in
            CenteredSelectionCarouselItem(
                id: QuickCategoryCarouselID.category(category.id),
                title: category.name,
                iconName: category.displayIcon,
                color: category.displayColor,
                accessibilityLabel: "\(parent.name), \(category.name)"
            )
        }
        return [collapse] + subcategories
    }

    private var displayAmount: String {
        let value = amountExpression.result ?? .zero
        guard let currency = selectedAccount?.currency else { return MoneyFormatter.number(value) }
        return MoneyFormatter.format(value, currency: currency)
    }

    private var hasExtraDetails: Bool {
        !viewModel.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !viewModel.payee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !viewModel.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            viewModel.isRecurring
    }

    private var categoryBinding: Binding<UUID?> {
        Binding(get: { viewModel.categoryID }, set: viewModel.setCategoryID)
    }

    private var categoryCarouselBinding: Binding<QuickCategoryCarouselID?> {
        Binding(
            get: {
                viewModel.categoryID.map(QuickCategoryCarouselID.category)
                    ?? .uncategorized
            },
            set: { selection in
                switch selection {
                case .all:
                    break
                case .uncategorized:
                    viewModel.setCategoryID(nil)
                case let .category(categoryID):
                    viewModel.setCategoryID(categoryID)
                case nil:
                    break
                }
            }
        )
    }

    private var accountBinding: Binding<UUID?> {
        Binding(
            get: { viewModel.accountID },
            set: { accountID in
                viewModel.setAccountID(accountID)
                if destinationAccountID == accountID {
                    destinationAccountID = nil
                }
            }
        )
    }

    private var dateBinding: Binding<Date> {
        Binding(get: { viewModel.occurredAt }, set: viewModel.setOccurredAt)
    }

    private var merchantBinding: Binding<String> {
        Binding(get: { viewModel.merchant }, set: viewModel.setMerchant)
    }

    private var payeeBinding: Binding<String> {
        Binding(get: { viewModel.payee }, set: viewModel.setPayee)
    }

    private var noteBinding: Binding<String> {
        Binding(get: { viewModel.note }, set: viewModel.setNote)
    }

    private var recurringBinding: Binding<Bool> {
        Binding(get: { viewModel.isRecurring }, set: viewModel.setRecurring)
    }

    private var recurrenceFrequencyBinding: Binding<RecurrenceFrequency> {
        Binding(
            get: { viewModel.recurrenceFrequency },
            set: viewModel.setRecurrenceFrequency
        )
    }

    private var hasRecurrenceEndDateBinding: Binding<Bool> {
        Binding(
            get: { viewModel.recurrenceEndAt != nil },
            set: { hasEndDate in
                viewModel.setRecurrenceEndAt(
                    hasEndDate ? defaultRecurrenceEndDate : nil
                )
            }
        )
    }

    private var recurrenceEndDateBinding: Binding<Date> {
        Binding(
            get: { viewModel.recurrenceEndAt ?? defaultRecurrenceEndDate },
            set: { viewModel.setRecurrenceEndAt($0) }
        )
    }

    private var defaultRecurrenceEndDate: Date {
        Calendar.current.date(
            byAdding: .month,
            value: 1,
            to: max(viewModel.occurredAt, Date.now)
        ) ?? viewModel.occurredAt
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func selectCategory(_ categoryID: UUID?) {
        viewModel.setCategoryID(categoryID)
        expandedCategoryID = nil
        navigationPath = NavigationPath()
    }

    private func expandSubcategories(for category: TransactionCategory) {
        guard !transactionStore.subcategories(of: category).isEmpty else { return }
        viewModel.setCategoryID(category.id)
        withAnimation(.snappy(duration: 0.3)) {
            expandedCategoryID = category.id
        }
    }

    private func collapseSubcategories(to parent: TransactionCategory) {
        viewModel.setCategoryID(parent.id)
        withAnimation(.snappy(duration: 0.3)) {
            expandedCategoryID = nil
        }
    }

    private func chooseDestinationIfNeeded() {
        if destinationAccountID == viewModel.accountID ||
            !accountStore.accounts.contains(where: { $0.id == destinationAccountID }) {
            destinationAccountID = accountStore.accounts.first { $0.id != viewModel.accountID }?.id
        }
    }

    private func handleModeChange(_ newMode: QuickTransactionMode) {
        withAnimation(.snappy(duration: 0.1)) {
            expandedCategoryID = nil
        }
        switch newMode {
        case .expense:
            viewModel.setKind(.expense, categories: transactionStore.categories)
        case .income:
            viewModel.setKind(.income, categories: transactionStore.categories)
        case .transfer:
            viewModel.setCategoryID(nil)
            viewModel.setRecurring(false)
            chooseDestinationIfNeeded()
        }
    }

    private func hasDraftChanges(from draft: QuickEntryDraft) -> Bool {
        mode != draft.mode ||
            (mode == .transfer && destinationAccountID != draft.destinationAccountId) ||
            viewModel.hasChanges(from: draft)
    }

    private func save() async {
        guard let accountID = viewModel.accountID else {
            errorMessage = "Choose an account."
            return
        }
        guard let amount = amountExpression.canonicalResult else {
            errorMessage = "Enter an amount greater than zero."
            return
        }
        if mode == .transfer {
            guard let destinationAccountID, destinationAccountID != accountID else {
                errorMessage = "Choose a different destination account."
                return
            }
            guard selectedAccount?.currency == destinationAccount?.currency else {
                errorMessage = "Transfers currently require accounts with the same currency."
                return
            }
        } else if let endAt = viewModel.recurrenceEndAt,
                  viewModel.isRecurring,
                  endAt < viewModel.occurredAt {
            errorMessage = "The recurrence end date must be on or after the transaction date."
            return
        }

        if let quickEntryDraft {
            onSaveDraft?(updatedDraft(from: quickEntryDraft, amount: amount, accountID: accountID))
            dismiss()
            return
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            if mode == .transfer, let destinationAccountID {
                try await saveTransfer(
                    from: accountID,
                    to: destinationAccountID,
                    amount: amount
                )
            } else {
                let request = transactionRequest(
                    accountID: accountID,
                    kind: viewModel.kind,
                    amount: amount,
                    categoryID: viewModel.categoryID
                )
                if let upcomingTransaction {
                    try await transactionStore.updateRecurringTransaction(upcomingTransaction, with: request)
                } else if let transaction {
                    try await transactionStore.updateTransaction(id: transaction.id, with: request)
                } else {
                    try await transactionStore.createTransaction(request)
                }
            }
            lastAccountID = accountID.uuidString
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updatedDraft(
        from draft: QuickEntryDraft,
        amount: String,
        accountID: UUID
    ) -> QuickEntryDraft {
        let originalAmount = Decimal(
            string: draft.amount.replacingOccurrences(of: ",", with: "."),
            locale: Locale(identifier: "en_US_POSIX")
        )
        let updatedAmount = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX"))
        let amountChanged = updatedAmount != originalAmount

        var updated = draft
        updated.mode = mode
        updated.accountId = accountID
        updated.destinationAccountId = mode == .transfer ? destinationAccountID : nil
        updated.amount = amountChanged ? amount : draft.amount
        updated.currency = selectedAccount?.currency ?? draft.currency
        if mode == .transfer {
            updated.category = nil
        } else if viewModel.categoryID == draft.category?.id {
            updated.category = draft.category
        } else {
            updated.category = transactionStore.categories.first { $0.id == viewModel.categoryID }
        }
        updated.merchant = optionalText(viewModel.merchant)
        updated.payee = optionalText(viewModel.payee)
        updated.note = optionalText(viewModel.note)
        updated.occurredAt = viewModel.occurredAt
        updated.isRecurring = mode != .transfer && viewModel.isRecurring
        updated.recurrenceFrequency = viewModel.recurrenceFrequency
        updated.recurrenceEndAt = updated.isRecurring ? viewModel.recurrenceEndAt : nil

        if mode != draft.mode || accountID != draft.accountId || amountChanged {
            updated.conversion = nil
        }
        return updated
    }

    private func saveTransfer(from sourceID: UUID, to destinationID: UUID, amount: String) async throws {
        try await transactionStore.createTransfer(
            TransferRequest(
                fromAccountId: sourceID,
                toAccountId: destinationID,
                amount: amount,
                merchant: optionalText(viewModel.merchant),
                payee: optionalText(viewModel.payee),
                note: optionalText(viewModel.note),
                occurredAt: viewModel.occurredAt
            )
        )
    }

    private func transactionRequest(
        accountID: UUID,
        kind: TransactionKind,
        amount: String,
        categoryID: UUID?
    ) -> TransactionRequest {
        TransactionRequest(
            accountId: accountID,
            kind: kind,
            amount: amount,
            categoryId: categoryID,
            merchant: optionalText(viewModel.merchant),
            payee: optionalText(viewModel.payee),
            note: optionalText(viewModel.note),
            occurredAt: viewModel.occurredAt,
            recurrence: viewModel.isRecurring
                ? RecurrenceRequest(
                    frequency: viewModel.recurrenceFrequency,
                    endAt: viewModel.recurrenceEndAt
                )
                : nil
        )
    }

    private func optionalText(_ value: String) -> String? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}
