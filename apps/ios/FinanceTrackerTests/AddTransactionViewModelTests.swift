import XCTest
@testable import FinanceTracker

@MainActor
final class AddTransactionViewModelTests: XCTestCase {
    func testEditingPrefillsAndPreservesSavedFieldsWhileAccountsAndCategoriesLoad() {
        let account = Self.account(name: "Original account")
        let otherAccount = Self.account(name: "Selected account")
        let category = Self.category(name: "Food & Drink", key: "expense.food-drink", kind: .expense)
        let transaction = Self.transaction(accountID: account.id, category: category)
        let viewModel = AddTransactionViewModel(transaction: transaction)

        viewModel.configureAccount(
            selectedAccountID: otherAccount.id,
            lastUsedAccountID: otherAccount.id,
            accounts: [account, otherAccount]
        )
        viewModel.refreshCategoryResolution(categories: [category])

        XCTAssertEqual(viewModel.accountID, transaction.accountId)
        XCTAssertEqual(viewModel.canonicalAmount(), "12.5")
        XCTAssertEqual(viewModel.kind, transaction.kind)
        XCTAssertEqual(viewModel.categoryID, category.id)
        XCTAssertEqual(viewModel.description, transaction.description)
        XCTAssertEqual(viewModel.note, transaction.note)
        XCTAssertEqual(viewModel.occurredAt, transaction.occurredAt)
        XCTAssertFalse(viewModel.isResolvingCategory)
        XCTAssertTrue(viewModel.canSave)
        XCTAssertFalse(viewModel.hasChanges(from: transaction))

        viewModel.setAmountText("12.50")
        XCTAssertFalse(viewModel.hasChanges(from: transaction))
        viewModel.setNote("Updated note")
        XCTAssertTrue(viewModel.hasChanges(from: transaction))
        viewModel.setNote(transaction.note!)
        XCTAssertFalse(viewModel.hasChanges(from: transaction))
        viewModel.setCategoryID(nil)
        XCTAssertTrue(viewModel.hasChanges(from: transaction))
    }

    func testEditingAnUncategorizedTransactionDoesNotInferACategory() async throws {
        let category = Self.category(name: "Food & Drink", key: "expense.food-drink", kind: .expense)
        let transaction = Self.transaction(accountID: UUID(), category: nil)
        let viewModel = AddTransactionViewModel(
            transaction: transaction,
            resolver: StubCategoryResolver { _, _, _ in
                CategoryResolution(categoryID: category.id, confidence: 1, source: .seed)
            }
        )
        viewModel.refreshCategoryResolution(categories: [category])
        viewModel.setDescription("Coffee", categories: [category])
        try await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertNil(viewModel.categoryID)
        XCTAssertEqual(viewModel.categorySource, .manual)
        XCTAssertFalse(viewModel.isResolvingCategory)
    }

    func testManualFieldsAreNotOverwrittenByLaterCommands() {
        let viewModel = AddTransactionViewModel(
            resolver: StubCategoryResolver { _, _, _ in nil },
            now: { Self.fixedDate }
        )

        viewModel.setCommand("12 coffee", categories: [], currencyCode: "USD")
        viewModel.setAmountText("99.25")
        viewModel.setDescription("team lunch", categories: [])
        viewModel.setOccurredAt(Self.manualDate)
        viewModel.setKind(.income, categories: [])

        viewModel.setCommand("40 gas yesterday", categories: [], currencyCode: "USD")

        XCTAssertEqual(viewModel.amountText, "99.25")
        XCTAssertEqual(viewModel.description, "team lunch")
        XCTAssertEqual(viewModel.occurredAt, Self.manualDate)
        XCTAssertEqual(viewModel.kind, .income)
        XCTAssertEqual(viewModel.amountSource, .manual)
        XCTAssertEqual(viewModel.descriptionSource, .manual)
        XCTAssertEqual(viewModel.dateSource, .manual)
        XCTAssertEqual(viewModel.kindSource, .manual)
    }

    func testManualCategorySurvivesAnInFlightSuggestion() async throws {
        let food = Self.category(name: "Food & Drink", key: "expense.food-drink", kind: .expense)
        let custom = Self.category(name: "Office", key: nil, kind: .expense, isSystem: false)
        let resolver = StubCategoryResolver { _, _, _ in
            try? await Task.sleep(nanoseconds: 150_000_000)
            return CategoryResolution(categoryID: food.id, confidence: 1, source: .seed)
        }
        let viewModel = AddTransactionViewModel(resolver: resolver, now: { Self.fixedDate })

        viewModel.setCommand("12 coffee", categories: [food, custom], currencyCode: "USD")
        viewModel.setCategoryID(custom.id)
        try await Task.sleep(nanoseconds: 600_000_000)

        XCTAssertEqual(viewModel.categoryID, custom.id)
        XCTAssertEqual(viewModel.categorySource, .manual)
        XCTAssertNil(viewModel.categoryResolutionSource)
    }

