import Combine
import Foundation

@MainActor
final class TransactionStore: ObservableObject {
    enum State: Equatable { case idle, loading, loaded, failed(String) }
    @Published private(set) var state: State = .loaded
    @Published private(set) var transactions: [FinanceTransaction] = []
    @Published private(set) var allTransactions: [FinanceTransaction] = []
    @Published private(set) var upcomingState: State = .loaded
    @Published private(set) var upcomingTransactions: [UpcomingTransaction] = []
    @Published private(set) var allUpcomingTransactions: [UpcomingTransaction] = []
    @Published private(set) var categories: [TransactionCategory] = []
    @Published private(set) var isLoadingCategories = false
    @Published private(set) var categoryErrorMessage: String?
    @Published private(set) var debts: [Debt] = []
    @Published private(set) var debtErrorMessage: String?
    @Published private(set) var isLoadingDebts = false
    // Keep unfinished composer text for this app session, never in local storage.
    @Published var quickEntryText = ""
    private let repository: LocalFinanceRepository
    private let apiClient: APIClient
    private var currentAccountID: UUID?
    private var isPreview = false
    private var balanceAccounts: [Account] = []
    private var subscription: AnyCancellable?
    init(apiClient: APIClient = APIClient(), repository: LocalFinanceRepository? = nil) {
        self.apiClient = apiClient; self.repository = repository ?? .shared
        apply(self.repository.snapshot)
        subscription = self.repository.$snapshot.sink { [weak self] in self?.apply($0) }
    }
    private func apply(_ snapshot: LocalSnapshot) {
        balanceAccounts = snapshot.sortedAccounts
        allTransactions = snapshot.detailedTransactions
        transactions = allTransactions.filter { currentAccountID == nil || $0.accountId == currentAccountID }
        categories = Array(snapshot.categories.values)
        debts = snapshot.debts.values.sorted(by: Debt.orderedBefore)
        allUpcomingTransactions = snapshot.upcoming(now: .now)
        upcomingTransactions = allUpcomingTransactions.filter { currentAccountID == nil || $0.accountId == currentAccountID }
    }
    func transactions(for accountID: UUID?) -> [FinanceTransaction] { allTransactions.filter { accountID == nil || $0.accountId == accountID } }
    func upcomingTransactions(for accountID: UUID?) -> [UpcomingTransaction] { allUpcomingTransactions.filter { accountID == nil || $0.accountId == accountID } }
    func loadTransactions(accountID: UUID?) async { currentAccountID = accountID; if isPreview { transactions = transactions(for: accountID); return }; apply(repository.snapshot) }
    func loadUpcomingTransactions(accountID: UUID?) async { currentAccountID = accountID; if isPreview { upcomingTransactions = upcomingTransactions(for: accountID); return }; apply(repository.snapshot) }
    func loadCategories(force: Bool = false) async { guard !isPreview else { return }; categories = Array(repository.snapshot.categories.values) }
    func loadDebts() async { guard !isPreview else { return }; apply(repository.snapshot) }
    func categories(for kind: TransactionKind) -> [TransactionCategory] {
        categories.filter { $0.kind == kind }.sorted { ($0.sortOrder ?? 1000, $0.name.lowercased()) < ($1.sortOrder ?? 1000, $1.name.lowercased()) }
    }
    func rootCategories(for kind: TransactionKind) -> [TransactionCategory] { categories(for: kind).filter { $0.parentId == nil } }
    func subcategories(of category: TransactionCategory) -> [TransactionCategory] { categories(for: category.kind).filter { $0.parentId == category.id } }
    func categoryPath(_ category: TransactionCategory) -> String {
        guard let parent = categories.first(where: { $0.id == category.parentId }) else { return category.name }
        return "\(parent.name) › \(category.name)"
    }
    func createDebt(name: String, icon: String = "user", color: CategoryColor = .blue) async throws -> Debt { try repository.edit { try $0.saveDebt(name: name, icon: icon, color: color) } }
    func updateDebt(_ debt: Debt, name: String, icon: String, color: CategoryColor) async throws -> Debt { try repository.edit { try $0.saveDebt(id: debt.id, name: name, icon: icon, color: color) } }
    func reorderDebts(_ debts: [Debt]) async throws { try repository.edit { try $0.reorderDebts(debts) } }
    func deleteDebt(_ debt: Debt) async throws { try repository.edit { try $0.deleteDebt(debt.id) } }
    @discardableResult
    func createCategory(name: String, kind: TransactionKind, parentID: UUID? = nil, icon: String = "label", color: CategoryColor = .gray) async throws -> TransactionCategory {
        try repository.edit { try $0.saveCategory(name: name, kind: kind, parentID: parentID, icon: icon, color: color) }
    }
    @discardableResult
    func updateCategory(_ category: TransactionCategory, name: String, parentID: UUID?, icon: String, color: CategoryColor) async throws -> TransactionCategory {
        try repository.edit { try $0.saveCategory(id: category.id, name: name, kind: category.kind, parentID: parentID, icon: icon, color: color) }
    }
    func deleteCategory(_ category: TransactionCategory) async throws { try repository.edit { try $0.deleteCategory(category) } }
    func categorySuggestions(description: String, kind: TransactionKind) async throws -> [CategorySuggestion] { LocalHistoryMatcher.suggestions(description: description, kind: kind, transactions: allTransactions) }
    @discardableResult
    func createTransaction(_ request: TransactionRequest) async throws -> FinanceTransaction { try repository.edit { try $0.saveTransaction(request: request) } }
    @discardableResult
    func updateTransaction(id: UUID, with request: TransactionRequest) async throws -> FinanceTransaction { try repository.edit { try $0.saveTransaction(id: id, request: request) } }
    @discardableResult
    func createTransfer(_ request: TransferRequest) async throws -> TransferResponse { try repository.edit { try $0.transfer(request) } }
    func updateRecurringTransaction(_ transaction: UpcomingTransaction, with request: TransactionRequest) async throws { try repository.edit { try $0.updateUpcoming(transaction, request: request) } }
    func deleteUpcomingTransaction(_ transaction: UpcomingTransaction, action: RecurringDeletionAction) async throws { try repository.edit { try $0.deleteOccurrence(scheduleID: transaction.id, date: transaction.occurredAt, action: action) } }
    func deleteTransaction(_ transaction: FinanceTransaction, action: RecurringDeletionAction = .occurrence) async throws { try repository.edit { try $0.deleteTransaction(transaction, action: action) } }
    func interpretQuickEntry(text: String, defaultAccountID: UUID, locale: String = Locale.current.identifier, timeZone: String = TimeZone.current.identifier, photo: String? = nil, document: ReceiptDocument? = nil, persistReview: Bool = true) async throws -> QuickEntryReviewPresentation {
        let epoch = try repository.value(Int.self, key: "localEpoch") ?? 0
        let response = try await apiClient.interpretQuickEntry(QuickEntryRequest(text: text, defaultAccountId: defaultAccountID, locale: locale, timeZone: timeZone,
            context: QuickEntryLocalContext(accounts: repository.snapshot.sortedAccounts, categories: categories), photo: photo, document: document))
        try Task.checkCancellation()
        guard (try repository.value(Int.self, key: "localEpoch") ?? 0) == epoch else { throw CancellationError() }
        let source: QuickEntryReviewPresentation.Source? = document != nil ? .document : photo != nil ? .photo : nil
        let presentation = QuickEntryReviewPresentation(prompt: document?.filename ?? (photo == nil ? text : "Scanned photo"), drafts: response.transactions.map { payload in QuickEntryDraft(payload: payload, category: categories.first { $0.id == payload.categoryId }) }, source: source)
        if persistReview { try repository.saveValue(presentation, key: "quickEntryReview") }
        // A scan or edits made while the request was running must keep their text.
        if source == nil, quickEntryText.trimmingCharacters(in: .whitespacesAndNewlines) == text.trimmingCharacters(in: .whitespacesAndNewlines) {
            quickEntryText = ""
        }
        return presentation
    }
    @discardableResult
    func commitQuickEntryDrafts(_ drafts: [QuickEntryDraft]) async throws -> Int {
        try repository.edit { editor in
            try saveQuickEntryDrafts(drafts, editor: &editor)
            editor.metadataChanges["quickEntryReview"] = .null
        }
        return drafts.count
    }
    func savedQuickEntryReview() -> QuickEntryReviewPresentation? { try? repository.value(QuickEntryReviewPresentation.self, key: "quickEntryReview") }
    @discardableResult
    func commitScanDraftBatch(_ drafts: [QuickEntryDraft], remainingBatches: [ScanDraftItem]) throws -> Int {
        try repository.edit { editor in
            try saveQuickEntryDrafts(drafts, editor: &editor)
            editor.metadataChanges[ScanDraftStore.metadataKey] = try LocalJSON.value(remainingBatches)
        }
        return drafts.count
    }
    /// Save the entire reviewed file atomically, without touching an unfinished AI review.
    @discardableResult
    func commitCSVImport(_ drafts: [QuickEntryDraft]) async throws -> Int {
        try repository.edit { editor in
            guard !drafts.isEmpty, drafts.count <= TransactionCSV.maximumTransactions else {
                throw LocalDataError(message: "Review between 1 and 5,000 transactions.")
            }
            for draft in drafts {
                guard !draft.isRecurring, draft.mode != .transfer else {
                    throw LocalDataError(message: "CSV rows must be individual expense, income, or debt transactions.")
                }
                let record = try editor.preparedTransaction(id: UUID(), request: TransactionRequest(
                    accountId: draft.accountId, kind: draft.kind, amount: draft.amount, categoryId: draft.category?.id, note: draft.note, occurredAt: draft.occurredAt,
                    debtId: draft.debtId, currency: draft.currency, counterparty: draft.counterparty
                ))
                try editor.put("transaction", key: record.id.uuidString, record)
            }
        }
        return drafts.count
    }
    func saveQuickEntryReview(_ review: QuickEntryReviewPresentation?) throws { try repository.saveValue(review, key: "quickEntryReview") }
    var debtTransactions: [FinanceTransaction] { allTransactions.filter { $0.kind == .debt } }
    func outstandingDebtInCurrency(_ currency: String) -> Decimal? {
        total(debtTransactions.filter { $0.currency.caseInsensitiveCompare(currency) == .orderedSame }, currency: currency, rates: nil, signed: false)
    }
    func outstandingDebt(currency: String, rates: ExchangeRateSnapshot?) -> Decimal? { total(debtTransactions, currency: currency, rates: rates, signed: false) }
    func balance(accountID: UUID?, currency: String, rates: ExchangeRateSnapshot?) -> Decimal? {
        guard var result = total(allTransactions.filter { accountID == nil || $0.accountId == accountID },
                                 currency: currency, rates: rates, signed: true) else { return nil }
        for account in balanceAccounts where accountID == nil || account.id == accountID {
            guard let value = Decimal(string: account.initialBalance, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
            // A zero opening balance never needs an exchange rate.
            if value == 0 { continue }
            guard let converted = account.currency.caseInsensitiveCompare(currency) == .orderedSame
                    ? value : rates?.convert(value, from: account.currency, to: currency) else { return nil }
            result += converted
        }
        return result
    }
    private func total(_ records: [FinanceTransaction], currency: String, rates: ExchangeRateSnapshot?, signed: Bool) -> Decimal? {
        var result = Decimal.zero
        for t in records {
            guard let value = Decimal(string: t.amount, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
            let magnitude = abs(value)
            guard let converted = t.currency.caseInsensitiveCompare(currency) == .orderedSame ? magnitude : rates?.convert(magnitude, from: t.currency, to: currency) else { return nil }
            result += signed && t.kind != .income ? -converted : converted
        }
        return result
    }

    private func saveQuickEntryDrafts(_ drafts: [QuickEntryDraft], editor: inout LocalEditor) throws {
        guard !drafts.isEmpty, drafts.count <= 750 else { throw LocalDataError(message: "Review between 1 and 750 transactions.") }
        for draft in drafts {
            if draft.mode == .transfer {
                guard let destinationID = draft.destinationAccountId else { throw LocalDataError(message: "Choose a destination for every transfer.") }
                guard repository.snapshot.sortedAccounts.first(where: { $0.id == draft.accountId })?.currency == draft.currency else {
                    throw LocalDataError(message: "Review the transfer amount after changing the account currency.")
                }
                _ = try editor.transfer(TransferRequest(fromAccountId: draft.accountId, toAccountId: destinationID, amount: draft.amount, note: draft.note, occurredAt: draft.occurredAt, counterparty: draft.counterparty))
            } else {
                _ = try editor.saveTransaction(request: TransactionRequest(accountId: draft.accountId, kind: draft.kind, amount: draft.amount, categoryId: draft.category?.id, note: draft.note, occurredAt: draft.occurredAt,
                    debtId: draft.debtId, recurrence: draft.isRecurring ? RecurrenceRequest(frequency: draft.recurrenceFrequency, endAt: draft.recurrenceEndAt) : nil, currency: draft.currency, counterparty: draft.counterparty))
            }
        }
    }
#if DEBUG
    static func preview(transactions: [FinanceTransaction], upcomingTransactions: [UpcomingTransaction] = [], accounts: [Account] = []) -> TransactionStore {
        let store = TransactionStore(); store.subscription = nil; store.isPreview = true; store.debts = Array(Dictionary(transactions.compactMap { $0.debt }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }).values); store.transactions = transactions; store.allTransactions = transactions
        store.balanceAccounts = accounts
        store.categories = Array(Set(transactions.compactMap(\.category))); store.upcomingTransactions = upcomingTransactions; store.allUpcomingTransactions = upcomingTransactions; return store
    }
#endif
}
