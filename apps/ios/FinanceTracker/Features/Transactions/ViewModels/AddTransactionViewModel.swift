import Combine
import Foundation

@MainActor
final class AddTransactionViewModel: ObservableObject {
    @Published private(set) var command = ""
    @Published private(set) var accountID: UUID?
    @Published private(set) var amountText = ""
    @Published private(set) var kind: TransactionKind = .expense
    @Published private(set) var categoryID: UUID?
    @Published private(set) var merchant = ""
    @Published private(set) var payee = ""
    @Published private(set) var note = ""
    @Published private(set) var occurredAt: Date
    @Published private(set) var isRecurring = false
    @Published private(set) var recurrenceFrequency: RecurrenceFrequency = .monthly
    @Published private(set) var recurrenceEndAt: Date?
    @Published private(set) var amountConflict = false
    @Published private(set) var dateConflict = false
    @Published private(set) var isResolvingCategory = false
    @Published private(set) var categoryResolutionSource: CategoryResolutionSource?

    @Published private(set) var amountSource: DraftFieldSource = .defaultValue
    @Published private(set) var kindSource: DraftFieldSource = .defaultValue
    @Published private(set) var categorySource: DraftFieldSource = .defaultValue
    @Published private(set) var dateSource: DraftFieldSource = .defaultValue

    private let parser: TransactionCommandParser
    private let resolver: any CategoryResolving
    private let now: () -> Date
    private var categoryTask: Task<Void, Never>?
    private var commandRevision = 0
    private var hasConfiguredAccount = false
    private var categoryQuery = ""

    init(
        transaction: (any EditableTransaction)? = nil,
        parser: TransactionCommandParser = TransactionCommandParser(),
        resolver: any CategoryResolving = AdaptiveCategoryResolver(),
        now: @escaping () -> Date = Date.init
    ) {
        self.parser = parser
        self.resolver = resolver
        self.now = now
        occurredAt = transaction?.occurredAt ?? now()

        if let transaction {
            accountID = transaction.accountId
            amountText = Decimal(string: transaction.amount, locale: Locale(identifier: "en_US_POSIX"))
                .map { NSDecimalNumber(decimal: $0).stringValue } ?? transaction.amount
            kind = transaction.kind
            categoryID = transaction.category?.id
            merchant = transaction.merchant ?? ""
            payee = transaction.payee ?? ""
            note = transaction.note ?? ""
            isRecurring = transaction.recurrence != nil
            recurrenceFrequency = transaction.recurrence?.frequency ?? .monthly
            recurrenceEndAt = transaction.recurrence?.endAt
            hasConfiguredAccount = true
            amountSource = .manual
            kindSource = .manual
            categorySource = .manual
            dateSource = .manual
        }
    }

    deinit {
        categoryTask?.cancel()
    }

    func configureAccount(
        selectedAccountID: UUID?,
        lastUsedAccountID: UUID?,
        accounts: [Account]
    ) {
        guard !hasConfiguredAccount else { return }
        hasConfiguredAccount = true

        if let selectedAccountID,
           accounts.contains(where: { $0.id == selectedAccountID }) {
            accountID = selectedAccountID
        } else if let lastUsedAccountID,
                  accounts.contains(where: { $0.id == lastUsedAccountID }) {
            accountID = lastUsedAccountID
        }
    }

    func setCommand(
        _ value: String,
        categories: [TransactionCategory],
        currencyCode: String?
    ) {
        command = value
        commandRevision += 1

        let result = parser.parse(
            value,
            context: TransactionCommandContext(
                now: now(),
                currencyCode: currencyCode
            )
        )

        amountConflict = result.amountConflict
        dateConflict = result.dateConflict

        if amountSource != .manual {
            if let amount = result.amount {
                amountText = NSDecimalNumber(decimal: amount).stringValue
                amountSource = .inferred
            } else {
                amountText = ""
                amountSource = .defaultValue
            }
        }

        if kindSource != .manual {
            kind = result.kind
            kindSource = result.amount == nil ? .defaultValue : .inferred
        }

        categoryQuery = result.description

        if dateSource != .manual {
            if let parsedDate = result.occurredAt {
                occurredAt = parsedDate
                dateSource = .inferred
            } else if !result.dateConflict {
                occurredAt = now()
                dateSource = .defaultValue
            }
        }

        if categorySource != .manual {
            categoryID = nil
            categorySource = .defaultValue
            categoryResolutionSource = nil
        }
        scheduleCategoryResolution(categories: categories)
    }

