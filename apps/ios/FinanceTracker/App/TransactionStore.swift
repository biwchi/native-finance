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
    private let repository: LocalFinanceRepository
    private let apiClient: APIClient
    private var currentAccountID: UUID?
    private var isPreview = false
    private var subscription: AnyCancellable?
    init(apiClient: APIClient = APIClient(), repository: LocalFinanceRepository? = nil) {
        self.apiClient = apiClient; self.repository = repository ?? .shared
        apply(self.repository.snapshot)
        subscription = self.repository.$snapshot.sink { [weak self] in self?.apply($0) }
    }
    private func apply(_ snapshot: LocalSnapshot) {
        allTransactions = snapshot.detailedTransactions
        transactions = allTransactions.filter { currentAccountID == nil || $0.accountId == currentAccountID }
        categories = Array(snapshot.categories.values)
        debts = snapshot.debts.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
    func interpretQuickEntry(text: String, defaultAccountID: UUID, locale: String = Locale.current.identifier, timeZone: String = TimeZone.current.identifier) async throws -> QuickEntryReviewPresentation {
        try repository.saveValue(text, key: "quickEntryText")
        let epoch = try repository.value(Int.self, key: "localEpoch") ?? 0
        let response = try await apiClient.interpretQuickEntry(QuickEntryRequest(text: text, defaultAccountId: defaultAccountID, locale: locale, timeZone: timeZone,
            context: QuickEntryLocalContext(accounts: repository.snapshot.sortedAccounts, categories: categories)))
        guard (try repository.value(Int.self, key: "localEpoch") ?? 0) == epoch else { throw CancellationError() }
        let presentation = QuickEntryReviewPresentation(prompt: text, drafts: response.transactions.map { payload in QuickEntryDraft(payload: payload, category: categories.first { $0.id == payload.categoryId }) }, unparsedText: response.unparsedText)
        try repository.saveValue(presentation, key: "quickEntryReview"); return presentation
    }
    @discardableResult
    func commitQuickEntryDrafts(_ drafts: [QuickEntryDraft]) async throws -> Int {
        try repository.edit { editor in
            guard !drafts.isEmpty, drafts.count <= 100 else { throw LocalDataError(message: "Review between 1 and 100 transactions.") }
            for draft in drafts {
                if draft.mode == .transfer {
                    guard let destinationID = draft.destinationAccountId else { throw LocalDataError(message: "Choose a destination for every transfer.") }
                    _ = try editor.transfer(TransferRequest(fromAccountId: draft.accountId, toAccountId: destinationID, amount: draft.amount, merchant: draft.merchant, payee: draft.payee, note: draft.note, occurredAt: draft.occurredAt))
                } else {
                    _ = try editor.saveTransaction(request: TransactionRequest(accountId: draft.accountId, kind: draft.kind, amount: draft.amount, categoryId: draft.category?.id,
                        merchant: draft.merchant, payee: draft.payee, note: draft.note, occurredAt: draft.occurredAt,
                        recurrence: draft.isRecurring ? RecurrenceRequest(frequency: draft.recurrenceFrequency, endAt: draft.recurrenceEndAt) : nil))
                }
            }
            editor.metadataChanges["quickEntryReview"] = .null
            editor.metadataChanges["quickEntryText"] = .string("")
        }
        return drafts.count
    }
    func savedQuickEntryText() -> String { (try? repository.value(String.self, key: "quickEntryText")) ?? "" }
    func savedQuickEntryReview() -> QuickEntryReviewPresentation? { try? repository.value(QuickEntryReviewPresentation.self, key: "quickEntryReview") }
    func saveQuickEntryText(_ text: String) throws { try repository.saveValue(text, key: "quickEntryText") }
    func saveQuickEntryReview(_ review: QuickEntryReviewPresentation?) throws { try repository.saveValue(review, key: "quickEntryReview") }
    var debtTransactions: [FinanceTransaction] { allTransactions.filter { $0.kind == .debt } }
    func outstandingDebtInCurrency(_ currency: String) -> Decimal? {
        total(debtTransactions.filter { $0.currency.caseInsensitiveCompare(currency) == .orderedSame }, currency: currency, rates: nil, signed: false)
    }
    func outstandingDebt(currency: String, rates: ExchangeRateSnapshot?) -> Decimal? { total(debtTransactions, currency: currency, rates: rates, signed: false) }
    func balance(accountID: UUID?, currency: String, rates: ExchangeRateSnapshot?) -> Decimal? { total(allTransactions.filter { accountID == nil || $0.accountId == accountID }, currency: currency, rates: rates, signed: true) }
    private func total(_ records: [FinanceTransaction], currency: String, rates: ExchangeRateSnapshot?, signed: Bool) -> Decimal? {
        var result = Decimal.zero
        for t in records {
            guard let value = Decimal(string: t.amount, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
            guard let converted = t.currency.caseInsensitiveCompare(currency) == .orderedSame ? value : rates?.convert(value, from: t.currency, to: currency) else { return nil }
            result += signed && t.kind != .income ? -converted : converted
        }
        return result
    }
#if DEBUG
    static func preview(transactions: [FinanceTransaction], upcomingTransactions: [UpcomingTransaction] = []) -> TransactionStore {
        let store = TransactionStore(); store.subscription = nil; store.isPreview = true; store.debts = Array(Dictionary(transactions.compactMap { $0.debt }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }).values); store.transactions = transactions; store.allTransactions = transactions
        store.categories = Array(Set(transactions.compactMap(\.category))); store.upcomingTransactions = upcomingTransactions; store.allUpcomingTransactions = upcomingTransactions; return store
    }
#endif
}
