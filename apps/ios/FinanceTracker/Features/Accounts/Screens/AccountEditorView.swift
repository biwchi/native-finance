import SwiftUI

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
                            .foregroundStyle(AppColor.destructive)
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