    func testStaleCategoryResultCannotReplaceLatestCommand() async throws {
        let food = Self.category(name: "Food & Drink", key: "expense.food-drink", kind: .expense)
        let fuel = Self.category(name: "Fuel", key: "expense.fuel", kind: .expense)
        let resolver = StubCategoryResolver { description, _, _ in
            if description == "coffee" {
                try? await Task.sleep(nanoseconds: 500_000_000)
                return CategoryResolution(categoryID: food.id, confidence: 1, source: .seed)
            }

            try? await Task.sleep(nanoseconds: 10_000_000)
            return CategoryResolution(categoryID: fuel.id, confidence: 1, source: .seed)
        }
        let viewModel = AddTransactionViewModel(resolver: resolver, now: { Self.fixedDate })

        viewModel.setCommand("12 coffee", categories: [food, fuel], currencyCode: "USD")
        try await Task.sleep(nanoseconds: 350_000_000)
        viewModel.setCommand("40 gas", categories: [food, fuel], currencyCode: "USD")
        try await Task.sleep(nanoseconds: 700_000_000)

        XCTAssertEqual(viewModel.categoryID, fuel.id)
        XCTAssertEqual(viewModel.categorySource, .inferred)
        XCTAssertEqual(viewModel.categoryResolutionSource, .seed)
        XCTAssertFalse(viewModel.isResolvingCategory)
    }

    func testSelectedAccountWinsThenLastUsedIsFallback() {
        let first = Self.account(name: "Cash")
        let second = Self.account(name: "Card")

        let selectedViewModel = AddTransactionViewModel(
            resolver: StubCategoryResolver { _, _, _ in nil }
        )
        selectedViewModel.configureAccount(
            selectedAccountID: second.id,
            lastUsedAccountID: first.id,
            accounts: [first, second]
        )

        let fallbackViewModel = AddTransactionViewModel(
            resolver: StubCategoryResolver { _, _, _ in nil }
        )
        fallbackViewModel.configureAccount(
            selectedAccountID: UUID(),
            lastUsedAccountID: first.id,
            accounts: [first, second]
        )

        XCTAssertEqual(selectedViewModel.accountID, second.id)
        XCTAssertEqual(fallbackViewModel.accountID, first.id)
    }

    func testSavingRequiresOnlyAccountAndPositiveUnambiguousAmount() {
        let account = Self.account(name: "Cash")
        let viewModel = AddTransactionViewModel(
            resolver: StubCategoryResolver { _, _, _ in nil },
            now: { Self.fixedDate }
        )

        viewModel.configureAccount(
            selectedAccountID: account.id,
            lastUsedAccountID: nil,
            accounts: [account]
        )
        viewModel.setCommand("12.50", categories: [], currencyCode: "USD")
        XCTAssertTrue(viewModel.canSave)

        viewModel.setCommand("12 coffee and 4 tip", categories: [], currencyCode: "USD")
        XCTAssertFalse(viewModel.canSave)

        viewModel.setAmountText("16.50")
        XCTAssertTrue(viewModel.canSave)
    }

    private static let fixedDate: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 12))!
    }()

    private static func transaction(accountID: UUID, category: TransactionCategory?) -> FinanceTransaction {
        FinanceTransaction(
            id: UUID(), accountId: accountID, kind: .expense, amount: "12.5000", currency: "USD",
            category: category, description: "Coffee", note: "Saved note",
            occurredAt: manualDate, createdAt: fixedDate, updatedAt: fixedDate
        )
    }

    private static let manualDate: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 9))!
    }()

    private static func category(
        name: String,
        key: String?,
        kind: TransactionKind,
        isSystem: Bool = true
    ) -> TransactionCategory {
        TransactionCategory(
            id: UUID(),
            systemKey: key,
            name: name,
            kind: kind,
            isSystem: isSystem,
            examples: [name],
            sortOrder: 10,
            createdAt: nil,
            updatedAt: nil
        )
    }

    private static func account(name: String) -> Account {
        Account(
            id: UUID(),
            name: name,
            type: .cash,
            currency: "USD",
            icon: "banknote.fill",
            iconColor: .green,
            createdAt: "2026-08-31T00:00:00Z",
            updatedAt: "2026-08-31T00:00:00Z"
        )
    }
}

private struct StubCategoryResolver: CategoryResolving {
    let handler: (String, TransactionKind, [TransactionCategory]) async -> CategoryResolution?

    init(
        _ handler: @escaping (String, TransactionKind, [TransactionCategory]) async -> CategoryResolution?
    ) {
        self.handler = handler
    }

    func resolve(
        description: String,
        kind: TransactionKind,
        categories: [TransactionCategory]
    ) async -> CategoryResolution? {
        await handler(description, kind, categories)
    }
}
