import XCTest
import SwiftUI
@testable import FinanceTracker

final class MoneyFormatterTests: XCTestCase {
    @MainActor
    func testConvertedRowsRenderInBothAppearancesAndAtAccessibilitySizes() throws {
        let now = Date(timeIntervalSince1970: 0)
        let account = Account(id: UUID(), name: "Everyday card", currency: "KZT", icon: "wallet", iconColor: .blue, createdAt: "", updatedAt: "")
        let transaction = FinanceTransaction(id: UUID(), accountId: account.id, kind: .expense, amount: "200", currency: "RUB", category: nil,
            note: "Coffee", occurredAt: now, createdAt: now, updatedAt: now)
        let rates = ExchangeRateSnapshot(baseCurrency: "RUB", reportingCurrency: "KZT",
            quotes: [ExchangeRateQuote(currency: "KZT", rate: "5", effectiveDate: "2026-09-11")], fetchedAt: now, stale: false)
        for scheme in [ColorScheme.light, .dark] {
            for size in [DynamicTypeSize.large, .accessibility3] {
                let content = VStack(spacing: 24) {
                    TransactionRow(transaction: transaction, account: account, displayCurrency: "KZT", exchangeRates: rates)
                    TransactionRow(transaction: transaction, account: account, recurrenceDetails: "Monthly · 28 February", style: .upcoming,
                                   displayCurrency: "KZT", exchangeRates: rates)
                }
                .padding(20)
                .frame(width: 350)
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(uiColor: .systemBackground))
                .environment(\.colorScheme, scheme)
                .environment(\.dynamicTypeSize, size)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.uiImage)
                XCTAssertEqual(image.size.width, 350)
                XCTAssertGreaterThan(image.size.height, 100)
                let attachment = XCTAttachment(image: image)
                attachment.name = "Currency-rows-\(scheme)-\(size)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testTransactionDisplayConvertsWithoutChangingTheOriginalAndFallsBackWithoutRates() {
        let now = Date(timeIntervalSince1970: 0)
        let rates = ExchangeRateSnapshot(baseCurrency: "USD", reportingCurrency: "USD", quotes: [
            ExchangeRateQuote(currency: "RUB", rate: "100", effectiveDate: "2026-09-11"),
            ExchangeRateQuote(currency: "KZT", rate: "500", effectiveDate: "2026-09-11")
        ], fetchedAt: now, stale: false)
        for kind in TransactionKind.allCases {
            let transaction = FinanceTransaction(id: UUID(), accountId: UUID(), kind: kind, amount: "200", currency: "RUB",
                category: nil, note: nil, occurredAt: now, createdAt: now, updatedAt: now)
            let accountDisplay = TransactionAmountDisplay(transaction, currency: "KZT", rates: rates)
            XCTAssertEqual(accountDisplay.primary, kind == .income ? "≈+₸1 000" : "≈-₸1 000")
            XCTAssertEqual(accountDisplay.original, kind == .income ? "+₽200" : "-₽200")
            let allAccountsDisplay = TransactionAmountDisplay(transaction, currency: nil, rates: rates)
            XCTAssertEqual(allAccountsDisplay.primary, kind == .income ? "+₽200" : "-₽200")
            XCTAssertNil(allAccountsDisplay.original)
            let upcomingDisplay = TransactionAmountDisplay(transaction, currency: "KZT", rates: rates, showExpenseSign: false)
            XCTAssertEqual(upcomingDisplay.primary, kind == .income ? "≈+₸1 000" : "≈₸1 000")
            for currency in ["RUB", "rub", "EUR"] {
                let unchanged = TransactionAmountDisplay(transaction, currency: currency, rates: rates)
                XCTAssertEqual(unchanged.primary, transaction.formattedAmount())
                XCTAssertNil(unchanged.original)
            }
            let unavailable = TransactionAmountDisplay(transaction, currency: "KZT", rates: nil)
            XCTAssertEqual(unavailable.primary, transaction.formattedAmount())
            XCTAssertNil(unavailable.original)
            XCTAssertEqual(transaction.amount, "200")
            XCTAssertEqual(transaction.currency, "RUB")
        }
    }

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
                currency: transaction.currency, category: nil, note: nil,
                frequency: .monthly, occurredAt: date,
                counterparty: nil
            )
            XCTAssertEqual(transaction.formattedAmount(), kind == .income ? "+₸62 253,40" : "-₸62 253,40")
            XCTAssertEqual(upcoming.amountText, kind == .income ? "+₸62 253,40" : "₸62 253,40")
            XCTAssertEqual(upcoming.amountText, upcoming.formattedAmount(showExpenseSign: false))
        }
    }
}
