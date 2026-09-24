import SwiftUI

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore
    @AppStorage("lastTransactionAccountID") private var lastAccountID = ""
    @AppStorage(AppPreferences.roundTotalsKey) private var roundTotals = false

    let transaction: FinanceTransaction?
    let upcomingTransaction: UpcomingTransaction?
    let quickEntryDraft: QuickEntryDraft?
    let isCSVImport: Bool
    let initialCommand: String?
    let initialAccountID: UUID?
    let onSaveDraft: ((QuickEntryDraft) -> Void)?
    let onBottomActionBarHeightChange: (CGFloat) -> Void
    private let initialKind: TransactionKind
    private let initialRecurring: Bool

    @StateObject private var viewModel: AddTransactionViewModel
    @StateObject private var exchangeRateStore = ExchangeRateStore()
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
        initialKind: TransactionKind = .expense,
        initialRecurring: Bool = false,
        isCSVImport: Bool = false,
        onBottomActionBarHeightChange: @escaping (CGFloat) -> Void = { _ in },
        onSaveDraft: ((QuickEntryDraft) -> Void)? = nil
    ) {
        self.transaction = transaction
        self.upcomingTransaction = upcomingTransaction
        quickEntryDraft = draft
        self.isCSVImport = isCSVImport
        self.initialCommand = initialCommand
        self.initialAccountID = initialAccountID
        self.onSaveDraft = onSaveDraft
        self.onBottomActionBarHeightChange = onBottomActionBarHeightChange
        self.initialKind = initialKind
        self.initialRecurring = initialRecurring
        let original: (any EditableTransaction)?
        if let draft {
            original = draft
        } else if let upcomingTransaction {
            original = upcomingTransaction
        } else {
            original = transaction
        }
        let model = AddTransactionViewModel(transaction: original)
        if isCSVImport, let draft { model.setCurrency(draft.currency) }
        if original == nil, initialKind != .expense { model.setKind(initialKind, categories: []) }
        if original == nil, initialRecurring { model.setRecurring(true) }
        _viewModel = StateObject(wrappedValue: model)
        _mode = State(
            initialValue: draft?.mode ?? original.map(QuickTransactionMode.init) ?? (initialKind == .debt ? .debt : initialKind == .income ? .income : .expense)
        )
        _amountExpression = State(
            initialValue: AmountExpression(rawValue: original?.amount ?? "")
        )
        _destinationAccountID = State(initialValue: draft?.destinationAccountId)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            manualEntryContent
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if #available(iOS 26.0, *) {
                        ToolbarItem(placement: .cancellationAction) {
                            closeButton
                        }
                        .sharedBackgroundVisibility(.hidden)
                        ToolbarItem(placement: .principal) {
                            transactionModeSelector
                        }
                        .sharedBackgroundVisibility(.hidden)
                    } else {
                        ToolbarItem(placement: .cancellationAction) {
                            closeButton
                        }
                        ToolbarItem(placement: .principal) {
                            transactionModeSelector
                        }
                    }
                }
                .interactiveDismissDisabled(isSaving)
                .navigationDestination(for: AddTransactionRoute.self) { route in
                    Group {
                        switch route {
                        case .categoryPicker:
                            CategoryPickerView(
                                selection: categoryBinding,
                                kind: viewModel.kind,
                                onSelect: selectCategory
                            )
                        case .details:
                            QuickTransactionDetailsView(
                                counterparty: counterpartyBinding,
                                note: noteBinding,
                                supportsRecurrence: !isCSVImport && mode != .transfer && mode != .debt,
                                isRecurring: recurringBinding,
                                frequency: recurrenceFrequencyBinding,
                                hasEndDate: hasRecurrenceEndDateBinding,
                                endDate: recurrenceEndDateBinding,
                                currency: transaction != nil || upcomingTransaction != nil ? currencyBinding : nil
                            )
                        }
                    }.legacyNavigationDestination()
                }
        }
        .onChange(of: mode) { _, newMode in
            handleModeChange(newMode)
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
            await transactionStore.loadDebts()
            applyInitialCommandIfNeeded()
        }
        .task(id: accountBalanceScopeKey) {
            guard !isCSVImport, let selectedAccount else { return }
            await exchangeRateStore.load(currencies: accountCurrencies, reportingCurrency: selectedAccount.currency)
        }
        .alert(errorAlertTitle, isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Try again.")
        }
    }

    @ViewBuilder
    private var transactionModeSelector: some View {
        if canChangeMode {
            TransactionModeSelector(modes: availableModes, selection: $mode)
                .disabled(isSaving)
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            AppIcon("xmark", size: AppControlSize.iconButtonGlyph)
                .foregroundStyle(.primary)
                .frame(width: AppControlSize.minimumTapTarget, height: AppControlSize.minimumTapTarget)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modifier(TransactionGlassSurface(shape: Circle(), isToolbarControl: true))
        .accessibilityLabel("Close")
        .disabled(isSaving)
    }

    private var manualEntryContent: some View {
        GeometryReader { geometry in
            ScrollView {
                entryControls
                    .frame(minHeight: geometry.size.height)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .scrollEdgeFades(background: AppColor.sheetBackground)
        .background(AppColor.sheetBackground.ignoresSafeArea())
        .disabled(isSaving)
    }

    private var entryControls: some View {
        VStack(spacing: AppSpacing.medium) {
            TransactionAmountPanel(expression: amountExpression, formattedAmount: displayAmount)
                .modifier(TransactionModeSwipe(modes: availableModes, selection: $mode, isActive: canChangeMode))
            TransactionMetadataBar(
                accounts: accountStore.accounts,
                selectedAccountID: viewModel.accountID,
                accountBalance: accountBalanceSubtitle,
                date: dateBinding,
                hasExtraDetails: hasExtraDetails
            ) { accountID in
                accountBinding.wrappedValue = accountID
                if mode == .transfer {
                    chooseDestinationIfNeeded()
                }
            }
            classificationSelector
            TransactionKeypad(onClear: clearAmount) { key in
                amountExpression.enter(key)
                viewModel.setAmountText(amountExpression.canonicalResult ?? "")
            }
            submitButton
                .reportScanDraftBottomBarHeight {
                    onBottomActionBarHeightChange($0 + AppSpacing.small)
                }
        }
        .padding(.horizontal, AppSpacing.large)
        .padding(.vertical, AppSpacing.small)
        .frame(maxWidth: .infinity)
        .background(.clear)
    }

    private var classificationSelector: some View {
        Group {
            if mode == .debt {
                DebtRecipientPicker(selection: Binding(get: { viewModel.debtID }, set: viewModel.setDebtID))
            } else {
                TransactionClassificationSelector(
                    mode: mode,
                    destinationItems: destinationAccountCarouselItems,
                    destinationSelection: $destinationAccountID,
                    categoryItems: categoryCarouselItems,
                    expandedCategoryID: expandedCategoryID,
                    expandedCategoryItems: expandedCategory.map(subcategoryCarouselItems),
                    categorySelection: categoryCarouselBinding
                )
            }
        }
        .padding(.vertical, AppSpacing.small)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.extraLarge))
        .background {
            Color.clear
                .modifier(TransactionGlassSurface(shape: RoundedRectangle(cornerRadius: AppRadius.extraLarge)))
        }
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

    private func clearAmount() {
        amountExpression.clear()
        viewModel.setAmountText("")
    }

    private var availableModes: [QuickTransactionMode] {
        if isCSVImport { return [.income, .expense, .debt] }
        if quickEntryDraft != nil {
            return accountStore.accounts.count > 1 ? [.income, .expense, .transfer] : [.income, .expense]
        }
        if upcomingTransaction != nil || transaction?.recurrence != nil { return [.income, .expense] }
        if isEditing { return [.income, .expense, .debt] }
        if initialRecurring { return [.income, .expense] }
        if initialKind == .debt { return [.debt] }
        return accountStore.accounts.count > 1 ? QuickTransactionMode.allCases : [.income, .expense, .debt]
    }

    private var canChangeMode: Bool {
        availableModes.count > 1
    }

    private var submitButton: some View {
        PrimaryActionButton(submitButtonTitle, appearance: .glass) {
            Task { await save() }
        }
        .controlSize(.large)
        .disabled(isSubmitDisabled)
        .padding(.top, AppSpacing.extraSmall)
    }

    private var submitButtonTitle: String {
        if isEditing {
            return "Save changes"
        }
        return mode == .transfer ? "Transfer" : "Add transaction"
    }

    private var isSubmitDisabled: Bool {
        if hasZeroAmount { return isSaving }
        if mode == .debt && !viewModel.canSave { return true }
        if let quickEntryDraft {
            return isSaving || !hasDraftChanges(from: quickEntryDraft)
        }
        return isSaving || originalTransaction.map { !viewModel.hasChanges(from: $0) } == true
    }

    private var hasZeroAmount: Bool {
        amountExpression.rawValue.isEmpty || amountExpression.result == 0
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

    private var accountBalanceSubtitle: String {
        guard let selectedAccount else { return "Choose account" }
        if let balance = transactionStore.balance(
            accountID: selectedAccount.id,
            currency: selectedAccount.currency,
            rates: exchangeRateStore.snapshot
        ) {
            return MoneyFormatter.format(balance, currency: selectedAccount.currency, roundToWhole: roundTotals)
        }
        return "Balance unavailable"
    }

    private var accountCurrencies: Set<String> {
        let stored = Set(transactionStore.allTransactions.lazy
            .filter { $0.accountId == viewModel.accountID }
            .map(\.currency))
        guard let draft = quickEntryDraft else { return stored }
        return stored.union(accountStore.accounts.map(\.currency)).union([draft.currency])
    }

    private var accountBalanceScopeKey: String {
        "\(selectedAccount?.currency ?? ""):\(accountCurrencies.sorted().joined(separator: ","))"
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
        guard let currency = viewModel.currency(for: selectedAccount) else { return MoneyFormatter.number(value) }
        return MoneyFormatter.format(value, currency: currency)
    }

    private var currencyBinding: Binding<String> {
        Binding(
            get: { viewModel.currency(for: selectedAccount) ?? AppPreferences.initialCurrency },
            set: viewModel.setCurrency
        )
    }

    private var hasExtraDetails: Bool {
        !viewModel.counterparty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
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
                let savedCurrency = viewModel.currency(for: selectedAccount)
                if quickEntryDraft != nil, !isCSVImport,
                   let sourceCurrency = viewModel.currency(for: selectedAccount),
                   let target = accountStore.accounts.first(where: { $0.id == accountID }),
                   sourceCurrency != target.currency,
                   let currentAmount = amountExpression.result, currentAmount != 0 {
                    guard let converted = exchangeRateStore.convert(currentAmount, from: sourceCurrency, to: target.currency) else {
                        errorMessage = "Exchange rates are unavailable. Try changing the account when rates are available."
                        return
                    }
                    var value = converted
                    var rounded = Decimal()
                    NSDecimalRound(&rounded, &value, 4, .plain)
                    let amount = NSDecimalNumber(decimal: rounded).stringValue
                    amountExpression = AmountExpression(rawValue: amount)
                    viewModel.setAmountText(amount)
                }
                viewModel.setAccountID(accountID)
                if isCSVImport, let savedCurrency { viewModel.setCurrency(savedCurrency) }
                if quickEntryDraft != nil, !isCSVImport, let target = selectedAccount { viewModel.setCurrency(target.currency) }
                if destinationAccountID == accountID {
                    destinationAccountID = nil
                }
            }
        )
    }

    private var dateBinding: Binding<Date> {
        Binding(get: { viewModel.occurredAt }, set: viewModel.setOccurredAt)
    }

    private var counterpartyBinding: Binding<String> {
        Binding(get: { viewModel.counterparty }, set: viewModel.setCounterparty)
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
        case .debt:
            viewModel.setKind(.debt, categories: transactionStore.categories)
        case .transfer:
            viewModel.setKind(.expense, categories: transactionStore.categories)
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
        guard !isSaving else { return }
        if hasZeroAmount {
            dismiss()
            return
        }
        guard let accountID = viewModel.accountID else {
            errorMessage = "Choose an account."
            return
        }
        guard let amount = amountExpression.canonicalResult,
              let decimalAmount = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")), decimalAmount != 0 else {
            errorMessage = "Enter a non-zero amount."
            return
        }
        if mode == .debt && viewModel.debtID == nil {
            errorMessage = "Choose a debt recipient."
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
            guard viewModel.currency(for: selectedAccount) == selectedAccount?.currency else {
                errorMessage = "Select the source account again to convert this draft before transferring."
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
        updated.debt = mode == .debt ? transactionStore.debts.first { $0.id == viewModel.debtID } : nil
        updated.amount = amountChanged ? amount : draft.amount
        updated.currency = viewModel.currency(for: selectedAccount) ?? draft.currency
        if mode == .transfer {
            updated.category = nil
        } else if viewModel.categoryID == draft.category?.id {
            updated.category = draft.category
        } else {
            updated.category = transactionStore.categories.first { $0.id == viewModel.categoryID }
        }
        updated.counterparty = viewModel.counterparty.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.note = optionalText(viewModel.note)
        updated.occurredAt = viewModel.occurredAt
        updated.isRecurring = !isCSVImport && mode != .transfer && mode != .debt && viewModel.isRecurring
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
                note: optionalText(viewModel.note),
                occurredAt: viewModel.occurredAt,
                counterparty: viewModel.counterparty
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
            note: optionalText(viewModel.note),
            occurredAt: viewModel.occurredAt,
            debtId: kind == .debt ? viewModel.debtID : nil,
            recurrence: viewModel.isRecurring
                ? RecurrenceRequest(
                    frequency: viewModel.recurrenceFrequency,
                    endAt: viewModel.recurrenceEndAt
                )
                : nil,
            currency: transaction != nil || upcomingTransaction != nil ? viewModel.currency(for: selectedAccount) : nil,
            counterparty: viewModel.counterparty
        )
    }

    private func optionalText(_ value: String) -> String? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}
