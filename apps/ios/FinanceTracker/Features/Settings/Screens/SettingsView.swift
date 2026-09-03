import SwiftUI

struct SettingsView: View {
    var onCurrencyPickerVisibilityChange: (Bool) -> Void = { _ in }

    @AppStorage(AppPreferences.defaultCurrencyKey)
    private var defaultCurrency = AppPreferences.initialCurrency

    @AppStorage(AppPreferences.themeKey)
    private var theme = AppTheme.dark.rawValue

    @AppStorage(AppPreferences.preferSimpleTransactionEntryKey)
    private var preferSimpleTransactionEntry = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        CurrencyPickerView(
                            selection: $defaultCurrency,
                            currencyCodes: AppPreferences.currencyCodes
                        )
                        .navigationTitle("Default currency")
                        .onAppear { onCurrencyPickerVisibilityChange(true) }
                        .onDisappear { onCurrencyPickerVisibilityChange(false) }
                    } label: {
                        LabeledContent {
                            Text(currencyLabel)
                                .foregroundStyle(.secondary)
                        } label: {
                            Label("Default currency", icon: "cash")
                        }
                    }

                    Toggle(isOn: isDarkTheme) {
                        Label("Dark theme", icon: "half-moon")
                    }
                }

                Section {
                    Toggle(isOn: $preferSimpleTransactionEntry) {
                        Label("Use quick entry", icon: "input-field")
                    }
                } header: {
                    Text("Add transactions")
                } footer: {
                    Text("The Add button opens a multiline entry above the keyboard, then shows the transaction form for review.")
                }

                Section {
                    NavigationLink {
                        CategorySettingsView()
                    } label: {
                        Label("Categories", icon: "label")
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var isDarkTheme: Binding<Bool> {
        Binding(
            get: { (AppTheme(rawValue: theme) ?? .dark) == .dark },
            set: { theme = ($0 ? AppTheme.dark : .light).rawValue }
        )
    }

    private var currencyLabel: String {
        guard let name = Locale.current.localizedString(forCurrencyCode: defaultCurrency) else {
            return defaultCurrency
        }
        return "\(defaultCurrency) · \(name)"
    }
}
