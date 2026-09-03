import XCTest
@testable import FinanceTracker

@MainActor
final class TransactionStoreTests: XCTestCase {
    func testCategoryIconCatalogHasRichDistinctGroups() {
        XCTAssertEqual(CategoryIconCatalog.groups.count, 11)
        XCTAssertTrue(CategoryIconCatalog.groups.allSatisfy { $0.icons.count >= 16 })
        XCTAssertEqual(Set(CategoryIconCatalog.choices).count, CategoryIconCatalog.choices.count)
    }

    func testExtendedCategoryColorsUseStableAPINames() throws {
        let colors: [(CategoryColor, String)] = [
            (.coral, "coral"),
            (.amber, "amber"),
            (.lime, "lime"),
            (.turquoise, "turquoise"),
            (.sky, "sky"),
            (.navy, "navy"),
            (.violet, "violet"),
            (.lavender, "lavender"),
            (.rose, "rose"),
            (.slate, "slate"),
        ]
        let encoder = JSONEncoder()

        for (color, expectedName) in colors {
            let encoded = try encoder.encode(color)
            XCTAssertEqual(String(decoding: encoded, as: UTF8.self), "\"\(expectedName)\"")
        }
    }

    func testTransactionRequestEncodesRecurrenceWithoutDescription() throws {
        let endAt = Date(timeIntervalSince1970: 1_800_000_000)
        let request = TransactionRequest(
            accountId: UUID(),
            kind: .expense,
            amount: "12.5",
            categoryId: nil,
            note: "Rent",
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
            recurrence: RecurrenceRequest(frequency: .monthly, endAt: endAt)
        )

        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let recurrence = try XCTUnwrap(json["recurrence"] as? [String: Any])

        XCTAssertNil(json["description"])
        XCTAssertEqual(json["note"] as? String, "Rent")
        XCTAssertEqual(recurrence["frequency"] as? String, "monthly")
        XCTAssertNotNil(recurrence["endAt"])
    }

