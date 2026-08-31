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

    var body: some View {
        Menu {
            Button {
                accountStore.selectedAccountID = nil
            } label: {
                accountLabel(
                    title: "Total",
                    systemImage: "square.stack.3d.up.fill",
                    isSelected: accountStore.selectedAccountID == nil
                )
            }

            if !accountStore.accounts.isEmpty {
                Divider()

                ForEach(accountStore.accounts) { account in
                    Button {
                        accountStore.selectedAccountID = account.id
                    } label: {
                        accountLabel(
                            title: account.name,
                            systemImage: account.icon,
                            color: account.iconColor.color,
                            isSelected: accountStore.selectedAccountID == account.id
                        )
                    }
                }
            }

            Divider()

            if let account = accountStore.selectedAccount {
                Button {
                    accountStore.editor = .edit(account)
                } label: {
                    Label("Edit account", systemImage: "pencil")
                }
            }

            Button {
                accountStore.editor = .add
            } label: {
                Label("Add account", systemImage: "plus")
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: selectedIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(selectedColor)
                    .frame(width: 28, height: 28)
                    .background(selectedColor.opacity(0.14), in: Circle())

                Text(accountStore.selectionTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Account, \(accountStore.selectionTitle)")
            .accessibilityHint("Opens the account picker")
        }
        .tint(.primary)
    }

    private var selectedIcon: String {
        accountStore.selectedAccount?.icon ?? "square.stack.3d.up.fill"
    }

    private var selectedColor: Color {
        accountStore.selectedAccount?.iconColor.color ?? .primary
    }

    private func accountLabel(
        title: String,
        systemImage: String,
        color: Color? = nil,
        isSelected: Bool
    ) -> some View {
        HStack {
            Label {
                Text(title)
            } icon: {
                menuIcon(systemImage: systemImage, color: color)
            }

            if isSelected {
                Image(systemName: "checkmark")
            }
        }
    }

    @ViewBuilder
    private func menuIcon(systemImage: String, color: Color?) -> some View {
#if canImport(UIKit)
        if let color, let image = UIImage(systemName: systemImage) {
            Image(
                uiImage: image.withTintColor(
                    UIColor(color),
                    renderingMode: .alwaysOriginal
                )
            )
        } else {
            Image(systemName: systemImage)
                .renderingMode(.template)
                .foregroundStyle(.primary)
        }
#else
        Image(systemName: systemImage)
            .foregroundStyle(color ?? .primary)
#endif
    }
}

struct AccountEditorView: View {
    private static let currencyCodes = Locale.Currency.isoCurrencies
        .map(\.identifier)
        .sorted()

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
        _name = State(initialValue: account?.name ?? "")
        _type = State(initialValue: account?.type ?? .checking)
        _currency = State(
            initialValue: account?.currency ?? Locale.current.currency?.identifier ?? "USD"
        )
        _icon = State(initialValue: account?.icon ?? "creditcard.fill")
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
                            Label(type.title, systemImage: type.systemImage)
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
                                Image(systemName: choice)
                                    .font(.body.weight(.semibold))
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
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
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
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
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
                .disabled(isSubmitDisabled)
                .opacity(isSubmitDisabled ? 0 : 1)
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
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

                Text(account == nil ? "Add account" : "Save changes")
            }
            .frame(maxWidth: .infinity)
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

private struct CurrencyPickerView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selection: String
    let currencyCodes: [String]

    @State private var query = ""

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
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .overlay {
            if filteredCurrencyCodes.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Code or currency name")
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
    func accountSelectorToolbar() -> some View {
        navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    AccountSelector()
                }
            }
    }
}
