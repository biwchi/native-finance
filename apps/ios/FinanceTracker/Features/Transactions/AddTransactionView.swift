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

private enum TransactionEntryMode: Equatable {
    case manual
    case simple
}

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore
    @AppStorage("lastTransactionAccountID") private var lastAccountID = ""

    let transaction: FinanceTransaction?

    @StateObject private var viewModel: AddTransactionViewModel
    @State private var navigationPath = NavigationPath()
    @State private var mode = QuickTransactionMode.expense
    @State private var amountExpression = AmountExpression()
    @State private var destinationAccountID: UUID?
    @State private var expandedCategoryID: UUID?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var entryMode: TransactionEntryMode
    @State private var simpleTransactionText = ""
    @State private var isShowingAIPlaceholder = false
    @FocusState private var isSimpleInputFocused: Bool

    private let keypadColumns = Array(repeating: GridItem(.flexible(), spacing: 9), count: 4)
    private let keypadRows = [
        ["1", "2", "3", "+"],
        ["4", "5", "6", "-"],
        ["7", "8", "9", "*"],
        [",", "0", "⌫", "/"],
    ]
    private let simplePromptExamples = [
        "$12 at a restaurant yesterday",
        "Coffee with Maya, $8.50 this morning",
        "Salary payment of $2,400 today",
    ]

    init(transaction: FinanceTransaction? = nil) {
        self.transaction = transaction
        let startsInSimpleMode = transaction == nil && UserDefaults.standard.bool(
            forKey: AppPreferences.preferSimpleTransactionEntryKey
        )
        _viewModel = StateObject(wrappedValue: AddTransactionViewModel(transaction: transaction))
        _mode = State(initialValue: transaction.map(QuickTransactionMode.init) ?? .expense)
        _amountExpression = State(
            initialValue: AmountExpression(rawValue: transaction?.amount ?? "")
        )
        _entryMode = State(initialValue: startsInSimpleMode ? .simple : .manual)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            entryContent
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                        .disabled(isSaving)
                    }

                    if transaction == nil {
                        ToolbarItem(placement: .primaryAction) {
                            entryModeButton
                        }
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
                            description: descriptionBinding,
                            note: noteBinding
                        )
                    }
                }
        }
        .task {
            await accountStore.loadAccounts()
            viewModel.configureAccount(
                selectedAccountID: accountStore.selectedAccountID,
                lastUsedAccountID: UUID(uuidString: lastAccountID),
                accounts: accountStore.accounts
            )
            chooseDestinationIfNeeded()
            await transactionStore.loadCategories()
        }
        .task(id: entryMode) {
            guard entryMode == .simple else { return }
            try? await Task.sleep(for: .milliseconds(300))
            isSimpleInputFocused = true
        }
        .alert(transaction == nil ? "Couldn’t add transaction" : "Couldn’t save transaction", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Try again.")
        }
        .alert("AI connection comes next", isPresented: $isShowingAIPlaceholder) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The Simple Add interface is ready. Connect the AI parser to turn this description into transaction details.")
        }
    }

    @ViewBuilder
    private var entryContent: some View {
        if entryMode == .simple, transaction == nil {
            simpleEntryContent
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        } else {
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
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    private var navigationTitle: String {
        if transaction != nil { return "Edit transaction" }
        return entryMode == .simple ? "Simple Add" : "New transaction"
    }

    private var entryModeButton: some View {
        Button {
            isSimpleInputFocused = false
            withAnimation(.snappy(duration: 0.25)) {
                entryMode = entryMode == .simple ? .manual : .simple
            }
        } label: {
            Image(systemName: entryMode == .simple ? "square.and.pencil" : "wand.and.stars")
        }
        .accessibilityLabel(entryMode == .simple ? "Use manual entry" : "Use Simple Add")
        .accessibilityHint("Switches the transaction entry form")
    }

    private var simpleEntryContent: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentColor.opacity(0.24), Color.purple.opacity(0.12)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 72, height: 72)

                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .symbolEffect(.bounce, value: entryMode)
                    }
                    .accessibilityHidden(true)

                    VStack(spacing: 7) {
                        Text("What happened?")
                            .font(.title2.bold())

                        Text("Write it like you'd say it. We'll fill in the amount, category, and date.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 330)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Describe the transaction")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextField(
                        "$12 at a restaurant yesterday",
                        text: $simpleTransactionText,
                        axis: .vertical
                    )
                    .font(.title3)
                    .lineLimit(4...7)
                    .focused($isSimpleInputFocused)
                    .submitLabel(.continue)
                    .onSubmit(fillTransactionDetails)
                    .padding(18)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                Color.accentColor.opacity(isSimpleInputFocused ? 0.7 : 0.18),
                                lineWidth: isSimpleInputFocused ? 2 : 1
                            )
                    }
                    .shadow(color: Color.accentColor.opacity(isSimpleInputFocused ? 0.12 : 0), radius: 18)
                    .animation(.easeOut(duration: 0.2), value: isSimpleInputFocused)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Try an example")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(simplePromptExamples, id: \.self) { example in
                                Button {
                                    simpleTransactionText = example
                                    isSimpleInputFocused = true
                                } label: {
                                    Text(example)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                        .padding(.horizontal, 14)
                                        .frame(height: 38)
                                        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .contentMargins(.horizontal, 0, for: .scrollContent)
                }

                Label("You'll review the details before anything is saved.", systemImage: "checkmark.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button(action: fillTransactionDetails) {
                Label("Fill transaction details", systemImage: "sparkles")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(Color(uiColor: .systemBackground))
            }
            .modifier(QuickSubmitButtonStyle())
            .disabled(trimmedSimpleTransactionText.isEmpty)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }

    private var trimmedSimpleTransactionText: String {
        simpleTransactionText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fillTransactionDetails() {
        guard !trimmedSimpleTransactionText.isEmpty else { return }
        isSimpleInputFocused = false
        isShowingAIPlaceholder = true
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
            accountMenu(title: selectedAccount?.name ?? "Account", selection: accountBinding)

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

    private func accountMenu(title: String, selection: Binding<UUID?>) -> some View {
        Menu {
            ForEach(accountStore.accounts) { account in
                Button {
                    selection.wrappedValue = account.id
                    if mode == .transfer {
                        chooseDestinationIfNeeded()
                    }
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
            !viewModel.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !viewModel.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    private var descriptionBinding: Binding<String> {
        Binding(
            get: { viewModel.description },
            set: { viewModel.setDescription($0, categories: transactionStore.categories) }
        )
    }

    private var noteBinding: Binding<String> {
        Binding(get: { viewModel.note }, set: viewModel.setNote)
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
        let sourceName = selectedAccount?.name ?? "account"
        let destinationName = destinationAccount?.name ?? "account"

        try await transactionStore.createTransfer(
            TransferRequest(
                fromAccountId: sourceID,
                toAccountId: destinationID,
                amount: amount,
                merchant: optionalText(viewModel.merchant),
                payee: optionalText(viewModel.payee),
                description: optionalText(viewModel.description) ??
                    "Transfer from \(sourceName) to \(destinationName)",
                note: optionalText(viewModel.note),
                occurredAt: viewModel.occurredAt
            )
        )
    }

    private func transactionRequest(
        accountID: UUID,
        kind: TransactionKind,
        amount: String,
        categoryID: UUID?,
        fallbackDescription: String? = nil
    ) -> TransactionRequest {
        TransactionRequest(
            accountId: accountID,
            kind: kind,
            amount: amount,
            categoryId: categoryID,
            merchant: optionalText(viewModel.merchant),
            payee: optionalText(viewModel.payee),
            description: optionalText(viewModel.description) ?? fallbackDescription,
            note: optionalText(viewModel.note),
            occurredAt: viewModel.occurredAt
        )
    }

    private func optionalText(_ value: String) -> String? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
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

private struct QuickSubmitButtonStyle: ViewModifier {
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
    @Binding var description: String
    @Binding var note: String

    var body: some View {
        Form {
            Section("People and places") {
                TextField("Merchant", text: $merchant)
                    .textContentType(.organizationName)
                TextField("Payee", text: $payee)
                    .textContentType(.name)
            }

            Section("Details") {
                TextField("Description", text: $description)
                TextField("Note", text: $note, axis: .vertical)
                    .lineLimit(2...6)
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