    func testCategoryAppearanceIsSentWhenCreatingAndEditing() async throws {
        let parentID = UUID()
        let createdCategory = category(
            parentID: parentID,
            icon: "cup.and.saucer.fill",
            color: .orange
        )
        let editedCategory = category(
            id: createdCategory.id,
            name: "Coffee runs",
            icon: "mug.fill",
            color: .brown
        )
        let session = makeSession { request in
            let body = try XCTUnwrap(requestBody(request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

            switch request.httpMethod {
            case "POST":
                XCTAssertEqual(json["name"] as? String, "Coffee")
                XCTAssertEqual(json["kind"] as? String, "expense")
                XCTAssertEqual(json["parentId"] as? String, parentID.uuidString)
                XCTAssertEqual(json["icon"] as? String, "cup.and.saucer.fill")
                XCTAssertEqual(json["color"] as? String, "orange")
                return (201, try self.encode(createdCategory))
            case "PATCH":
                XCTAssertEqual(request.url?.lastPathComponent, createdCategory.id.uuidString)
                XCTAssertEqual(json["name"] as? String, "Coffee runs")
                XCTAssertTrue(json["parentId"] is NSNull)
                XCTAssertEqual(json["icon"] as? String, "mug.fill")
                XCTAssertEqual(json["color"] as? String, "brown")
                return (200, try self.encode(editedCategory))
            default:
                XCTFail("Unexpected request method")
                return (405, Data())
            }
        }
        defer { session.invalidateAndCancel() }

        let store = TransactionStore(
            apiClient: APIClient(baseURL: URL(string: "https://test.invalid")!, session: session)
        )
        let created = try await store.createCategory(
            name: "Coffee",
            kind: .expense,
            parentID: parentID,
            icon: "cup.and.saucer.fill",
            color: .orange
        )
        let edited = try await store.updateCategory(
            created,
            name: "Coffee runs",
            parentID: nil,
            icon: "mug.fill",
            color: .brown
        )

        XCTAssertEqual(edited, editedCategory)
        XCTAssertEqual(store.categories, [editedCategory])
    }

    func testUpdateReplacesAndReordersTheExistingTransactionWithoutDuplicates() async throws {
        let accountID = UUID()
        let original = transaction(accountID: accountID, occurredAt: Date(timeIntervalSince1970: 1_700_000_000))
        let newer = transaction(accountID: accountID, occurredAt: Date(timeIntervalSince1970: 1_700_001_000))
        let edited = transaction(id: original.id, accountID: accountID, occurredAt: Date(timeIntervalSince1970: 1_700_002_000.123))
        let session = makeSession { request in
            if request.url?.lastPathComponent == "upcoming" {
                return (200, Data("[]".utf8))
            }
            if request.httpMethod == "GET" {
                return (200, try self.encode([newer, original]))
            }
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.url?.lastPathComponent, original.id.uuidString)
            let body = try XCTUnwrap(requestBody(request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["occurredAt"] as? String, "2023-11-14T22:46:40.123Z")
            XCTAssertNil(json["categoryId"])
            XCTAssertNil(json["description"])
            XCTAssertNil(json["note"])
            return (200, try self.encode(edited))
        }
        defer { session.invalidateAndCancel() }
        let store = TransactionStore(apiClient: APIClient(baseURL: URL(string: "https://test.invalid")!, session: session))
        await store.loadTransactions(accountID: nil)
        try await store.updateTransaction(id: original.id, with: draft(edited))

        XCTAssertEqual(store.transactions, [edited, newer])
        XCTAssertEqual(store.state, .loaded)
    }

    func testMovingTransactionOutOfSelectedAccountRemovesItsRow() async throws {
        let accountID = UUID()
        let original = transaction(accountID: accountID)
        let moved = transaction(id: original.id, accountID: UUID())
        let session = makeSession { request in
            if request.url?.lastPathComponent == "upcoming" {
                return (200, Data("[]".utf8))
            }
            if request.httpMethod == "GET" {
                XCTAssertNil(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems)
                return (200, try self.encode([original]))
            }
            return (200, try self.encode(moved))
        }
        defer { session.invalidateAndCancel() }
        let store = TransactionStore(apiClient: APIClient(baseURL: URL(string: "https://test.invalid")!, session: session))
        await store.loadTransactions(accountID: accountID)
        try await store.updateTransaction(id: original.id, with: draft(moved))

        XCTAssertTrue(store.transactions.isEmpty)
        XCTAssertEqual(store.allTransactions, [moved])
        XCTAssertEqual(store.balance(accountID: accountID, currency: "USD", rates: nil), 0)
        XCTAssertEqual(store.balance(accountID: moved.accountId, currency: "USD", rates: nil), Decimal(string: "-12.5"))
        XCTAssertEqual(store.state, .loaded)
    }

    func testFailedSaveLeavesOriginalTransactionUntouched() async throws {
        let original = transaction(accountID: UUID())
        let session = makeSession { request in
            if request.url?.lastPathComponent == "upcoming" {
                return (200, Data("[]".utf8))
            }
            if request.httpMethod == "GET" {
                return (200, try self.encode([original]))
            }
            return (500, Data(#"{"message":"Could not save changes"}"#.utf8))
        }
        defer { session.invalidateAndCancel() }
        let store = TransactionStore(apiClient: APIClient(baseURL: URL(string: "https://test.invalid")!, session: session))
        await store.loadTransactions(accountID: nil)

        do {
            try await store.updateTransaction(id: original.id, with: draft(original))
            XCTFail("Expected the update to fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Could not save changes")
        }
        XCTAssertEqual(store.transactions, [original])
    }

    func testDeleteRemovesTransactionAfterServerSuccess() async throws {
        let transaction = transaction(accountID: UUID())
        let session = makeSession { request in
            if request.url?.lastPathComponent == "upcoming" {
                return (200, Data("[]".utf8))
            }
            if request.httpMethod == "GET" {
                return (200, try self.encode([transaction]))
            }
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/api/v1/transactions/\(transaction.id.uuidString)")
            return (200, Data(#"{"deleted":true}"#.utf8))
        }
        defer { session.invalidateAndCancel() }
        let store = TransactionStore(apiClient: APIClient(baseURL: URL(string: "https://test.invalid")!, session: session))
        await store.loadTransactions(accountID: nil)

        try await store.deleteTransaction(transaction)

        XCTAssertTrue(store.transactions.isEmpty)
        XCTAssertTrue(store.allTransactions.isEmpty)
        XCTAssertEqual(store.balance(accountID: nil, currency: "USD", rates: nil), 0)
        XCTAssertEqual(store.state, .loaded)
    }

    func testFailedDeleteLeavesTransactionUntouched() async throws {
        let transaction = transaction(accountID: UUID())
        let session = makeSession { request in
            if request.url?.lastPathComponent == "upcoming" {
                return (200, Data("[]".utf8))
            }
            if request.httpMethod == "GET" {
                return (200, try self.encode([transaction]))
            }
            return (500, Data(#"{"message":"Could not delete transaction"}"#.utf8))
        }
        defer { session.invalidateAndCancel() }
        let store = TransactionStore(apiClient: APIClient(baseURL: URL(string: "https://test.invalid")!, session: session))
        await store.loadTransactions(accountID: nil)

        do {
            try await store.deleteTransaction(transaction)
            XCTFail("Expected deletion to fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Could not delete transaction")
        }
        XCTAssertEqual(store.transactions, [transaction])
    }

    func testUpcomingLoadsForSelectedAccountAndRefreshesAfterRecurringSave() async throws {
        let accountID = UUID()
        let scheduleID = UUID()
        var original = transaction(accountID: accountID)
        original.recurrence = TransactionRecurrence(id: scheduleID, frequency: .monthly, endAt: nil)
        let upcoming = UpcomingTransaction(
            id: scheduleID, accountId: accountID, kind: .expense, amount: "14.99", currency: "USD",
            category: nil, merchant: "Netflix", payee: nil, note: nil, frequency: .monthly,
            occurredAt: Date(timeIntervalSince1970: 4_124_044_800)
        )
        let otherAccountUpcoming = upcomingTransaction()
        var recurring = true
        let session = makeSession { request in
            if request.url?.lastPathComponent == "upcoming" {
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
                XCTAssertNil(query)
                return (200, try self.encode(recurring ? [upcoming, otherAccountUpcoming] : [otherAccountUpcoming]))
            }
            if request.httpMethod == "PUT" {
                recurring = false
                return (200, try self.encode(original))
            }
            return (200, try self.encode([original]))
        }
        defer { session.invalidateAndCancel() }
        let store = TransactionStore(apiClient: APIClient(baseURL: URL(string: "https://test.invalid")!, session: session))

        await store.loadTransactions(accountID: accountID)
        XCTAssertEqual(store.upcomingState, .loaded)
        XCTAssertEqual(store.upcomingTransactions, [upcoming])
        XCTAssertEqual(store.allUpcomingTransactions, [upcoming, otherAccountUpcoming])
        XCTAssertEqual(upcoming.title, "Netflix")

        try await store.updateTransaction(id: original.id, with: draft(original))
        XCTAssertEqual(store.upcomingState, .loaded)
        XCTAssertTrue(store.upcomingTransactions.isEmpty)
        XCTAssertEqual(store.allUpcomingTransactions, [otherAccountUpcoming])
    }

    func testUpcomingFailureDoesNotHideTransactionsAndCanBeRetriedForAllAccounts() async throws {
        let original = transaction(accountID: UUID())
        var shouldFail = true
        let session = makeSession { request in
            if request.url?.lastPathComponent == "upcoming" {
                XCTAssertNil(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems)
                return shouldFail
                    ? (500, Data(#"{"message":"Schedules unavailable"}"#.utf8))
                    : (200, Data("[]".utf8))
            }
            return (200, try self.encode([original]))
        }
        defer { session.invalidateAndCancel() }
        let store = TransactionStore(apiClient: APIClient(baseURL: URL(string: "https://test.invalid")!, session: session))

        await store.loadTransactions(accountID: nil)
        XCTAssertEqual(store.state, .loaded)
        XCTAssertEqual(store.transactions, [original])
        XCTAssertEqual(store.upcomingState, .failed("Schedules unavailable"))

        shouldFail = false
        await store.loadUpcomingTransactions(accountID: nil)
        XCTAssertEqual(store.upcomingState, .loaded)
        XCTAssertTrue(store.upcomingTransactions.isEmpty)
    }

    func testUpcomingIncomeUsesPayeeAndPositiveAmount() {
        let upcoming = UpcomingTransaction(
            id: UUID(), accountId: UUID(), kind: .income, amount: "2100", currency: "USD",
            category: nil, merchant: "Ignored merchant", payee: "Salary", note: "Monthly pay",
            frequency: .monthly, occurredAt: .now
        )
        XCTAssertEqual(upcoming.title, "Salary")
        XCTAssertTrue(upcoming.amountText.hasPrefix("+"))
    }

    func testTemplateEditorKeepsNextDateRecurrenceAndEndDate() {
        let item = upcomingTransaction()
        let model = AddTransactionViewModel(transaction: item)
        XCTAssertEqual(model.accountID, item.accountId)
        XCTAssertEqual(model.merchant, "Netflix")
        XCTAssertEqual(model.occurredAt, item.occurredAt)
        XCTAssertEqual(model.recurrenceFrequency, .monthly)
        XCTAssertEqual(model.recurrenceEndAt, item.endAt)
        XCTAssertTrue(model.isRecurring)
        XCTAssertFalse(model.hasChanges(from: item))
        model.setAmountText("20")
        XCTAssertTrue(model.hasChanges(from: item))
    }

    func testTemplateSaveUsesScheduleEndpointAndRefreshesUpcomingWithoutChangingHistory() async throws {
        let item = upcomingTransaction()
        let history = transaction(accountID: item.accountId)
        var saved = false
        let session = makeSession { request in
            if request.httpMethod == "PUT" {
                XCTAssertEqual(request.url?.path, "/api/v1/transactions/recurring/\(item.id.uuidString)")
                let data = try XCTUnwrap(requestBody(request))
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                XCTAssertEqual(body["expectedOccurredAt"] as? String, "2100-01-31T12:00:00.000Z")
                let values = try XCTUnwrap(body["transaction"] as? [String: Any])
                XCTAssertEqual(values["amount"] as? String, "20")
                XCTAssertEqual((values["recurrence"] as? [String: Any])?["frequency"] as? String, "monthly")
                saved = true
                return (200, Data(#"{"updated":true}"#.utf8))
            }
            if request.url?.lastPathComponent == "upcoming" {
                return (200, try self.encode([self.upcomingTransaction(id: item.id, accountID: item.accountId, amount: saved ? "20" : "14.99")]))
            }
            return (200, try self.encode([history]))
        }
        defer { session.invalidateAndCancel() }
        let store = TransactionStore(apiClient: APIClient(baseURL: URL(string: "https://test.invalid")!, session: session))
        await store.loadTransactions(accountID: item.accountId)
        let request = TransactionRequest(accountId: item.accountId, kind: .expense, amount: "20", categoryId: nil, merchant: "Netflix", note: nil, occurredAt: item.occurredAt, recurrence: RecurrenceRequest(frequency: .monthly, endAt: item.endAt))
        try await store.updateRecurringTransaction(item, with: request)
        XCTAssertTrue(saved)
        XCTAssertEqual(store.transactions, [history])
        XCTAssertEqual(store.upcomingTransactions.first?.amount, "20")
    }

    func testEachRecurringDeleteChoiceSendsItsActionAndSelectedOccurrence() async throws {
        for action in RecurringDeletionAction.allCases {
            let item = upcomingTransaction()
            var deleted = false
            let session = makeSession { request in
                if request.httpMethod == "DELETE" {
                    XCTAssertEqual(request.url?.path, "/api/v1/transactions/recurring/\(item.id.uuidString)")
                    let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
                    XCTAssertEqual(query.first { $0.name == "action" }?.value, action.rawValue)
                    XCTAssertEqual(query.first { $0.name == "occurredAt" }?.value, "2100-01-31T12:00:00.000Z")
                    deleted = true
                    return (200, Data(#"{"deleted":true}"#.utf8))
                }
                if request.url?.lastPathComponent == "upcoming" {
                    return (200, try self.encode(deleted ? [] : [item]))
                }
                return (200, Data("[]".utf8))
            }
            let store = TransactionStore(apiClient: APIClient(baseURL: URL(string: "https://test.invalid")!, session: session))
            await store.loadTransactions(accountID: nil)
            try await store.deleteUpcomingTransaction(item, action: action)
            XCTAssertTrue(deleted)
            XCTAssertTrue(store.upcomingTransactions.isEmpty)
            XCTAssertEqual(store.upcomingState, .loaded)
            session.invalidateAndCancel()
        }
    }

    func testFailedRecurringDeletionLeavesUpcomingItemUntouched() async throws {
        let item = upcomingTransaction()
        let session = makeSession { request in
            if request.httpMethod == "DELETE" {
                return (409, Data(#"{"message":"Refresh the list."}"#.utf8))
            }
            return (200, try self.encode([item]))
        }
        defer { session.invalidateAndCancel() }
        let store = TransactionStore(apiClient: APIClient(baseURL: URL(string: "https://test.invalid")!, session: session))
        await store.loadUpcomingTransactions(accountID: nil)
        do {
            try await store.deleteUpcomingTransaction(item, action: .occurrenceAndFuture)
            XCTFail("Expected deletion to fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Refresh the list.")
        }
        XCTAssertEqual(store.upcomingTransactions, [item])
    }

    func testAllBalancesRemainAvailableWhileDashboardFiltersOneAccount() async throws {
        let firstID = UUID()
        let secondID = UUID()
        let income = transaction(accountID: firstID, kind: .income, amount: "100")
        let expense = transaction(accountID: firstID, amount: "25")
        let otherIncome = transaction(accountID: secondID, kind: .income, amount: "50")
        let all = [income, expense, otherIncome]
        let session = makeSession { request in
            if request.url?.lastPathComponent == "upcoming" {
                return (200, Data("[]".utf8))
            }
            XCTAssertNil(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems)
            return (200, try self.encode(all))
        }
        defer { session.invalidateAndCancel() }
        let store = TransactionStore(apiClient: APIClient(baseURL: URL(string: "https://test.invalid")!, session: session))

        await store.loadTransactions(accountID: firstID)
        XCTAssertEqual(store.transactions, [income, expense])
        XCTAssertEqual(store.allTransactions, all)
        XCTAssertEqual(store.balance(accountID: firstID, currency: "USD", rates: nil), 75)
        XCTAssertEqual(store.balance(accountID: secondID, currency: "USD", rates: nil), 50)
        XCTAssertEqual(store.balance(accountID: nil, currency: "USD", rates: nil), 125)
        XCTAssertEqual(store.balance(accountID: UUID(), currency: "USD", rates: nil), 0)

        await store.loadTransactions(accountID: secondID)
        XCTAssertEqual(store.transactions, [otherIncome])
        XCTAssertEqual(store.balance(accountID: nil, currency: "USD", rates: nil), 125)
    }

    func testBalancesConvertEveryCurrencyAndDoNotReturnPartialTotals() {
        let euros = transaction(accountID: UUID(), kind: .income, amount: "100", currency: "EUR")
        let dollars = transaction(accountID: UUID(), amount: "25")
        let store = TransactionStore.preview(transactions: [euros, dollars])
        let rates = ExchangeRateSnapshot(
            baseCurrency: "USD", reportingCurrency: "USD",
            quotes: [
                ExchangeRateQuote(currency: "USD", rate: "1", effectiveDate: "2026-09-03"),
                ExchangeRateQuote(currency: "EUR", rate: "0.8", effectiveDate: "2026-09-03"),
            ],
            fetchedAt: .now, stale: false
        )

        XCTAssertEqual(store.balance(accountID: euros.accountId, currency: "EUR", rates: nil), 100)
        XCTAssertEqual(store.balance(accountID: dollars.accountId, currency: "USD", rates: nil), -25)
        XCTAssertEqual(store.balance(accountID: nil, currency: "USD", rates: rates), 100)
        XCTAssertEqual(store.balance(accountID: nil, currency: "EUR", rates: rates), 80)
        XCTAssertNil(store.balance(accountID: nil, currency: "USD", rates: nil))
        XCTAssertNil(store.balance(accountID: nil, currency: "JPY", rates: rates))
    }

    func testCreatingTransactionInAnotherAccountUpdatesItsBalanceWithoutAddingDashboardRow() async throws {
        let selected = transaction(accountID: UUID(), kind: .income, amount: "100")
        let created = transaction(accountID: UUID(), kind: .income, amount: "40")
        let session = makeSession { request in
            if request.url?.lastPathComponent == "upcoming" {
                return (200, Data("[]".utf8))
            }
            return request.httpMethod == "POST"
                ? (201, try self.encode(created))
                : (200, try self.encode([selected]))
        }
        defer { session.invalidateAndCancel() }
        let store = TransactionStore(apiClient: APIClient(baseURL: URL(string: "https://test.invalid")!, session: session))
        await store.loadTransactions(accountID: selected.accountId)
        try await store.createTransaction(draft(created))

        XCTAssertEqual(store.transactions, [selected])
        XCTAssertEqual(store.balance(accountID: created.accountId, currency: "USD", rates: nil), 40)
        XCTAssertEqual(store.balance(accountID: nil, currency: "USD", rates: nil), 140)
    }

    func testTransferUpdatesBothAccountBalancesWithoutChangingCombinedBalance() async throws {
        let fromID = UUID()
        let toID = UUID()
        let income = transaction(accountID: fromID, kind: .income, amount: "100")
        let source = transaction(accountID: fromID, amount: "30")
        let destination = transaction(accountID: toID, kind: .income, amount: "30")
        let session = makeSession { request in
            if request.url?.lastPathComponent == "upcoming" {
                return (200, Data("[]".utf8))
            }
            if request.httpMethod == "POST" {
                return (201, try self.encode(["source": source, "destination": destination]))
            }
            return (200, try self.encode([income]))
        }
        defer { session.invalidateAndCancel() }
        let store = TransactionStore(apiClient: APIClient(baseURL: URL(string: "https://test.invalid")!, session: session))
        await store.loadTransactions(accountID: fromID)
        try await store.createTransfer(TransferRequest(
            fromAccountId: fromID, toAccountId: toID, amount: "30",
            merchant: nil, payee: nil, note: nil, occurredAt: .now
        ))

        XCTAssertEqual(store.transactions.count, 2)
        XCTAssertTrue(store.transactions.allSatisfy { $0.accountId == fromID })
        XCTAssertEqual(store.balance(accountID: fromID, currency: "USD", rates: nil), 70)
        XCTAssertEqual(store.balance(accountID: toID, currency: "USD", rates: nil), 30)
        XCTAssertEqual(store.balance(accountID: nil, currency: "USD", rates: nil), 100)
    }

    func testBalancesStayUnavailableUntilFullTransactionLoadSucceeds() async throws {
        let created = transaction(accountID: UUID(), kind: .income, amount: "40")
        let session = makeSession { request in
            if request.httpMethod == "POST" {
                return (201, try self.encode(created))
            }
            return (500, Data(#"{"message":"Unavailable"}"#.utf8))
        }
        defer { session.invalidateAndCancel() }
        let store = TransactionStore(apiClient: APIClient(baseURL: URL(string: "https://test.invalid")!, session: session))
        XCTAssertNil(store.balance(accountID: nil, currency: "USD", rates: nil))
        await store.loadTransactions(accountID: nil)
        try await store.createTransaction(draft(created))
        XCTAssertNil(store.balance(accountID: nil, currency: "USD", rates: nil))
    }

    private func upcomingTransaction(id: UUID = UUID(), accountID: UUID = UUID(), amount: String = "14.99") -> UpcomingTransaction {
        UpcomingTransaction(id: id, accountId: accountID, kind: .expense, amount: amount, currency: "USD", category: nil, merchant: "Netflix", payee: nil, note: nil, frequency: .monthly, occurredAt: ISO8601DateFormatter().date(from: "2100-01-31T12:00:00Z")!, endAt: ISO8601DateFormatter().date(from: "2100-12-31T12:00:00Z"))
    }

    private func transaction(
        id: UUID = UUID(), accountID: UUID, occurredAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        kind: TransactionKind = .expense, amount: String = "12.5000", currency: String = "USD"
    ) -> FinanceTransaction {
        FinanceTransaction(
            id: id, accountId: accountID, kind: kind, amount: amount, currency: currency,
            category: nil, note: nil, occurredAt: occurredAt,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000), updatedAt: Date(timeIntervalSince1970: 1_700_002_000)
        )
    }

    private func category(
        id: UUID = UUID(),
        name: String = "Coffee",
        parentID: UUID? = nil,
        icon: String,
        color: CategoryColor
    ) -> TransactionCategory {
        TransactionCategory(
            id: id,
            systemKey: nil,
            name: name,
            kind: .expense,
            parentId: parentID,
            icon: icon,
            color: color,
            isSystem: false,
            examples: [],
            sortOrder: 1_000,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func draft(_ transaction: FinanceTransaction) -> TransactionRequest {
        TransactionRequest(
            accountId: transaction.accountId, kind: transaction.kind, amount: transaction.amount,
            categoryId: nil, note: nil, occurredAt: transaction.occurredAt
        )
    }

    nonisolated private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return try encoder.encode(value)
    }

    private func makeSession(
        handler: @escaping (URLRequest) throws -> (Int, Data)
    ) -> URLSession {
        TransactionTestProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TransactionTestProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class TransactionTestProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func requestBody(_ request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count > 0 else { break }
        data.append(buffer, count: count)
    }
    return data
}