    func setAccountID(_ value: UUID?) {
        accountID = value
    }

    func setAmountText(_ value: String) {
        amountText = value
        amountSource = .manual
        amountConflict = false
    }

    func setKind(_ value: TransactionKind, categories: [TransactionCategory]) {
        kind = value
        kindSource = .manual

        if let categoryID,
           categories.first(where: { $0.id == categoryID })?.kind != value {
            self.categoryID = nil
            categorySource = .defaultValue
            categoryResolutionSource = nil
        }
        scheduleCategoryResolution(categories: categories)
    }

    func setCategoryID(_ value: UUID?) {
        categoryTask?.cancel()
        isResolvingCategory = false
        categoryID = value
        categorySource = .manual
        categoryResolutionSource = nil
    }

    func setMerchant(_ value: String) {
        merchant = value
    }

    func setPayee(_ value: String) {
        payee = value
    }

    func setNote(_ value: String) {
        note = value
    }

    func setOccurredAt(_ value: Date) {
        occurredAt = value
        dateSource = .manual
        dateConflict = false
    }

    func setRecurring(_ value: Bool) {
        isRecurring = value
        if !value {
            recurrenceEndAt = nil
        }
    }

    func setRecurrenceFrequency(_ value: RecurrenceFrequency) {
        recurrenceFrequency = value
    }

    func setRecurrenceEndAt(_ value: Date?) {
        recurrenceEndAt = value
    }

    func refreshCategoryResolution(categories: [TransactionCategory]) {
        guard categorySource != .manual else { return }
        scheduleCategoryResolution(categories: categories)
    }

    func canonicalAmount() -> String? {
        // The keypad and command parser supply canonical dot-decimal strings.
        canonicalTransactionAmount(amountText, locale: Locale(identifier: "en_US_POSIX"))
    }

    var canSave: Bool {
        accountID != nil &&
            canonicalAmount() != nil &&
            !amountConflict &&
            !dateConflict
    }

    func hasChanges(from transaction: any EditableTransaction) -> Bool {
        accountID != transaction.accountId ||
            canonicalAmount().flatMap { Decimal(string: $0) } != Decimal(string: transaction.amount) ||
            kind != transaction.kind ||
            categoryID != transaction.category?.id ||
            merchant.trimmingCharacters(in: .whitespacesAndNewlines) != (transaction.merchant ?? "") ||
            payee.trimmingCharacters(in: .whitespacesAndNewlines) != (transaction.payee ?? "") ||
            note.trimmingCharacters(in: .whitespacesAndNewlines) != (transaction.note ?? "") ||
            occurredAt != transaction.occurredAt ||
            isRecurring != (transaction.recurrence != nil) ||
            isRecurring && (
                recurrenceFrequency != transaction.recurrence?.frequency ||
                    recurrenceEndAt != transaction.recurrence?.endAt
            )
    }

    private func scheduleCategoryResolution(categories: [TransactionCategory]) {
        categoryTask?.cancel()
        isResolvingCategory = false

        guard
            categorySource != .manual,
            categoryQuery.contains(where: \.isLetter),
            categoryQuery.filter(\.isLetter).count >= 2
        else {
            return
        }

        let revision = commandRevision
        let description = categoryQuery
        let kind = kind
        let availableCategories = categories.filter { $0.kind == kind }
        guard !availableCategories.isEmpty else { return }

        isResolvingCategory = true
        categoryTask = Task { [weak self, resolver] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            let resolution = await resolver.resolve(
                description: description,
                kind: kind,
                categories: availableCategories
            )
            guard !Task.isCancelled, let self else { return }

            isResolvingCategory = false
            guard
                commandRevision == revision,
                categorySource != .manual,
                categoryQuery == description,
                self.kind == kind
            else {
                return
            }

            categoryID = resolution?.categoryID
            categorySource = resolution == nil ? .defaultValue : .inferred
            categoryResolutionSource = resolution?.source
        }
    }
}
