import SwiftUI

private enum QuickTransactionMode: String, CaseIterable, Identifiable {
    case income
    case expense
    case transfer

    var id: Self { self }

    init(_ transaction: FinanceTransaction) {
        self = transaction.kind == .income ? .income : .expense
    }

    var title: String {
        rawValue.capitalized
    }

    var systemImage: String {
        switch self {
        case .expense: "arrow.up.right.circle.fill"
        case .income: "arrow.down.left.circle.fill"
        case .transfer: "arrow.left.arrow.right.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .expense: Color(uiColor: .systemOrange)
        case .income: Color(uiColor: .systemGreen)
        case .transfer: Color(uiColor: .systemBlue)
        }
    }
}

private enum QuickCategoryCarouselID: Hashable {
    case all
    case uncategorized
    case category(UUID)
}

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore
    @AppStorage("lastTransactionAccountID") private var lastAccountID = ""

    let transaction: FinanceTransaction?
    let initialCommand: String?
    let initialAccountID: UUID?

    @StateObject private var viewModel: AddTransactionViewModel
    @State private var navigationPath = NavigationPath()
    @State private var mode = QuickTransactionMode.expense
    @State private var amountExpression = AmountExpression()
    @State private var destinationAccountID: UUID?
    @State private var expandedCategoryID: UUID?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didApplyInitialCommand = false

    private let keypadColumns = Array(repeating: GridItem(.flexible(), spacing: 9), count: 4)
    private let keypadRows = [
        ["1", "2", "3", "+"],
        ["4", "5", "6", "-"],
        ["7", "8", "9", "*"],
        [",", "0", "⌫", "/"],
    ]

    init(
        transaction: FinanceTransaction? = nil,
        initialCommand: String? = nil,
        initialAccountID: UUID? = nil
    ) {
        self.transaction = transaction
        self.initialCommand = initialCommand
        self.initialAccountID = initialAccountID
        _viewModel = StateObject(wrappedValue: AddTransactionViewModel(transaction: transaction))
        _mode = State(initialValue: transaction.map(QuickTransactionMode.init) ?? .expense)
        _amountExpression = State(
            initialValue: AmountExpression(
                rawValue: transaction?.amount ?? "",
                replacesInitialValue: transaction != nil
            )
        )
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
        .alert(transaction == nil ? "Couldn’t add transaction" : "Couldn’t save transaction", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Try again.")
        }
    }

    private var manualEntryContent: some View {
        VStack(spacing: 0) {
            typeSelector
            amountPanel
            metadataRow
            categorySelector
            keypad
            submitButton
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.clear)
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private var navigationTitle: String {
        if transaction != nil { return "Edit transaction" }
        return initialCommand == nil ? "New transaction" : "Review transaction"
    }

    private func applyInitialCommandIfNeeded() {
        guard
            !didApplyInitialCommand,
            transaction == nil,
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

    private var typeSelector: some View {
        HStack(spacing: 2) {
            ForEach(availableModes) { mode in
                transactionModeButton(mode)
            }
        }
        .padding(3)
        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
        .animation(.snappy(duration: 0.1), value: mode)
        .onChange(of: mode) { _, newMode in
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
                chooseDestinationIfNeeded()
            }
        }
    }

    private var availableModes: [QuickTransactionMode] {
        guard transaction == nil else { return [.expense, .income] }
        return accountStore.accounts.count > 1 ? QuickTransactionMode.allCases : [.expense, .income]
    }

    private func transactionModeButton(_ option: QuickTransactionMode) -> some View {
        let isSelected = mode == option

        return Button {
            mode = option
        } label: {
            HStack(spacing: 6) {
                Image(systemName: option.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? option.color : .primary)
                    .accessibilityHidden(true)

                Text(option.title)
                    .foregroundStyle(isSelected ? option.color : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .frame(maxWidth: .infinity, minHeight: 42)
            .background {
                if isSelected {
                    Capsule()
                        .fill(option.color.opacity(0.15))
                        .shadow(color: option.color.opacity(0.18), radius: 2, y: 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var amountPanel: some View {
        VStack(spacing: 5) {
            if amountExpression.rawValue.contains(where: { "+-*/".contains($0) }) {
                Text(amountExpression.displayValue)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("Amount")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(displayAmount)
                    .font(.system(size: 48, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .contentTransition(.numericText(value: amountAnimationValue))
                    .animation(.snappy(duration: 0.24), value: amountAnimationValue)

                if let currency = selectedAccount?.currency {
                    Text(currency)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 98, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(amountAccessibilityLabel)
    }

    private var metadataRow: some View {
        HStack(spacing: 8) {
            QuickAccountMenu(
                accounts: accountStore.accounts,
                selectedAccountID: viewModel.accountID
            ) { accountID in
                accountBinding.wrappedValue = accountID
                if mode == .transfer {
                    chooseDestinationIfNeeded()
                }
            }

            DatePicker(
                "Date and time",
                selection: dateBinding,
                displayedComponents: [.date, .hourAndMinute]
            )
            .labelsHidden()
            .fixedSize()

            NavigationLink(value: AddTransactionRoute.details) {
                Image(systemName: hasExtraDetails ? "text.badge.checkmark" : "text.badge.plus")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .modifier(QuickCapsuleControlBackground())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Transaction details")
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var categorySelector: some View {
        if mode == .transfer {
            CenteredSelectionCarousel(
                items: destinationAccountCarouselItems,
                selection: $destinationAccountID
            )
            .padding(.horizontal, -16)
        } else {
            ZStack {
                if let expandedCategory {
                    CenteredSelectionCarousel(
                        items: subcategoryCarouselItems(for: expandedCategory),
                        selection: categoryCarouselBinding
                    )
                    .id(expandedCategory.id)
                    .transition(
                        .move(edge: .bottom)
                            .combined(with: .opacity)
                    )
                } else {
                    CenteredSelectionCarousel(
                        items: categoryCarouselItems,
                        selection: categoryCarouselBinding
                    )
                    .transition(
                        .move(edge: .top)
                            .combined(with: .opacity)
                    )
                }
            }
            .frame(height: 84)
            .clipped()
            .padding(.horizontal, -16)
            .animation(.snappy(duration: 0.3), value: expandedCategoryID)
        }
    }

    private var keypad: some View {
        LazyVGrid(columns: keypadColumns, spacing: 9) {
            ForEach(keypadRows.flatMap { $0 }, id: \.self) { key in
                Button {
                    amountExpression.enter(key)
                    viewModel.setAmountText(amountExpression.canonicalResult ?? "")
                } label: {
                    Group {
                        if key == "⌫" {
                            Image(systemName: "delete.left")
                        } else {
                            Text(key == "*" ? "×" : key == "/" ? "÷" : key)
                        }
                    }
                    .font(.title2.weight(isOperator(key) ? .semibold : .medium))
                    .frame(maxWidth: .infinity, minHeight: 49)
                    .modifier(QuickKeyBackground())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(keyAccessibilityLabel(key))
            }
        }
    }

    private var submitButton: some View {
        Button {
            Task { await save() }
        } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView()
                        .tint(Color(uiColor: .systemBackground))
                }
                Text(submitButtonTitle)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(Color(uiColor: .systemBackground))
        }
        .modifier(QuickSubmitButtonStyle())
        .disabled(isSubmitDisabled)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .padding(.horizontal, 10)
    }

    private var submitButtonTitle: String {
        if transaction != nil {
            return "Save changes"
        }
        return mode == .transfer ? "Transfer" : "Add transaction"
    }

    private var isSubmitDisabled: Bool {
        isSaving || transaction.map { !viewModel.hasChanges(from: $0) } == true
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
                systemImage: account.icon,
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
            systemImage: "square.grid.2x2",
            color: Color.primary,
            accessibilityLabel: "All categories",
            action: {
                navigationPath.append(AddTransactionRoute.categoryPicker)
            }
        )
        let uncategorized = CenteredSelectionCarouselItem(
            id: QuickCategoryCarouselID.uncategorized,
            title: "Uncategorized",
            systemImage: "circle.slash",
            color: Color.gray
        )
        let categories = visibleCategories.map { category in
            let hasSubcategories = !transactionStore.subcategories(of: category).isEmpty

            return CenteredSelectionCarouselItem(
                id: QuickCategoryCarouselID.category(category.id),
                title: category.name,
                systemImage: category.displayIcon,
                color: category.displayColor,
                accessibilityLabel: hasSubcategories
                    ? "\(category.name), has subcategories. Select again to show them."
                    : category.name,
                selectedAccessorySystemImage: hasSubcategories ? "chevron.down" : nil,
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
            systemImage: "chevron.down",
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
                systemImage: category.displayIcon,
                color: category.displayColor,
                accessibilityLabel: "\(parent.name), \(category.name)"
            )
        }
        return [collapse] + subcategories
    }

    private var displayAmount: String {
        guard let result = amountExpression.result else { return "0" }
        return result.formatted(
            .number.grouping(.automatic).precision(.fractionLength(0...4))
        )
    }

    private var amountAnimationValue: Double {
        guard let result = amountExpression.result else { return 0 }
        return NSDecimalNumber(decimal: result).doubleValue
    }

    private var amountAccessibilityLabel: String {
        ["Amount", displayAmount, selectedAccount?.currency]
            .compactMap { $0 }
            .joined(separator: " ")
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

    private func isOperator(_ key: String) -> Bool {
        ["+", "-", "*", "/"].contains(key)
    }

    private func keyAccessibilityLabel(_ key: String) -> String {
        switch key {
        case "+": "Plus"
        case "-": "Minus"
        case "*": "Multiply"
        case "/": "Divide"
        case ",": "Decimal separator"
        case "⌫": "Delete"
        default: key
        }
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
                if let transaction {
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

struct QuickAccountMenu: View {
    let accounts: [Account]
    let selectedAccountID: UUID?
    let onSelect: (UUID) -> Void

    private var title: String {
        accounts.first { $0.id == selectedAccountID }?.name ?? "Account"
    }

    var body: some View {
        Menu {
            ForEach(accounts) { account in
                Button {
                    onSelect(account.id)
                } label: {
                    Label(account.name, systemImage: account.icon)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "creditcard.fill")
                Text(title)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 10)
            .frame(height: 38)
            .modifier(QuickCapsuleControlBackground())
        }
        .buttonStyle(.plain)
        .disabled(accounts.isEmpty)
        .accessibilityLabel("Account, \(title)")
    }
}

private struct QuickCapsuleControlBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(Color(uiColor: .tertiarySystemFill), in: Capsule())
    }
}

private struct QuickKeyBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            Color(uiColor: .tertiarySystemFill),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }
}

struct QuickSubmitButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.plain)
            .background(Color.primary, in: Capsule())
            .contentShape(Capsule())
    }
}

private struct QuickTransactionDetailsView: View {
    @Binding var merchant: String
    @Binding var payee: String
    @Binding var note: String
    let supportsRecurrence: Bool
    @Binding var isRecurring: Bool
    @Binding var frequency: RecurrenceFrequency
    @Binding var hasEndDate: Bool
    @Binding var endDate: Date

    var body: some View {
        Form {
            Section("People and places") {
                TextField("Merchant", text: $merchant)
                    .textContentType(.organizationName)
                TextField("Payee", text: $payee)
                    .textContentType(.name)
            }

            Section("Details") {
                TextField("Note", text: $note, axis: .vertical)
                    .lineLimit(2...6)
            }

            if supportsRecurrence {
                Section("Recurring transaction") {
                    Toggle("Repeat", isOn: $isRecurring)

                    if isRecurring {
                        Picker("Frequency", selection: $frequency) {
                            ForEach(RecurrenceFrequency.allCases) { frequency in
                                Text(frequency.title).tag(frequency)
                            }
                        }

                        Toggle("Set end date", isOn: $hasEndDate)

                        if hasEndDate {
                            DatePicker(
                                "End date and time",
                                selection: $endDate,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                        } else {
                            LabeledContent("Ends", value: "Forever")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private enum AddTransactionRoute: Hashable {
    case categoryPicker
    case details
}

#Preview {
    AddTransactionView()
        .environmentObject(AccountStore())
        .environmentObject(TransactionStore())
}
