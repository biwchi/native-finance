import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

extension AccountIconColor {
    var color: Color {
        switch self {
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .green: .green
        case .teal: .teal
        case .gray: .gray
        }
    }
}

struct AccountSelector: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore
    // The picker needs all currencies even when the dashboard is showing one account.
    @StateObject private var exchangeRateStore = ExchangeRateStore()
    @ScaledMetric(relativeTo: .body) private var iconBadgeSize = 36

    @AppStorage(AppPreferences.defaultCurrencyKey)
    private var reportingCurrency = AppPreferences.initialCurrency

    var compact = false

    var body: some View {
        Menu {
            Toggle(isOn: accountSelection(nil)) {
                accountLabel(
                    title: "All Accounts",
                    subtitle: balanceSubtitle(for: nil),
                    iconName: "credit-cards"
                )
            }

            if !accountStore.accounts.isEmpty {
                Divider()

                ForEach(accountStore.accounts) { account in
                    Toggle(isOn: accountSelection(account.id)) {
                        accountLabel(
                            title: account.name,
                            subtitle: balanceSubtitle(for: account),
                            iconName: account.icon,
                            color: account.iconColor.color
                        )
                    }
                }
            }

            Divider()

            Button {
                accountStore.isManagingAccounts = true
            } label: {
                Label("Manage Accounts", icon: "settings")
            }
        } label: {
            selectorLabel
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Account, \(accountStore.selectionTitle), \(selectionSubtitle)")
                .accessibilityHint("Opens the account picker")
        }
        .buttonStyle(.plain)
        .tint(.primary)
        .task(id: exchangeRateScopeKey) {
            await exchangeRateStore.load(
                currencies: exchangeCurrencies,
                reportingCurrency: reportingCurrency.uppercased()
            )
        }
    }

    @ViewBuilder
    private var selectorLabel: some View {
        if compact {
            HStack(spacing: 9) {
                selectedIconBadge

                VStack(alignment: .leading, spacing: 0) {
                    Text(accountStore.selectionTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(selectionSubtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                AppIcon("nav-arrow-down", size: 11)
                    .foregroundStyle(.secondary)
            }
            .padding([.leading, .vertical], 4)
            .padding(.trailing, 12)
            .accountSelectorGlass()
            .contentShape(Capsule())
        } else {
            HStack(spacing: 9) {
                selectedIconBadge

                VStack(alignment: .leading, spacing: 0) {
                    Text(accountStore.selectionTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(selectionSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                .layoutPriority(1)
            }
            .padding(.leading, 5)
            .padding(.trailing, 14)
            .padding(.vertical, 5)
            .accountSelectorGlass()
            .contentShape(Capsule())
        }
    }

    private var selectedIcon: String {
        accountStore.selectedAccount?.icon ?? "credit-cards"
    }

    private var selectedColor: Color {
        accountStore.selectedAccount?.iconColor.color ?? .primary
    }

    private var selectedIconBadge: some View {
        AppIcon(selectedIcon, size: 24)
            .foregroundStyle(selectedColor)
            .frame(width: iconBadgeSize, height: iconBadgeSize)
            .background(selectedColor.opacity(0.14), in: Circle())
            .accessibilityHidden(true)
    }

    private var selectionSubtitle: String {
        balanceSubtitle(for: accountStore.selectedAccount)
    }

    private func balanceSubtitle(for account: Account?) -> String {
        switch transactionStore.state {
        case .idle, .loading:
            "Loading balance"
        case .loaded:
            if let balance = transactionStore.balance(
                accountID: account?.id,
                currency: account?.currency ?? reportingCurrency.uppercased(),
                rates: exchangeRateStore.snapshot
            ) {
                MoneyFormatter.format(
                    balance, currency: account?.currency ?? reportingCurrency.uppercased()
                )
            } else if exchangeRateStore.state == .idle || exchangeRateStore.state == .loading {
                "Converting balance"
            } else {
                "Balance unavailable"
            }
        case .failed:
            "Balance unavailable"
        }
    }

    private var exchangeCurrencies: Set<String> {
        return Set(
            accountStore.accounts.map(\.currency) +
            transactionStore.allTransactions.map(\.currency)
        )
    }

    private var exchangeRateScopeKey: String {
        "\(reportingCurrency.uppercased()):\(exchangeCurrencies.sorted().joined(separator: ","))"
    }

    private func accountSelection(_ accountID: UUID?) -> Binding<Bool> {
        Binding(
            get: { accountStore.selectedAccountID == accountID },
            set: { isSelected in
                if isSelected { accountStore.selectedAccountID = accountID }
            }
        )
    }

    @ViewBuilder
    private func accountLabel(
        title: String,
        subtitle: String,
        iconName: String,
        color: Color? = nil
    ) -> some View {
        Text(title)
        Text(subtitle)
        menuIcon(iconName: iconName, color: color)
    }

    @ViewBuilder
    private func menuIcon(iconName: String, color: Color?) -> some View {
#if canImport(UIKit)
        if let color, let image = AppIcons.uiImage(named: iconName) {
            Image(
                uiImage: image.withTintColor(
                    UIColor(color),
                    renderingMode: .alwaysOriginal
                )
            )
        } else {
            AppIcons.resolve(iconName).image().renderingMode(.template)
                .foregroundStyle(.primary)
        }
#else
        AppIcon(iconName)
            .foregroundStyle(color ?? .primary)
#endif
    }
}

struct AccountManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore

    @State private var editor: AccountEditorDestination?
    @State private var presentedAlert: AccountManagementAlert?
    @State private var isUpdatingOrder = false
    @State private var deletingAccountID: UUID?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if accountStore.accounts.isEmpty {
                        ContentUnavailableView(
                            "No accounts",
                            iconName: "credit-card",
                            description: Text("Add an account to start tracking transactions.")
                        )
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(accountStore.accounts) { account in
                            Button {
                                editor = .edit(account)
                            } label: {
                                AccountManagementRow(
                                    account: account,
                                    isWorking: deletingAccountID == account.id
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(isUpdatingOrder || deletingAccountID != nil)
                        }
                        .onMove(perform: moveAccounts)
                        .onDelete(perform: requestDeletion)
                        .moveDisabled(isUpdatingOrder || deletingAccountID != nil)
                        .deleteDisabled(isUpdatingOrder || deletingAccountID != nil)
                    }
                } footer: {
                    if !accountStore.accounts.isEmpty {
                        Text("Tap an account to edit it. Use Edit to reorder or remove accounts.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isBusy)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                        .disabled(accountStore.accounts.isEmpty || isBusy)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .disabled(isBusy)
                }

                ToolbarItem(placement: .bottomBar) {
                    Button {
                        editor = .add
                    } label: {
                        Label("Add Account", icon: "plus")
                    }
                    .disabled(isBusy)
                }
            }
        }
        .sheet(item: $editor) { destination in
            AccountEditorView(account: destination.account)
                .environmentObject(accountStore)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert(item: $presentedAlert) { alert in
            switch alert {
            case let .confirmDeletion(account):
                Alert(
                    title: Text("Delete \(account.name)?"),
                    message: Text(
                        "This also deletes its transactions and account budget data. This can't be undone."
                    ),
                    primaryButton: .destructive(Text("Delete")) {
                        Task {
                            await deleteAccount(account)
                        }
                    },
                    secondaryButton: .cancel()
                )
            case let .error(message):
                Alert(
                    title: Text("Couldn't update accounts"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var isBusy: Bool {
        isUpdatingOrder || deletingAccountID != nil
    }

    private func moveAccounts(from source: IndexSet, to destination: Int) {
        var reorderedAccounts = accountStore.accounts
        reorderedAccounts.move(fromOffsets: source, toOffset: destination)
        isUpdatingOrder = true

        Task {
            defer { isUpdatingOrder = false }

            do {
                try await accountStore.reorderAccounts(reorderedAccounts)
            } catch {
                presentedAlert = .error(error.localizedDescription)
            }
        }
    }

    private func requestDeletion(at offsets: IndexSet) {
        guard let index = offsets.first,
              accountStore.accounts.indices.contains(index) else {
            return
        }
        presentedAlert = .confirmDeletion(accountStore.accounts[index])
    }

    private func deleteAccount(_ account: Account) async {
        deletingAccountID = account.id
        defer { deletingAccountID = nil }

        do {
            try await accountStore.deleteAccount(account)
            await transactionStore.loadTransactions(accountID: accountStore.selectedAccountID)
        } catch {
            presentedAlert = .error(error.localizedDescription)
        }
    }
}

private struct AccountManagementRow: View {
    let account: Account
    let isWorking: Bool

    var body: some View {
        HStack(spacing: 12) {
            AppIcon(account.icon, size: 17)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(account.iconColor.color, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .foregroundStyle(.primary)

                Text("\(account.type.title) · \(account.currency)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isWorking {
                ProgressView()
            } else {
                AppIcon("nav-arrow-right", size: 12)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private enum AccountEditorDestination: Identifiable {
    case add
    case edit(Account)

    var id: String {
        switch self {
        case .add: "add"
        case let .edit(account): account.id.uuidString
        }
    }

    var account: Account? {
        if case let .edit(account) = self {
            account
        } else {
            nil
        }
    }
}

private enum AccountManagementAlert: Identifiable {
    case confirmDeletion(Account)
    case error(String)

    var id: String {
        switch self {
        case let .confirmDeletion(account): "delete-\(account.id.uuidString)"
        case let .error(message): "error-\(message)"
        }
    }
}

struct AccountEditorView: View {
    private static let currencyCodes = AppPreferences.currencyCodes

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountStore: AccountStore

    let account: Account?

    @State private var name: String
    @State private var type: AccountType
    @State private var currency: String
    @State private var icon: String
    @State private var iconColor: AccountIconColor
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(account: Account? = nil) {
        self.account = account
        let defaultCurrency = UserDefaults.standard.string(
            forKey: AppPreferences.defaultCurrencyKey
        ) ?? AppPreferences.initialCurrency
        _name = State(initialValue: account?.name ?? "")
        _type = State(initialValue: account?.type ?? .checking)
        _currency = State(initialValue: account?.currency ?? defaultCurrency)
        _icon = State(initialValue: AppIcons.canonicalName(account?.icon ?? "credit-card"))
        _iconColor = State(initialValue: account?.iconColor ?? .blue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account details") {
                    TextField("Name", text: $name)
                        .textContentType(.name)

                    Picker("Type", selection: $type) {
                        ForEach(AccountType.allCases) { type in
                            Label(type.title, icon: type.iconName)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    NavigationLink {
                        CurrencyPickerView(
                            selection: $currency,
                            currencyCodes: Self.currencyCodes
                        )
                    } label: {
                        HStack {
                            Text("Currency")

                            Spacer()

                            Text(currencyLabel(currency))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Section("Icon") {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible()), count: 6),
                        spacing: 16
                    ) {
                        ForEach(AccountIcon.choices, id: \.self) { choice in
                            Button {
                                icon = choice
                            } label: {
                                AppIcon(choice, size: 17)
                                    .foregroundStyle(icon == choice ? .white : iconColor.color)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        icon == choice ? iconColor.color : Color.secondary.opacity(0.12),
                                        in: Circle()
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(choice)
                            .accessibilityAddTraits(icon == choice ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Icon color") {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible()), count: 6),
                        spacing: 16
                    ) {
                        ForEach(AccountIconColor.allCases) { choice in
                            Button {
                                iconColor = choice
                            } label: {
                                Circle()
                                    .fill(choice.color)
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        if iconColor == choice {
                                            AppIcon("check", size: 12)
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(choice.title)
                            .accessibilityAddTraits(iconColor == choice ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, icon: "warning-triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
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
                submitButton
                    .controlSize(.large)
                    .disabled(isSubmitDisabled)
                    .opacity(isSubmitDisabled ? 0 : 1)
                    .padding(.horizontal)
                    .padding(.vertical, 12)
            }
        }
    }

    private var submitButton: some View {
        PrimaryActionButton(
            account == nil ? "Add account" : "Save changes",
            isLoading: isSaving,
            appearance: .glass
        ) {
            Task {
                await save()
            }
        }
    }

    private var isSubmitDisabled: Bool {
        !canSave || isSaving
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            Self.currencyCodes.contains(currency)
    }

    private func currencyLabel(_ code: String) -> String {
        guard let name = Locale.current.localizedString(forCurrencyCode: code) else {
            return code
        }

        return "\(code) · \(name)"
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            if let account {
                try await accountStore.updateAccount(
                    id: account.id,
                    name: name,
                    type: type,
                    currency: currency,
                    icon: icon,
                    iconColor: iconColor
                )
            } else {
                try await accountStore.createAccount(
                    name: name,
                    type: type,
                    currency: currency,
                    icon: icon,
                    iconColor: iconColor
                )
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CurrencyPickerView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selection: String
    let currencyCodes: [String]

    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        List(filteredCurrencyCodes, id: \.self) { code in
            Button {
                selection = code
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(code)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if let name = currencyName(code) {
                            Text(name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if selection == code {
                        AppIcon("check", size: 17)
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .overlay {
            if filteredCurrencyCodes.isEmpty {
                ContentUnavailableView(
                    "No currencies found",
                    iconName: "search",
                    description: Text("No results for “\(query)”.")
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            searchField
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            AppIcon("search", size: 20)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Code or currency name", text: $query)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isSearchFocused)
                .onSubmit { isSearchFocused = false }
                .accessibilityLabel("Search currencies")

            if !query.isEmpty {
                Button {
                    query = ""
                    isSearchFocused = true
                } label: {
                    AppIcon("xmark", size: 16)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, query.isEmpty ? 18 : 4)
        .frame(minHeight: 54)
        .accountSelectorGlass()
        .contentShape(Capsule())
        .onTapGesture { isSearchFocused = true }
    }

    private var filteredCurrencyCodes: [String] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !search.isEmpty else {
            return currencyCodes
        }

        return currencyCodes.filter { code in
            code.localizedCaseInsensitiveContains(search) ||
                currencyName(code)?.localizedCaseInsensitiveContains(search) == true
        }
    }

    private func currencyName(_ code: String) -> String? {
        Locale.current.localizedString(forCurrencyCode: code)
    }
}

extension View {
    @ViewBuilder
    fileprivate func accountSelectorGlass() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(), in: Capsule())
        } else {
            background(.thinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                }
        }
    }

    func accountSelectorToolbar() -> some View {
        navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    AccountSelector()
                }
            }
    }
}
