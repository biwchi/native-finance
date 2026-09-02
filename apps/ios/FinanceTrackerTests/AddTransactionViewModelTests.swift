import XCTest
@testable import FinanceTracker

@MainActor
final class AddTransactionViewModelTests: XCTestCase {
    func testAmountExpressionCalculatesAsKeysAreEntered() {
        var expression = AmountExpression()
        ["1", "2", "+", "4", "*", "3"].forEach { expression.enter($0) }

        XCTAssertEqual(expression.rawValue, "12+4*3")
        XCTAssertEqual(expression.result, 24)
        XCTAssertEqual(expression.canonicalResult, "24")
    }

    func testAmountExpressionHandlesDecimalBackspaceAndTrailingOperator() {
        var expression = AmountExpression()
        ["1", ",", "5", "+", "2", "⌫", "4", "/"].forEach { expression.enter($0) }

        XCTAssertEqual(expression.rawValue, "1.5+4/")
        XCTAssertEqual(expression.result, 5.5)
        XCTAssertEqual(expression.canonicalResult, "5.5")
    }

    func testAmountExpressionRejectsDivisionByZeroAndNonPositiveResults() {
        var divisionByZero = AmountExpression()
        ["8", "/", "0"].forEach { divisionByZero.enter($0) }
        XCTAssertNil(divisionByZero.result)
        XCTAssertNil(divisionByZero.canonicalResult)

        var negative = AmountExpression()
        ["2", "-", "5"].forEach { negative.enter($0) }
        XCTAssertEqual(negative.result, -3)
        XCTAssertNil(negative.canonicalResult)
    }

    func testEditingAmountAppendsDigitsToTheNormalizedStoredValue() {
        var expression = AmountExpression(rawValue: "2000.0000")

        XCTAssertEqual(expression.rawValue, "2000")

        expression.enter("0")

        XCTAssertEqual(expression.rawValue, "20000")
        XCTAssertEqual(expression.canonicalResult, "20000")

        expression.enter("4")

        XCTAssertEqual(expression.rawValue, "200004")
        XCTAssertEqual(expression.canonicalResult, "200004")
    }

    func testEditingAmountAddsDecimalPlacesToTheStoredValue() {
        for separator in [".", ","] {
            var expression = AmountExpression(rawValue: "2000.0000")

            expression.enter(separator)

            XCTAssertEqual(expression.rawValue, "2000.")
            XCTAssertEqual(expression.canonicalResult, "2000")

            expression.enter("5")

            XCTAssertEqual(expression.rawValue, "2000.5")
            XCTAssertEqual(expression.canonicalResult, "2000.5")
        }
    }

    func testEditingFractionalAmountPreservesExistingDecimalPlaces() {
        var expression = AmountExpression(rawValue: "12.5000")

        expression.enter(",")
        XCTAssertEqual(expression.rawValue, "12.5")

        expression.enter("9")
        XCTAssertEqual(expression.rawValue, "12.59")
        XCTAssertEqual(expression.canonicalResult, "12.59")
    }

    func testEditingAmountCanDeleteOrCalculateFromInitialValue() {
        var edited = AmountExpression(rawValue: "12.5000")
        edited.enter("⌫")
        edited.enter("9")
        XCTAssertEqual(edited.rawValue, "12.9")

        var calculated = AmountExpression(rawValue: "12.5000")
        calculated.enter("+")
        calculated.enter("2")
        XCTAssertEqual(calculated.rawValue, "12.5+2")
        XCTAssertEqual(calculated.canonicalResult, "14.5")
    }

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
        XCTAssertEqual(viewModel.note, transaction.note)
        XCTAssertEqual(viewModel.occurredAt, transaction.occurredAt)
        XCTAssertTrue(viewModel.isRecurring)
        XCTAssertEqual(viewModel.recurrenceFrequency, .weekly)
        XCTAssertNil(viewModel.recurrenceEndAt)
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
        try await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertNil(viewModel.categoryID)
        XCTAssertEqual(viewModel.categorySource, .manual)
        XCTAssertFalse(viewModel.isResolvingCategory)
    }

    func testRecurringSettingsAreTrackedAsEdits() {
        let transaction = Self.transaction(accountID: UUID(), category: nil)
        let viewModel = AddTransactionViewModel(transaction: transaction)

        XCTAssertFalse(viewModel.hasChanges(from: transaction))

        viewModel.setRecurrenceFrequency(.daily)
        XCTAssertTrue(viewModel.hasChanges(from: transaction))

        viewModel.setRecurrenceFrequency(.weekly)
        XCTAssertFalse(viewModel.hasChanges(from: transaction))

        viewModel.setRecurring(false)
        XCTAssertTrue(viewModel.hasChanges(from: transaction))
    }

    func testManualFieldsAreNotOverwrittenByLaterCommands() {
        let viewModel = AddTransactionViewModel(
            resolver: StubCategoryResolver { _, _, _ in nil },
            now: { Self.fixedDate }
        )

        viewModel.setCommand("12 coffee", categories: [], currencyCode: "USD")
        viewModel.setAmountText("99.25")
        viewModel.setNote("team lunch")
        viewModel.setOccurredAt(Self.manualDate)
        viewModel.setKind(.income, categories: [])

        viewModel.setCommand("40 gas yesterday", categories: [], currencyCode: "USD")

        XCTAssertEqual(viewModel.amountText, "99.25")
        XCTAssertEqual(viewModel.note, "team lunch")
        XCTAssertEqual(viewModel.occurredAt, Self.manualDate)
        XCTAssertEqual(viewModel.kind, .income)
        XCTAssertEqual(viewModel.amountSource, .manual)
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
            category: category, note: "Saved note",
            occurredAt: manualDate, createdAt: fixedDate, updatedAt: fixedDate,
            recurrence: TransactionRecurrence(id: UUID(), frequency: .weekly, endAt: nil)
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
