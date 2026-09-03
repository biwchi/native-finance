import XCTest
@testable import FinanceTracker

final class MoneyFormatterTests: XCTestCase {
    func testCurrencyExamplesHaveFixedTwoDecimalPlaces() throws {
        for (raw, currency, expected) in [
            ("62253.40", "KZT", "₸62 253,40"),
            ("62253.4", "kzt", "₸62 253,40"),
            ("62253", "KZT", "₸62 253,00"),
            ("40.1", "USD", "$40,10"),
            ("0", "KZT", "₸0,00"),
            ("1234.5", "EUR", "€1 234,50"),
            ("1234.5", "GBP", "£1 234,50"),
            ("1234", "JPY", "¥1 234,00"),
            ("1234.567", "KWD", "KWD1 234,57"),
            ("1234", "ZZZ", "ZZZ1 234,00"),
        ] {
            let value = try XCTUnwrap(Decimal(string: raw))
            XCTAssertEqual(MoneyFormatter.format(value, currency: currency), expected)
        }
    }

    func testRoundingSignsAndLargeValuesRemainDecimalAccurate() throws {
        for (raw, expected) in [
            ("-62253.4", "-₸62 253,40"),
            ("1.005", "₸1,01"),
            ("-1.005", "-₸1,01"),
            ("999.9999", "₸1 000,00"),
            ("-0.004", "₸0,00"),
            ("123456789012345.125", "₸123 456 789 012 345,13"),
        ] {
            let value = try XCTUnwrap(Decimal(string: raw))
            XCTAssertEqual(MoneyFormatter.format(value, currency: "KZT"), expected)
        }
        XCTAssertEqual(MoneyFormatter.format(40, currency: "USD", showPositiveSign: true), "+$40,00")
        XCTAssertEqual(MoneyFormatter.format(-40, currency: "USD", showPositiveSign: true), "-$40,00")
        XCTAssertEqual(MoneyFormatter.format(0, currency: "USD", showPositiveSign: true), "$0,00")
        XCTAssertEqual(MoneyFormatter.format(.nan, currency: "USD"), "Unavailable")
    }

    func testFormattedNumbersCanBeEditedWithoutLosingPrecision() throws {
        for input in ["62 253,40", "62\u{00A0}253,40", "62\u{202F}253,40", "62253.40"] {
            XCTAssertEqual(MoneyFormatter.parseInput(input), Decimal(string: "62253.4"))
        }
        let original = try XCTUnwrap(Decimal(string: "123456789012345.1234"))
        XCTAssertEqual(MoneyFormatter.parseInput(",5"), Decimal(string: "0.5"))
        XCTAssertEqual(MoneyFormatter.parseInput(".5"), Decimal(string: "0.5"))
        XCTAssertEqual(MoneyFormatter.number(original), "123 456 789 012 345,12")
        XCTAssertEqual(MoneyFormatter.editingText(original), "123456789012345,1234")
        XCTAssertEqual(MoneyFormatter.parseInput(MoneyFormatter.editingText(original)), original)
        for input in ["", "abc", "12abc", "12,3,4", "12.3.4", "NaN"] {
            XCTAssertNil(MoneyFormatter.parseInput(input), input)
        }
    }

    func testTransactionAndRecurringAmountsUseTheSharedFormat() {
        let date = Date(timeIntervalSince1970: 0)
        for kind in TransactionKind.allCases {
            let transaction = FinanceTransaction(
                id: UUID(), accountId: UUID(), kind: kind, amount: "62253.4000", currency: "KZT",
                category: nil, note: nil, occurredAt: date, createdAt: date, updatedAt: date
            )
            let upcoming = UpcomingTransaction(
                id: UUID(), accountId: transaction.accountId, kind: kind, amount: transaction.amount,
                currency: transaction.currency, category: nil, merchant: nil, payee: nil, note: nil,
                frequency: .monthly, occurredAt: date
            )
            XCTAssertEqual(transaction.formattedAmount(), kind == .income ? "+₸62 253,40" : "-₸62 253,40")
            XCTAssertEqual(upcoming.amountText, kind == .income ? "+₸62 253,40" : "₸62 253,40")
            XCTAssertEqual(upcoming.amountText, upcoming.formattedAmount(showExpenseSign: false))
        }
    }
}
