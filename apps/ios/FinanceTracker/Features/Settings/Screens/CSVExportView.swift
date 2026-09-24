import SwiftUI
import UniformTypeIdentifiers

struct CSVExportView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore
    @State private var accountID: UUID?
    @State private var usesDateRange = false
    @State private var startDate = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: .now)) ?? .now
    @State private var endDate = Date.now
    @State private var document: CSVDocument?
    @State private var showsExporter = false
    @State private var isPreparing = false
    @State private var errorMessage: String?

    var body: some View {
        AppForm {
            AppSection("Account") {
                Picker("Account", selection: $accountID) {
                    Text("All accounts").tag(UUID?.none)
                    ForEach(accountStore.accounts) { account in
                        Text("\(account.name) · \(account.currency)").tag(Optional(account.id))
                    }
                }
            }
            AppSection("Period") {
                Picker("Period", selection: $usesDateRange) {
                    Text("All dates").tag(false)
                    Text("Date range").tag(true)
                }
                if usesDateRange {
                    DatePicker("From", selection: $startDate, displayedComponents: .date)
                    DatePicker("Through", selection: $endDate, displayedComponents: .date)
                    if !validPeriod {
                        Text("The end date must be on or after the start date.")
                            .foregroundStyle(AppColor.destructiveText)
                    }
                }
            }
            AppSection {
                LabeledContent("Transactions", value: "\(selectedTransactions.count)")
                if selectedTransactions.isEmpty {
                    Text("No transactions match these filters.").foregroundStyle(.secondary)
                }
            } footer: {
                Text("Both dates are included. Amounts keep their saved currencies. This exports recorded transactions, including past recurring payments, without recreating their schedules. Transfers appear as an expense and an income. Account opening balances are not included.")
            }
        }
        .navigationTitle("Export CSV")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            PrimaryActionButton("Export CSV", isLoading: isPreparing) { prepareExport() }
                .disabled(!validPeriod || selectedTransactions.isEmpty || isPreparing)
                .padding(.horizontal, AppSpacing.medium)
                .padding(.vertical, AppSpacing.small)
        }
        .fileExporter(isPresented: $showsExporter, document: document, contentType: .commaSeparatedText, defaultFilename: "transactions") { result in
            if case .failure(let error) = result { errorMessage = error.localizedDescription }
        }
        .alert("Couldn’t export CSV", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private var validPeriod: Bool {
        !usesDateRange || Calendar.current.startOfDay(for: startDate) <= Calendar.current.startOfDay(for: endDate)
    }

    private var selectedTransactions: [FinanceTransaction] {
        guard validPeriod else { return [] }
        return TransactionCSV.filtered(transactionStore.allTransactions, accountID: accountID,
                                       start: usesDateRange ? startDate : nil, end: usesDateRange ? endDate : nil)
    }

    private func prepareExport() {
        guard validPeriod, !isPreparing else { return }
        let transactions = selectedTransactions
        let accounts = accountStore.accounts
        let categories = transactionStore.categories
        let debts = transactionStore.debts
        isPreparing = true
        Task {
            let text = await Task.detached(priority: .userInitiated) {
                TransactionCSV.encode(transactions, accounts: accounts, categories: categories, debts: debts)
            }.value
            document = CSVDocument(text: text)
            isPreparing = false
            showsExporter = true
        }
    }
}
