import XCTest
@testable import FinanceTracker

final class MoneyFormatterTests: XCTestCase {
    func testCompactTotalsPreserveSignsAndRoundAcrossUnitBoundaries() throws {
        for (raw, expected) in [
            ("18973175.02", "₽19M"), ("18675011.86", "₽18,7M"),
            ("298163.16", "₽298K"), ("999950", "₽1M"),
            ("999999999", "₽1B"), ("123456789012345.125", "₽123T"),
            ("-298163.16", "-₽298K"), ("-0.004", "₽0"), ("42.55", "₽42,55")
        ] {
            let value = try XCTUnwrap(Decimal(string: raw))
            XCTAssertEqual(MoneyFormatter.compact(value, currency: "RUB"), expected)
            XCTAssertEqual(MoneyFormatter.parseInput(MoneyFormatter.editingText(value)), value)
        }
        XCTAssertEqual(MoneyFormatter.compact(1_867_500, currency: "RUB", showPositiveSign: true), "+₽1,87M")
        XCTAssertEqual(MoneyFormatter.compact(18_675_000, currency: "RUB", showPositiveSign: true, significantDigits: 2), "+₽19M")
        XCTAssertEqual(MoneyFormatter.compact(0, currency: "RUB", showPositiveSign: true), "₽0")
        XCTAssertEqual(MoneyFormatter.compact(Decimal(string: "999.5")!, currency: "KZT", roundToWhole: true), "₸1K")
        XCTAssertEqual(MoneyFormatter.compact(.nan, currency: "USD"), "Unavailable")
    }

    func testWholeTotalsRoundOnceWithoutChangingEditingPrecision() throws {
        for (raw, expected) in [
            ("1234.0000", "$1 234"), ("1234.4999", "$1 234"),
            ("1234.5000", "$1 235"), ("-1234.5", "-$1 235"),
            ("-0.49", "$0"), ("999.9999", "$1 000")
        ] {
            let value = try XCTUnwrap(Decimal(string: raw))
            XCTAssertEqual(MoneyFormatter.format(value, currency: "USD", roundToWhole: true), expected)
            XCTAssertEqual(MoneyFormatter.parseInput(MoneyFormatter.editingText(value)), value)
        }
        XCTAssertEqual(MoneyFormatter.format(.nan, currency: "USD", roundToWhole: true), "Unavailable")
        XCTAssertEqual(MoneyFormatter.format(10, currency: "USD", showPositiveSign: true, roundToWhole: true), "+$10")
        XCTAssertEqual(MoneyFormatter.format(10, currency: "USD"), "$10")
        XCTAssertEqual(MoneyFormatter.spoken(10, currency: "USD", locale: Locale(identifier: "en_US"), roundToWhole: true), "10 US dollars")
        XCTAssertEqual(MoneyFormatter.spoken(10, currency: "USD", locale: Locale(identifier: "en_US")), "10 US dollars")
        XCTAssertEqual(MoneyFormatter.spoken(Decimal(string: "10.5")!, currency: "USD", locale: Locale(identifier: "en_US")), "10.50 US dollars")
    }

    func testCurrencyExamplesOmitZeroFractionsAndKeepCents() throws {
        for (raw, currency, expected) in [
            ("62253.40", "KZT", "₸62 253,40"),
            ("62253.4", "kzt", "₸62 253,40"),
            ("62253", "KZT", "₸62 253"),
            ("-20000.0000", "KZT", "-₸20 000"),
            ("-286.00", "RUB", "-₽286"),
            ("40.1", "USD", "$40,10"),
            ("0", "KZT", "₸0"),
            ("1234.5", "EUR", "€1 234,50"),
            ("1234.5", "GBP", "£1 234,50"),
            ("1234", "JPY", "¥1 234"),
            ("1234.567", "KWD", "KWD1 234,57"),
            ("1234", "ZZZ", "ZZZ1 234"),
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
            ("999.9999", "₸1 000"),
            ("-0.004", "₸0"),
            ("123456789012345.125", "₸123 456 789 012 345,13"),
        ] {
            let value = try XCTUnwrap(Decimal(string: raw))
            XCTAssertEqual(MoneyFormatter.format(value, currency: "KZT"), expected)
        }
        XCTAssertEqual(MoneyFormatter.format(40, currency: "USD", showPositiveSign: true), "+$40")
        XCTAssertEqual(MoneyFormatter.format(-40, currency: "USD", showPositiveSign: true), "-$40")
        XCTAssertEqual(MoneyFormatter.format(0, currency: "USD", showPositiveSign: true), "$0")
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
