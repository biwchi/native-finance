import Combine
import Foundation

enum DraftFieldSource: Equatable {
    case defaultValue
    case inferred
    case manual

    var isSuggested: Bool { self == .inferred }
}

@MainActor
final class AddTransactionViewModel: ObservableObject {
    @Published private(set) var command = ""
    @Published private(set) var accountID: UUID?
    @Published private(set) var amountText = ""
    @Published private(set) var kind: TransactionKind = .expense
    @Published private(set) var categoryID: UUID?
    @Published private(set) var description = ""
    @Published private(set) var note = ""
    @Published private(set) var occurredAt: Date
    @Published private(set) var amountConflict = false
    @Published private(set) var dateConflict = false
    @Published private(set) var isResolvingCategory = false
    @Published private(set) var categoryResolutionSource: CategoryResolutionSource?

    @Published private(set) var amountSource: DraftFieldSource = .defaultValue
    @Published private(set) var kindSource: DraftFieldSource = .defaultValue
    @Published private(set) var categorySource: DraftFieldSource = .defaultValue
    @Published private(set) var descriptionSource: DraftFieldSource = .defaultValue
    @Published private(set) var dateSource: DraftFieldSource = .defaultValue

    private let parser: TransactionCommandParser
    private let resolver: any CategoryResolving
    private let now: () -> Date
    private var categoryTask: Task<Void, Never>?
    private var commandRevision = 0
    private var hasConfiguredAccount = false

    init(
        parser: TransactionCommandParser = TransactionCommandParser(),
        resolver: any CategoryResolving = AdaptiveCategoryResolver(),
        now: @escaping () -> Date = Date.init
    ) {
        self.parser = parser
        self.resolver = resolver
        self.now = now
        occurredAt = now()
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

        if descriptionSource != .manual {
            description = result.description
            descriptionSource = result.description.isEmpty ? .defaultValue : .inferred
        }

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

    func setDescription(_ value: String, categories: [TransactionCategory]) {
        description = value
        descriptionSource = .manual
        if categorySource != .manual {
            categoryID = nil
            categorySource = .defaultValue
            categoryResolutionSource = nil
        }
        scheduleCategoryResolution(categories: categories)
    }

    func setNote(_ value: String) {
        note = value
    }

    func setOccurredAt(_ value: Date) {
        occurredAt = value
        dateSource = .manual
        dateConflict = false
    }

    func refreshCategoryResolution(categories: [TransactionCategory]) {
        guard categorySource != .manual else { return }
        scheduleCategoryResolution(categories: categories)
    }

    func selectCreatedCategory(_ category: TransactionCategory) {
        categoryTask?.cancel()
        isResolvingCategory = false
        categoryID = category.id
        categorySource = .manual
        categoryResolutionSource = nil
    }

    func canonicalAmount(locale: Locale = .autoupdatingCurrent) -> String? {
        canonicalTransactionAmount(amountText, locale: locale)
    }

    var canSave: Bool {
        accountID != nil &&
            canonicalAmount() != nil &&
            !amountConflict &&
            !dateConflict
    }

    private func scheduleCategoryResolution(categories: [TransactionCategory]) {
        categoryTask?.cancel()
        isResolvingCategory = false

        guard
            categorySource != .manual,
            description.contains(where: \.isLetter),
            description.filter(\.isLetter).count >= 2
        else {
            return
        }

        let revision = commandRevision
        let description = description
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
                self.description == description,
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
