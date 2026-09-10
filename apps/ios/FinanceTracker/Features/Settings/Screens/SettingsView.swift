import SwiftUI

struct SettingsView: View {
    @ObservedObject private var repository = LocalFinanceRepository.shared
    private enum DeletionAction {
        case allData
        case userAccount

        var title: String {
            switch self {
            case .allData: "Delete all data"
            case .userAccount: "Delete user account"
            }
        }

        var explanation: String {
            switch self {
            case .allData:
                "Permanently delete all accounts, transactions, recurring payments, debts, categories, and budgets in this workspace."
            case .userAccount:
                "Permanently delete your user account and all associated data."
            }
        }
    }

    @AppStorage(AppPreferences.defaultCurrencyKey)
    private var defaultCurrency = AppPreferences.initialCurrency

    @AppStorage(AppPreferences.themeKey)
    private var theme = AppTheme.dark.rawValue

    @AppStorage(AppPreferences.preferSimpleTransactionEntryKey)
    private var preferSimpleTransactionEntry = false

    @Environment(\.openURL) private var openURL
    @AppStorage(AppPreferences.firstWeekdayKey) private var firstWeekday = 0
    @AppStorage(AppPreferences.roundTotalsKey) private var roundTotals = false
    @AppStorage(AppPreferences.useAllocatedBudgetForSummaryKey)
    private var useAllocatedBudgetForSummary = AppPreferences.defaultUseAllocatedBudgetForSummary
    @AppStorage(AppPreferences.recurringReminderDaysKey)
    private var recurringReminderDays = AppPreferences.defaultRecurringReminderDays
    @State private var deletionAction = DeletionAction.allData
    @State private var showsDeleteWarning = false
    @State private var showsDeleteConfirmation = false
    @State private var supportMessage: String?

    var body: some View {
        AppForm {
            if repository.snapshot.pending.contains(where: { $0.issue != nil }) {
                AppSection { NavigationLink("Review changes") { SyncReviewView() } }
            }
            AppSection { NavigationLink("Exchange rates") { RateDetailsView() } }
            AppSection {
                NavigationLink {
                    CategorySettingsView()
                } label: {
                    Label("Categories", icon: "label")
                }

                NavigationLink {
                    CurrencyPickerView(
                        selection: $defaultCurrency,
                        currencyCodes: AppPreferences.currencyCodes
                    )
                    .navigationTitle("Default currency")
                } label: {
                    if #available(iOS 26.0, *) {
                        currencySettingsLabel
                    } else {
                        // Native legacy row sizing otherwise removes padding from this two-line label.
                        currencySettingsLabel
                            .environment(\.defaultMinListRowHeight, 0)
                            .padding(.vertical, AppSpacing.large)
                    }
                }
                .legacyListRows(verticalPadding: 0)

                Toggle(isOn: isDarkTheme) {
                    Label("Dark theme", icon: "half-moon")
                }
            }

            AppSection {
                Picker(selection: $firstWeekday) {
                    Text("System default").tag(0)
                    ForEach(1...7, id: \.self) { day in
                        Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
                    }
                } label: {
                    Label("First day of week", icon: "calendar")
                }
                Toggle(isOn: $roundTotals) {
                    Label("Round totals", icon: "cash")
                }
            } header: {
                Text("Display")
            } footer: {
                Text("Show totals as whole numbers on Home and Budget. Transaction amounts keep their full precision.")
            }

            AppSection {
                Toggle(isOn: $useAllocatedBudgetForSummary) {
                    Label("Use pool and category limits", icon: "percentage-circle")
                }
                .accessibilityIdentifier("useAllocatedBudgetForSummary")
            } header: {
                Text("Budget summary")
            } footer: {
                Text("When no monthly limit is set, Home and Budget use the total of your pools and category limits outside pools. Turn off to show a budget summary only with a monthly limit.")
            }

            AppSection {
                Toggle(isOn: $preferSimpleTransactionEntry) {
                    Label("Use quick entry", icon: "input-field")
                }
            } header: {
                Text("Add transactions")
            } footer: {
                Text("The Add button opens a multiline entry above the keyboard, then shows the transaction form for review.")
            }

            AppSection {
                Picker(selection: $recurringReminderDays) {
                    ForEach(AppPreferences.recurringReminderDaysRange, id: \.self) { days in
                        Text(days == 0 ? "On the day" : days == 1 ? "1 day before" : "\(days) days before")
                            .tag(days)
                    }
                } label: {
                    Label("Show on Home", icon: "calendar")
                }
            } header: {
                Text("Recurring reminders")
            } footer: {
                Text("Show the nearest upcoming recurring transaction on Home, starting this many days before it is due.")
            }

            AppSection("Support") {
                ForEach(SettingsSupportLink.allCases) { link in
                    Button {
                        openSupport(link)
                    } label: {
                        HStack {
                            Label(link.rawValue, icon: link.icon)
                            Spacer()
                            AppIcon("arrow-up-right", size: 16)
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }

            AppSection {
                Button(role: .destructive) {
                    deletionAction = .allData
                    showsDeleteWarning = true
                } label: {
                    Label("Delete all data", icon: "trash")
                        .foregroundStyle(AppColor.destructiveText)
                }
                Button(role: .destructive) {
                    deletionAction = .userAccount
                    showsDeleteWarning = true
                } label: {
                    Label("Delete user account", icon: "user")
                        .foregroundStyle(AppColor.destructiveText)
                }
            } header: {
                Text("Danger zone")
                    .foregroundStyle(AppColor.destructiveText)
            }
            .tint(.red)

            AppSection {
                Text(appVersion)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: AppColor.switchTrack))
        .navigationTitle("Settings")
        .confirmationDialog(deletionAction.title + "?", isPresented: $showsDeleteWarning, titleVisibility: .visible) {
            Button("Continue", role: .destructive) { showsDeleteConfirmation = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deletionAction.explanation + " This cannot be undone. You’ll type confirm in the next step.")
        }
        .sheet(isPresented: $showsDeleteConfirmation) {
            DeleteDataConfirmationView(title: deletionAction.title, explanation: deletionAction.explanation) { confirmation in
                switch deletionAction {
                case .allData:
                    try repository.deleteAllData()
                    URLCache.shared.removeAllCachedResponses()
                    NotificationCenter.default.post(name: AppPreferences.dataDeletedNotification, object: nil)
                case .userAccount:
                    throw NSError(domain: "Settings", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Account deletion isn’t available yet."
                    ])
                }
            }
        }
        .alert("Support", isPresented: Binding(
            get: { supportMessage != nil },
            set: { if !$0 { supportMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(supportMessage ?? "")
        }
    }

    private var appVersion: String {
        let bundle = Bundle.main
        let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Finance Tracker"
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(name) · \(version) (\(build))"
    }

    private func openSupport(_ link: SettingsSupportLink) {
        guard let url = link.url() else {
            supportMessage = "\(link.rawValue) is not available in this version yet."
            return
        }
        openURL(url) { accepted in
            if !accepted { supportMessage = "Couldn’t open \(link.rawValue.lowercased()). Please try again." }
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

    private var currencySettingsLabel: some View {
        LabeledContent {
            Text(currencyLabel)
                .foregroundStyle(.secondary)
        } label: {
            Label("Default currency", icon: "cash")
        }
    }
}
