import SwiftUI
import XCTest
@testable import FinanceTracker

@MainActor
final class TransactionCSVTests: XCTestCase {
    func testCounterpartyRoundTrip() throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository)
        for counterparty in [nil, "Urbo Coffee", ""] as [String?] {
            var request = LocalTestData.transaction(account.id)
            request.counterparty = counterparty
            let saved = try repository.edit { try $0.saveTransaction(request: request) }
            let csv = TransactionCSV.encode([saved], accounts: [account], categories: [], debts: [])
            let imported = try XCTUnwrap(decode(csv, repository: repository).first)
            XCTAssertEqual(imported.counterparty, saved.counterparty)
        }
    }

    private func decode(_ csv: String, repository: LocalFinanceRepository, timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!) throws -> [QuickEntryDraft] {
        try TransactionCSV.decode(Data(csv.utf8), accounts: repository.snapshot.sortedAccounts,
                                  categories: Array(repository.snapshot.categories.values), debts: Array(repository.snapshot.debts.values), timeZone: timeZone)
    }

    func testBOMReorderedHeadersBlankLinesCRLFAndQuotedFields() throws {
        let repository = try LocalTestData.repository()
        _ = try LocalTestData.account(repository)
        let drafts = try decode("\u{FEFF}ACCOUNT,amount,TYPE,date,note\r\n\r\nmain,12.3456,EXPENSE,2026-01-15,\"Coffee, \"\"large\"\"\r\nwith milk\"\r\n", repository: repository)
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].amount, "12.3456")
        XCTAssertEqual(drafts[0].currency, "USD")
        XCTAssertEqual(drafts[0].note, "Coffee, \"large\"\r\nwith milk")
        XCTAssertTrue(repository.snapshot.transactions.isEmpty)
    }

    func testDateOnlyUsesDeviceZoneAndISOTimePreservesInstant() throws {
        let repository = try LocalTestData.repository()
        _ = try LocalTestData.account(repository)
        let drafts = try decode("date,type,amount,account\n2026-01-15,expense,1,Main\n2026-01-15T14:30:00+05:00,income,2,Main", repository: repository, timeZone: TimeZone(secondsFromGMT: 5 * 3600)!)
        XCTAssertEqual(drafts[0].occurredAt, LocalTestData.date("2026-01-14T19:00:00Z"))
        XCTAssertEqual(drafts[1].occurredAt, LocalTestData.date("2026-01-15T09:30:00Z"))
    }

    func testNegativeAmountsUseTheSelectedTypeAndBecomePositiveMagnitudes() throws {
        let repository = try LocalTestData.repository()
        _ = try LocalTestData.account(repository)
        let drafts = try decode("date,type,amount,account\n2026-01-15,expense,-12.50,Main", repository: repository)
        XCTAssertEqual(drafts.first?.amount, "12.50")
    }

    func testInvalidTablesProduceActionableErrorsWithoutDraftsOrWrites() throws {
        let repository = try LocalTestData.repository()
        _ = try LocalTestData.account(repository)
        let pending = repository.snapshot.pending.count
        let cases: [(String, String)] = [
            ("", "empty"),
            ("date,type,amount,account", "no transactions"),
            ("date,type,amount\n2026-01-01,expense,10", "Missing columns: account"),
            ("date,type,amount,account,account", "only once"),
            ("date,type,amount,account,recurrence", "Unknown columns"),
            ("date;type;amount;account", "Use commas"),
            ("date,type,amount,account\n2026-02-30,expense,10,Main", "Row 2: Date"),
            ("date,type,amount,account\n2026-02-30T10:00:00Z,expense,10,Main", "Row 2: Date"),
            ("date,type,amount,account\n2026-01-01T24:00:00Z,expense,10,Main", "Row 2: Date"),
            ("date,type,amount,account\n2026-01-01T12:00:00,expense,10,Main", "Row 2: Date"),
            ("date,type,amount,account\n2026-01-01,expense,0,Main", "Row 2: Amount"),
            ("date,type,amount,account\n2026-01-01,expense,1.12345,Main", "Row 2: Amount"),
            ("date,type,amount,account\n2026-01-01,expense,1e3,Main", "Row 2: Amount"),
            ("date,type,amount,account\n2026-01-01,transfer,10,Main", "Row 2: Type"),
            ("date,type,amount,account\n2026-01-01,expense,10,Missing", "Unknown account"),
            ("date,type,amount,account,currency\n2026-01-01,expense,10,Main,US", "Currency"),
            ("date,type,amount,account,note\n2026-01-01,expense,10,Main,\"open", "closing quote"),
            ("date,type,amount,account,note\n2026-01-01,expense,10,Main,\"closed\"extra", "Unexpected text"),
            ("date,type,amount,account\n2026-01-01,expense,10,Main,extra", "Expected 4 columns"),
            ("date,type,amount,account,note\n2026-01-01,expense,10,Main,\"\(String(repeating: "x", count: 2001))\"", "2000")
        ]
        for (csv, message) in cases {
            XCTAssertThrowsError(try decode(csv, repository: repository)) { error in
                XCTAssertTrue(error.localizedDescription.contains(message), "\(error.localizedDescription) should contain \(message)")
            }
        }
        XCTAssertTrue(repository.snapshot.transactions.isEmpty)
        XCTAssertEqual(repository.snapshot.pending.count, pending)
    }

    func testUnknownAndAmbiguousCategoriesAccountsAndRecipientsAreRejected() throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository)
        _ = try LocalTestData.account(repository, name: "MAIN")
        XCTAssertThrowsError(try decode("date,type,amount,account\n2026-01-01,expense,10,Main", repository: repository))
        XCTAssertEqual(try decode("date,type,amount,account\n2026-01-01,expense,10,\(account.id)", repository: repository).first?.accountId, account.id)
        for (kind, category, recipient) in [("expense", "Missing", ""), ("debt", "", "Missing"), ("expense", "", "Sam"), ("debt", "Food", "Sam")] {
            XCTAssertThrowsError(try decode("date,type,amount,account,category,recipient\n2026-01-01,\(kind),10,\(account.id),\(category),\(recipient)", repository: repository))
        }
    }

    func testLimitsAndInvalidEncoding() throws {
        let repository = try LocalTestData.repository()
        _ = try LocalTestData.account(repository)
        XCTAssertThrowsError(try TransactionCSV.decode(Data([0xFF, 0xFE, 0xFF]), accounts: [], categories: [], debts: []))
        XCTAssertThrowsError(try TransactionCSV.decode(Data(repeating: 65, count: TransactionCSV.maximumBytes + 1), accounts: [], categories: [], debts: []))
        let tooMany = "date,type,amount,account\n" + String(repeating: "2026-01-01,expense,1,Main\n", count: TransactionCSV.maximumTransactions + 1)
        XCTAssertThrowsError(try decode(tooMany, repository: repository))
    }

    func testRoundTripPreservesCurrenciesUnicodeCategoryPathsDebtAndFormulaText() async throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository, name: "Карта, main", currency: "KZT")
        let parent = try repository.edit { try $0.saveCategory(name: "Food", kind: .expense, parentID: nil, icon: "label", color: .gray) }
        let category = try repository.edit { try $0.saveCategory(name: "Coffee", kind: .expense, parentID: parent.id, icon: "label", color: .gray) }
        let recipient = try repository.edit { try $0.saveDebt(name: "Sam", icon: "user", color: .blue) }
        let notes = ["=HYPERLINK(\"example\")", "+sum", "-formula", "@value", "'literal", "\"quote\", comma\nnext line"]
        for note in notes {
            _ = try repository.edit { try $0.saveTransaction(request: TransactionRequest(accountId: account.id, kind: .expense, amount: "12.3456", categoryId: category.id, note: note, occurredAt: LocalTestData.now, currency: "USD", counterparty: "Coffee")) }
        }
        _ = try repository.edit { try $0.saveTransaction(request: TransactionRequest(accountId: account.id, kind: .debt, amount: "100", categoryId: nil, note: nil, occurredAt: LocalTestData.now, debtId: recipient.id)) }
        let store = TransactionStore(repository: repository)
        let csv = TransactionCSV.encode(store.allTransactions, accounts: [account], categories: store.categories, debts: store.debts)
        XCTAssertTrue(csv.contains("Food › Coffee"))
        XCTAssertTrue(csv.contains("'=HYPERLINK"))
        let drafts = try decode(csv, repository: repository)
        XCTAssertEqual(Set(drafts.compactMap(\.note)), Set(notes))
        XCTAssertEqual(drafts.filter { $0.currency == "USD" }.count, notes.count)
        XCTAssertEqual(drafts.first { $0.kind == .debt }?.debtId, recipient.id)
        XCTAssertEqual(drafts.filter { $0.category?.id == category.id }.count, notes.count)
        let saved = try await store.commitCSVImport(drafts)
        XCTAssertEqual(saved, drafts.count)
        XCTAssertEqual(store.allTransactions.count, drafts.count * 2)
    }

    func testDuplicateNamesExportAsIDsAndRemainImportable() throws {
        let repository = try LocalTestData.repository()
        let first = try LocalTestData.account(repository)
        _ = try LocalTestData.account(repository)
        let record = try repository.edit { try $0.saveTransaction(request: LocalTestData.transaction(first.id)) }
        let csv = TransactionCSV.encode([record], accounts: repository.snapshot.sortedAccounts, categories: [], debts: [])
        XCTAssertTrue(csv.contains(first.id.uuidString))
        XCTAssertEqual(try decode(csv, repository: repository).first?.accountId, first.id)
    }

    func testDateRangeIncludesWholeEndDayAcrossDaylightSavingAndFiltersAccount() throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository)
        let other = try LocalTestData.account(repository, name: "Other")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let instants = ["2026-03-08T04:59:59Z", "2026-03-08T05:00:00Z", "2026-03-09T03:59:59Z", "2026-03-09T04:00:00Z"]
        var records: [FinanceTransaction] = []
        for instant in instants {
            records.append(try repository.edit { try $0.saveTransaction(request: LocalTestData.transaction(account.id, occurredAt: LocalTestData.date(instant))) })
        }
        records.append(try repository.edit { try $0.saveTransaction(request: LocalTestData.transaction(other.id, occurredAt: LocalTestData.date(instants[1]))) })
        let day = LocalTestData.date("2026-03-08T12:00:00Z")
        XCTAssertEqual(TransactionCSV.filtered(records, accountID: account.id, start: day, end: day, calendar: calendar).map(\.occurredAt), [LocalTestData.date(instants[1]), LocalTestData.date(instants[2])])
        XCTAssertEqual(TransactionCSV.filtered(records, accountID: nil, start: nil, end: nil).count, 5)
    }

    func testPreviewDoesNotWriteAndSubmitCommitsMoreThan100WhilePreservingAIReview() async throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository)
        let store = TransactionStore(repository: repository)
        let pending = repository.snapshot.pending.count
        let csv = "date,type,amount,account\n" + String(repeating: "2026-01-01,expense,1,Main\n", count: 125)
        var drafts = try decode(csv, repository: repository)
        XCTAssertTrue(repository.snapshot.transactions.isEmpty)
        XCTAssertEqual(repository.snapshot.pending.count, pending)
        let review = QuickEntryReviewPresentation(prompt: "Unfinished AI review", drafts: [drafts[0]])
        try store.saveQuickEntryReview(review)
        drafts.removeLast()
        drafts[0].amount = "99.1234"
        let count = try await store.commitCSVImport(drafts)
        XCTAssertEqual(count, 124)
        XCTAssertEqual(repository.snapshot.transactions.count, 124)
        XCTAssertEqual(repository.snapshot.pending.count, pending + 1)
        XCTAssertTrue(store.allTransactions.contains { $0.amount == "99.1234" })
        XCTAssertEqual(store.savedQuickEntryReview()?.id, review.id)
        let reopened = try LocalFinanceRepository(path: repository.requireDatabase().pool.path)
        XCTAssertEqual(reopened.snapshot.transactions.count, 124)
        XCTAssertTrue(reopened.snapshot.transactions.values.allSatisfy { $0.accountId == account.id })
    }

    func testFailedSubmitIsAtomicAndRevalidatesDeletedAccounts() async throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository)
        let store = TransactionStore(repository: repository)
        var drafts = try decode("date,type,amount,account\n2026-01-01,expense,1,Main\n2026-01-02,expense,2,Main", repository: repository)
        let pending = repository.snapshot.pending.count
        drafts[1].amount = "0"
        do { _ = try await store.commitCSVImport(drafts); XCTFail("Must reject the whole batch") } catch {}
        XCTAssertTrue(store.allTransactions.isEmpty)
        XCTAssertEqual(repository.snapshot.pending.count, pending)
        drafts[1].amount = "2"
        try repository.edit { $0.deleteAccount(account.id) }
        do { _ = try await store.commitCSVImport(drafts); XCTFail("Must revalidate references") } catch {}
        XCTAssertTrue(store.allTransactions.isEmpty)
    }

    func testRecurringExportImportsOnlyRecordedRowsAndDoesNotMaterializeSchedules() async throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository)
        let record = try repository.edit(now: LocalTestData.now) { try $0.saveTransaction(request: LocalTestData.transaction(account.id, recurrence: RecurrenceRequest(frequency: .monthly, endAt: nil))) }
        let store = TransactionStore(repository: repository)
        let csv = TransactionCSV.encode([record], accounts: [account], categories: [], debts: [])
        let drafts = try decode(csv, repository: repository)
        XCTAssertFalse(drafts[0].isRecurring)
        _ = try await store.commitCSVImport(drafts)
        XCTAssertEqual(store.allTransactions.count, 2)
        XCTAssertEqual(repository.snapshot.schedules.count, 1)
        var invalid = drafts[0]
        invalid.isRecurring = true
        do { _ = try await store.commitCSVImport([invalid]); XCTFail("CSV must not create schedules") } catch {}
    }

    func testExampleCanBeImportedAndFileDocumentWritesUTF8() throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository)
        XCTAssertEqual(try decode(TransactionCSV.template(account: account), repository: repository).count, 1)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("csv-test-\(UUID()).csv")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(TransactionCSV.template(account: account).utf8).write(to: file)
        XCTAssertEqual(try TransactionCSV.readFile(file), Data(TransactionCSV.template(account: account).utf8))
    }

    func testCSVViewsRenderInLightAndDarkWithEnabledAndEmptyStates() async throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository)
        let store = TransactionStore(repository: repository)
        let accounts = AccountStore(repository: repository)
        let drafts = try decode(TransactionCSV.template(account: account), repository: repository)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for scheme in [ColorScheme.light, .dark] {
            for empty in [true, false] {
                let review = QuickEntryReviewPresentation(prompt: "transactions.csv", drafts: empty ? [] : drafts, source: .csv)
                try await capture(QuickEntryReviewView(presentation: review).environmentObject(store).environmentObject(accounts), name: "CSV-review-\(scheme)-\(empty)", scheme: scheme, scene: scene)
            }
            try await capture(NavigationStack { CSVImportView() }.environmentObject(store).environmentObject(accounts), name: "CSV-import-\(scheme)", scheme: scheme, scene: scene)
            try await capture(NavigationStack { CSVExportView() }.environmentObject(store).environmentObject(accounts), name: "CSV-export-empty-\(scheme)", scheme: scheme, scene: scene)
            try await capture(CSVImportHelpView(exampleAccount: account), name: "CSV-help-\(scheme)", scheme: scheme, scene: scene)
        }
        XCTAssertTrue(store.allTransactions.isEmpty)
    }

    private func capture<Content: View>(_ content: Content, name: String, scheme: ColorScheme, scene: UIWindowScene) async throws {
        let controller = UIHostingController(rootView: content.tint(AppColor.accent).preferredColorScheme(scheme))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.frame = window.bounds
        try await Task.sleep(for: .milliseconds(200))
        controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
