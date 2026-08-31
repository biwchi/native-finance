import XCTest
@testable import FinanceTracker

final class TransactionCommandParserTests: XCTestCase {
    private let parser = TransactionCommandParser()
    private var calendar: Calendar!
    private var timeZone: TimeZone!
    private var now: Date!

    override func setUpWithError() throws {
        timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Almaty"))
        calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = timeZone
        now = try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    timeZone: timeZone,
                    year: 2026,
                    month: 8,
                    day: 31,
                    hour: 14,
                    minute: 35,
                    second: 42
                )
            )
        )
    }

    func testParsesExpenseAmountAndDescription() {
        let result = parse("12.50 coffee")

        XCTAssertEqual(result.amount, Decimal(string: "12.50"))
        XCTAssertEqual(result.kind, .expense)
        XCTAssertEqual(result.description, "coffee")
        XCTAssertNil(result.occurredAt)
        XCTAssertFalse(result.amountConflict)
    }

    func testParsesYesterdayAndFuelCategory() throws {
        let result = parse("40 gas yesterday")
        let fuel = category(
            name: "Fuel",
            key: "expense.fuel",
            kind: .expense,
            examples: ["gas", "gasoline", "petrol"]
        )

        XCTAssertEqual(result.amount, 40)
        XCTAssertEqual(result.description, "gas")
        XCTAssertDate(result.occurredAt, year: 2026, month: 8, day: 30, hour: 14, minute: 35)
        XCTAssertEqual(
            LocalCategoryMatcher.resolve(description: result.description, categories: [fuel])?.categoryID,
            fuel.id
        )
    }

    func testPlusAmountIsIncomeAndMatchesSalary() {
        let result = parse("+3500 salary")
        let salary = category(
            name: "Salary",
            key: "income.salary",
            kind: .income,
            examples: ["salary", "paycheck", "payroll"]
        )

        XCTAssertEqual(result.amount, 3500)
        XCTAssertEqual(result.kind, .income)
        XCTAssertEqual(result.description, "salary")
        XCTAssertEqual(
            LocalCategoryMatcher.resolve(description: result.description, categories: [salary])?.categoryID,
            salary.id
        )
    }

    func testDateIsMaskedBeforeAmountParsing() {
        let result = parse("coffee 21.10.2026")

        XCTAssertNil(result.amount)
        XCTAssertEqual(result.description, "coffee")
        XCTAssertDate(result.occurredAt, year: 2026, month: 10, day: 21, hour: 14, minute: 35)
    }

    func testRelativeDatePreservesExplicitLocalTime() {
        let result = parse("gas yesterday 21:00")

        XCTAssertNil(result.amount)
        XCTAssertEqual(result.description, "gas")
        XCTAssertDate(result.occurredAt, year: 2026, month: 8, day: 30, hour: 21, minute: 0)
    }

    func testEnglishMonthDateUsesInjectedCalendar() {
        let result = parse("coffee on August 29, 2026 at 7:15 pm")

        XCTAssertEqual(result.description, "coffee")
        XCTAssertDate(result.occurredAt, year: 2026, month: 8, day: 29, hour: 19, minute: 15)
    }

    func testLocaleGroupingAndDecimalSeparators() {
        let german = parse("1.234,56 groceries", locale: Locale(identifier: "de_DE"))
        let english = parse("1,234.56 groceries", locale: Locale(identifier: "en_US"))

        XCTAssertEqual(german.amount, Decimal(string: "1234.56"))
        XCTAssertEqual(english.amount, Decimal(string: "1234.56"))
    }

    func testInvalidDateBlocksDateInferenceWithoutBecomingMoney() {
        let result = parse("coffee 31.02.2026")

        XCTAssertTrue(result.dateConflict)
        XCTAssertNil(result.occurredAt)
        XCTAssertNil(result.amount)
        XCTAssertEqual(result.description, "coffee")
    }

    func testAmountOnlyAllowsEmptyDescription() {
        let result = parse("12.50")

        XCTAssertEqual(result.amount, Decimal(string: "12.50"))
        XCTAssertEqual(result.description, "")
    }

    func testUnicodeSigns() {
        let income = parse("＋3500 salary")
        let expense = parse("−12.50 coffee")
        let fullWidthExpense = parse("－20 taxi")

        XCTAssertEqual(income.kind, .income)
        XCTAssertEqual(income.amount, 3500)
        XCTAssertEqual(expense.kind, .expense)
        XCTAssertEqual(expense.amount, Decimal(string: "12.50"))
        XCTAssertEqual(fullWidthExpense.kind, .expense)
        XCTAssertEqual(fullWidthExpense.amount, 20)
    }

    func testMultipleAmountsRemainUnresolved() {
        let result = parse("12 coffee and 4 tip")

        XCTAssertNil(result.amount)
        XCTAssertTrue(result.amountConflict)
        XCTAssertEqual(result.description, "coffee and tip")
    }

    func testConflictingDatesRemainUnresolved() {
        let result = parse("hotel yesterday on 2026-08-20")

        XCTAssertNil(result.occurredAt)
        XCTAssertTrue(result.dateConflict)
        XCTAssertEqual(result.description, "hotel")
    }

    func testRejectsMoreThanFourFractionDigitsAsAnAmount() {
        let result = parse("12.12345 adjustment")

        XCTAssertNil(result.amount)
        XCTAssertEqual(result.description, "12.12345 adjustment")
    }

    private func parse(
        _ command: String,
        locale: Locale = Locale(identifier: "en_US")
    ) -> TransactionCommandResult {
        parser.parse(
            command,
            context: TransactionCommandContext(
                now: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone,
                currencyCode: "USD"
            )
        )
    }

    private func category(
        name: String,
        key: String,
        kind: TransactionKind,
        examples: [String]
    ) -> TransactionCategory {
        TransactionCategory(
            id: UUID(),
            systemKey: key,
            name: name,
            kind: kind,
            isSystem: true,
            examples: examples,
            sortOrder: 10,
            createdAt: nil,
            updatedAt: nil
        )
    }

    private func XCTAssertDate(
        _ date: Date?,
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let date else {
            XCTFail("Expected a date", file: file, line: line)
            return
        }

        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        XCTAssertEqual(components.year, year, file: file, line: line)
        XCTAssertEqual(components.month, month, file: file, line: line)
        XCTAssertEqual(components.day, day, file: file, line: line)
        XCTAssertEqual(components.hour, hour, file: file, line: line)
        XCTAssertEqual(components.minute, minute, file: file, line: line)
    }
}
