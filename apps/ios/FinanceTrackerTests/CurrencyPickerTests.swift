import SwiftUI
import XCTest
@testable import FinanceTracker

@MainActor
final class CurrencyPickerTests: XCTestCase {
    func testSectionsKeepSelectionAndFavoritesUnique() {
        let catalog = CurrencyPickerCatalog(
            currencyCodes: ["USD", "KZT", "EUR", "AED", "USD", "ADP"],
            selection: "KZT", favorites: ["KZT", "USD", "EUR"], query: ""
        )
        XCTAssertEqual(catalog.selected, ["KZT"])
        XCTAssertEqual(catalog.favorites, ["EUR", "USD"])
        XCTAssertEqual(catalog.others, ["AED"])
    }

    func testSearchFindsNamesCodesAndHistoricalCurrencies() {
        let codes = ["USD", "KZT", "EUR", "AED", "ADP"]
        func search(_ query: String) -> CurrencyPickerCatalog {
            CurrencyPickerCatalog(currencyCodes: codes, selection: "KZT", favorites: ["USD"],
                                  query: query, locale: Locale(identifier: "en_US"))
        }
        XCTAssertEqual(search("  usd \n").favorites, ["USD"])
        XCTAssertEqual(search("emirates").others, ["AED"])
        XCTAssertEqual(search("adp").others, ["ADP"])
        XCTAssertTrue(search("no matching currency").isEmpty)
        XCTAssertTrue(search("usd").selected.isEmpty)
    }

    func testSavedHistoricalChoicesRemainVisibleAndFavoritesCanBeRemoved() {
        let catalog = CurrencyPickerCatalog(currencyCodes: ["USD", "ADP"], selection: "AFA",
                                            favorites: ["ADP"], query: "")
        XCTAssertEqual(catalog.selected, ["AFA"])
        XCTAssertEqual(catalog.favorites, ["ADP"])
        XCTAssertEqual(catalog.others, ["USD"])
        let removed = CurrencyPickerCatalog(currencyCodes: ["USD", "EUR"], selection: "USD",
                                            favorites: [], query: "")
        XCTAssertTrue(removed.favorites.isEmpty)
        XCTAssertEqual(removed.others, ["EUR"])
    }

    func testSmallExchangeRatesDoNotRoundToZero() {
        XCTAssertEqual(CurrencyPickerRow.formattedRate(Decimal(string: "0.000002184")!), "0,000002184")
        XCTAssertEqual(CurrencyPickerRow.formattedRate(Decimal(string: "0.002")!), "0,002")
        XCTAssertEqual(CurrencyPickerRow.formattedRate(Decimal(string: "12500")!), "12 500")
    }

    func testPickerAndHelpRenderInLightAndDark() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let repository = try LocalTestData.repository()
        let transport = TestRateTransport()
        let service = DailyRateService(repository: repository, transport: transport)
        await service.refreshIfNeeded()
        let rates = ExchangeRateStore(repository: repository, service: service)
        let suite = "CurrencyPicker-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("USD,EUR", forKey: AppPreferences.favoriteCurrenciesKey)

        for scheme in [ColorScheme.light, .dark] {
            try await capture(NavigationStack {
                CurrencyPickerView(selection: .constant("KZT"),
                                   currencyCodes: AppPreferences.currencyCodes,
                                   title: "Default currency", rateStore: rates)
            }.defaultAppStorage(defaults), name: "Currency-picker-\(scheme)", scheme: scheme, scene: scene)
            try await capture(CurrencyRateHelpView(), name: "Currency-help-\(scheme)", scheme: scheme, scene: scene)
            try await capture(rowSamples, name: "Currency-states-\(scheme)", scheme: scheme, scene: scene)
            try await capture(rowSamples.dynamicTypeSize(.accessibility3),
                              name: "Currency-large-text-\(scheme)", scheme: scheme, scene: scene)
            let emptyRepository = try LocalTestData.repository()
            let loadingService = DailyRateService(repository: emptyRepository, transport: LoadingRates())
            let loadingStore = ExchangeRateStore(repository: emptyRepository, service: loadingService)
            try await capture(NavigationStack {
                CurrencyPickerView(selection: .constant("KZT"), currencyCodes: ["KZT", "USD", "EUR"],
                                   rateStore: loadingStore)
            }.defaultAppStorage(defaults), name: "Currency-loading-\(scheme)", scheme: scheme, scene: scene)
        }
    }

    private struct LoadingRates: RateTransport {
        func fullExchangeRateTable() async throws -> ExchangeRateSnapshot {
            try await Task.sleep(for: .seconds(3))
            throw URLError(.notConnectedToInternet)
        }
    }

    private var rowSamples: some View {
        ScrollView {
            VStack(spacing: AppSpacing.medium) {
                CurrencyPickerRow(code: "KZT", name: "Kazakhstani Tenge", rate: 1, baseCurrency: "KZT",
                                  isSelected: true, isFavorite: true, select: {}, toggleFavorite: {})
                CurrencyPickerRow(code: "AED", name: "United Arab Emirates Dirham", rate: Decimal(string: "0.0073"),
                                  baseCurrency: "KZT", isSelected: false, isFavorite: false,
                                  select: {}, toggleFavorite: {})
                CurrencyPickerRow(code: "AFN", name: "Afghan Afghani", rate: nil, baseCurrency: "KZT",
                                  isSelected: false, isFavorite: false, select: {}, toggleFavorite: {})
                CurrencyPickerRow(code: "USD", name: "US Dollar", rate: Decimal(string: "0.002"), baseCurrency: "KZT",
                                  isSelected: false, isFavorite: true, select: {}, toggleFavorite: {})
                    .disabled(true)
            }
            .padding(AppSpacing.large)
        }
        .background(AppColor.groupedBackground)
    }

    private func capture<Content: View>(_ content: Content, name: String, scheme: ColorScheme,
                                       scene: UIWindowScene) async throws {
        let controller = UIHostingController(rootView: content.tint(AppColor.accent).preferredColorScheme(scheme))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.frame = window.bounds
        try await Task.sleep(for: .milliseconds(350))
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
