import SwiftUI
import XCTest
@testable import FinanceTracker

@MainActor
final class TransactionStoreTests: XCTestCase {
    func testDebtScreensRenderInLightAndDark() async throws {
        let recipient = Debt(id: UUID(), name: "Alexey", icon: "star", color: .purple)
        let account = Account(id: UUID(), name: "Main account", type: .checking, currency: "USD",
            icon: "credit-card", iconColor: .blue, createdAt: "", updatedAt: "")
        var loan = transaction(accountID: account.id, kind: .debt, amount: "125.50")
        loan.debtId = recipient.id
        loan.debt = recipient
        let store = TransactionStore.preview(transactions: [loan])
        let accounts = AccountStore.preview(accounts: [account])
        let originalCurrency = UserDefaults.standard.object(forKey: AppPreferences.defaultCurrencyKey)
        UserDefaults.standard.set("USD", forKey: AppPreferences.defaultCurrencyKey)
        defer { UserDefaults.standard.set(originalCurrency, forKey: AppPreferences.defaultCurrencyKey) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for scheme in [ColorScheme.light, .dark] {
            for (name, content) in [
                ("Debts", AnyView(NavigationStack { DebtsView() })),
                ("Debt-entry", AnyView(AddTransactionView(transaction: loan))),
                ("Debt-recipient", AnyView(DebtEditorView(debt: recipient) { _ in })),
                ("Debt-recipients", AnyView(DebtRecipientsView())),
            ] {
                let controller = UIHostingController(rootView: content
                    .environmentObject(accounts).environmentObject(store).preferredColorScheme(scheme))
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
                window.rootViewController = controller
                window.makeKeyAndVisible()
                controller.view.frame = window.bounds
                try await Task.sleep(for: .milliseconds(300))
                controller.view.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                    XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "\(name)-\(scheme)"
                attachment.lifetime = .keepAlways
                add(attachment)
                window.isHidden = true
            }
        }
    }



    func testLegacyDebtWithoutAppearanceStillDecodes() throws {
        let id = UUID()
        let json = Data("{\"id\":\"\(id.uuidString)\",\"name\":\"Alexey\"}".utf8)
        let debt = try JSONDecoder().decode(Debt.self, from: json)
        XCTAssertEqual(debt.id, id)
        XCTAssertNil(debt.icon)
        XCTAssertNil(debt.color)
    }



    func testDebtTotalsIncludeAllAccountsAndRequireCompleteExchangeRates() {
        let euros = transaction(accountID: UUID(), kind: .debt, amount: "80", currency: "EUR")
        let dollars = transaction(accountID: UUID(), kind: .debt, amount: "25")
        let expense = transaction(accountID: dollars.accountId, amount: "900")
        let store = TransactionStore.preview(transactions: [euros, dollars, expense])
        let rates = ExchangeRateSnapshot(baseCurrency: "USD", reportingCurrency: "USD", quotes: [
            ExchangeRateQuote(currency: "USD", rate: "1", effectiveDate: "2026-09-03"),
            ExchangeRateQuote(currency: "EUR", rate: "0.8", effectiveDate: "2026-09-03"),
        ], fetchedAt: .now, stale: false)
        XCTAssertNil(store.outstandingDebt(currency: "USD", rates: nil))
        XCTAssertEqual(store.outstandingDebt(currency: "USD", rates: rates), 125)
        XCTAssertEqual(store.outstandingDebtInCurrency("EUR"), 80)
        XCTAssertEqual(store.outstandingDebtInCurrency("USD"), 25)
        XCTAssertEqual(TransactionStore.preview(transactions: []).outstandingDebt(currency: "USD", rates: nil), 0)
    }

    func testDebtRecipientIsRequiredAndPreservedWhenEditing() {
        let recipient = Debt(id: UUID(), name: "Alexey")
        var loan = transaction(accountID: UUID(), kind: .debt, amount: "50")
        loan.debtId = recipient.id
        loan.debt = recipient
        let model = AddTransactionViewModel(transaction: loan)
        XCTAssertEqual(QuickTransactionMode(loan), .debt)
        XCTAssertEqual(model.debtID, recipient.id)
        XCTAssertTrue(model.canSave)
        XCTAssertFalse(model.hasChanges(from: loan))
        model.setDebtID(nil)
        XCTAssertFalse(model.canSave)
        XCTAssertTrue(model.hasChanges(from: loan))
        model.setRecurring(true)
        XCTAssertFalse(model.isRecurring)
        model.setKind(.expense, categories: [])
        XCTAssertNil(model.debtID)
    }

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
