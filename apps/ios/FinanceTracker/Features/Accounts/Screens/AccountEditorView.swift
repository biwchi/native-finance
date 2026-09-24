import SwiftUI

struct AccountEditorView: View {
    private static let currencyCodes = AppPreferences.currencyCodes
    private enum Field: Hashable { case name, balance }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountStore: AccountStore
    let account: Account?
    let onSave: ((Account) -> Void)?

    @State private var name: String
    @State private var initialBalance: String
    @State private var currency: String
    @State private var icon: String
    @State private var iconColor: AccountIconColor
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didRequestInitialFocus = false
    @State private var isKeyboardVisible = false
    @FocusState private var focusedField: Field?

    init(account: Account? = nil, onSave: ((Account) -> Void)? = nil) {
        self.account = account
        self.onSave = onSave
        let defaultCurrency = UserDefaults.standard.string(
            forKey: AppPreferences.defaultCurrencyKey
        ) ?? AppPreferences.initialCurrency
        _name = State(initialValue: account?.name ?? "")
        let balance = Decimal(string: account?.initialBalance ?? "0", locale: Locale(identifier: "en_US_POSIX")) ?? .zero
        _initialBalance = State(initialValue: balance == 0 ? "" : MoneyFormatter.editingText(balance))
        _currency = State(initialValue: account?.currency ?? defaultCurrency)
        _icon = State(initialValue: AppIcons.canonicalName(account?.icon ?? "credit-card"))
        _iconColor = State(initialValue: account?.iconColor ?? .blue)
    }

    var body: some View {
        NavigationStack {
            AppForm {
                AppSection {
                    HStack(spacing: AppSpacing.medium) {
                        AccountIconBadge(iconName: icon, color: iconColor.color)
                        TextField("Account name", text: $name)
                            .textInputAutocapitalization(.words)
                            .focused($focusedField, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .balance }
                            .accessibilityIdentifier("accountNameField")
                    }
                }

                if !suggestedIcons.isEmpty {
                    AppSection("Suggested icons") {
                        ScrollView(.horizontal) {
                            HStack(spacing: AppSpacing.small) {
                                ForEach(suggestedIcons) { option in
                                    AccentSelectionButton(
                                        option.title, isSelected: icon == option.symbol,
                                        iconName: option.symbol, appearance: .iconBadge,
                                        selectionTint: iconColor.color
                                    ) {
                                        focusedField = nil
                                        icon = option.symbol
                                    }
                                }
                            }
                            .padding(.vertical, AppSpacing.extraSmall)
                        }
                        .scrollIndicators(.hidden)
                    }
                }

                AppSection("Icon") {
                    colorPicker
                    IconPicker(selection: Binding(
                        get: { icon },
                        set: { icon = $0; focusedField = nil }
                    ))
                }

                AppSection {
                    LabeledContent("Initial balance") {
                        HStack(spacing: AppSpacing.extraSmall) {
                            Text(MoneyFormatter.symbol(for: currency))
                                .foregroundStyle(.secondary)
                            TextField("0", text: $initialBalance)
                                .keyboardType(.numbersAndPunctuation)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .focused($focusedField, equals: .balance)
                                .onSubmit { focusedField = nil }
                                .accessibilityLabel("Initial balance")
                                .accessibilityIdentifier("accountInitialBalanceField")
                        }
                    }
                    AppNavigationLink {
                        CurrencyPickerView(selection: $currency, currencyCodes: Self.currencyCodes)
                            .onAppear { focusedField = nil }
                    } label: {
                        LabeledContent("Currency", value: currency)
                    }
                } footer: {
                    Text("The balance before your recorded transactions, in \(currency). Use a negative amount if you owe money. It is excluded from income and spending.")
                    if account != nil {
                        Text("Changing currency keeps the initial balance amount. Existing transactions and recurring schedules keep their original currency.")
                    }
                }

                if let errorMessage {
                    AppSection {
                        Label(errorMessage, icon: "warning-triangle")
                            .foregroundStyle(AppColor.destructiveText)
                    }
                }
            }
            .disabled(isSaving)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(account == nil ? "New account" : "Edit account")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { AppIcon("xmark", size: AppControlSize.iconButtonGlyph) }
                        .accessibilityLabel("Close")
                        .disabled(isSaving)
                        .legacyToolbarIcon()
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !isKeyboardVisible {
                    PrimaryActionButton("Save", isLoading: isSaving) {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                    .padding(.horizontal, AppSpacing.extraLarge)
                    .padding(.vertical, AppSpacing.medium)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                isKeyboardVisible = false
            }
            .task {
                guard account == nil, !didRequestInitialFocus else { return }
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                guard !Task.isCancelled else { return }
                didRequestInitialFocus = true
                focusedField = .name
            }
        }
    }

    private var suggestedIcons: [IconPickerOption] {
        AppIconCatalog.suggestions(matching: name)
    }

    private var colorPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: AppSpacing.small) {
                ForEach(AccountIconColor.allCases) { choice in
                    Button {
                        focusedField = nil
                        iconColor = choice
                    } label: {
                        Circle()
                            .fill(choice.color)
                            .frame(width: 34, height: 34)
                            .overlay {
                                if iconColor == choice {
                                    AppIcon("check", size: 14).foregroundStyle(choice.foregroundColor)
                                }
                            }
                            .frame(width: AppControlSize.minimumTapTarget, height: AppControlSize.minimumTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(choice.title)
                    .accessibilityAddTraits(iconColor == choice ? .isSelected : [])
                }
            }
            .padding(.horizontal, AppSpacing.large)
        }
        .scrollIndicators(.hidden)
        .horizontalScrollFades()
        .padding(.horizontal, -AppSpacing.large)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Icon color")
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            Self.currencyCodes.contains(currency) && (try? Account.initialBalanceValue(initialBalance)) != nil
    }

    private func save() async {
        guard canSave, !isSaving else { return }
        focusedField = nil
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let savedAccount: Account
            if let account {
                savedAccount = try await accountStore.updateAccount(id: account.id, name: name, currency: currency,
                    icon: icon, iconColor: iconColor, initialBalance: initialBalance)
            } else {
                savedAccount = try await accountStore.createAccount(name: name, currency: currency,
                    icon: icon, iconColor: iconColor, initialBalance: initialBalance)
            }
            onSave?(savedAccount)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
