import SwiftUI
import UIKit
import XCTest
@testable import FinanceTracker

final class BudgetOverviewTests: XCTestCase {
    private let firstPool = UUID()
    private let secondPool = UUID()
    private let accountID = UUID()
    private let now = ISO8601DateFormatter().date(from: "2026-09-18T12:00:00Z")!

    func testGroupingUsesPoolIdentityAndKeepsEveryAssignmentVisible() {
        let food = category("Food")
        let travel = category("Travel")
        let personal = category("Personal")
        let unavailable = UUID()
        let budget = makeBudget([
            .init(categoryId: food.id, groupId: firstPool, limit: nil),
            .init(categoryId: travel.id, groupId: secondPool, limit: "80"),
            .init(categoryId: personal.id, groupId: nil, limit: "100"),
            .init(categoryId: unavailable, groupId: UUID(), limit: "20")
        ])
        let result = BudgetOverviewData(budget: budget, transactions: [], categories: [food, travel, personal])
        XCTAssertEqual(result.pools.map(\.id), [firstPool, secondPool])
        XCTAssertEqual(result.pools[0].categories.map(\.id), [food.id])
        XCTAssertEqual(result.pools[1].categories.map(\.id), [travel.id])
        XCTAssertEqual(Set(result.standaloneCategories.map(\.id)), [personal.id, unavailable])
        XCTAssertEqual(result.pools.flatMap(\.categories).count + result.standaloneCategories.count, 4)
        XCTAssertTrue(result.attention.isEmpty)
    }

    func testParentCategoryLimitsRetainSpendingWhenChildMovesPools() throws {
        let food = category("Food")
        let restaurants = category("Restaurants", parent: food.id)
        let budget = makeBudget([
            .init(categoryId: food.id, groupId: firstPool, limit: "50"),
            .init(categoryId: restaurants.id, groupId: secondPool, limit: "40")
        ])
        let result = BudgetOverviewData(budget: budget,
            transactions: [transaction("20", category: food), transaction("60", category: restaurants)],
            categories: [food, restaurants])
        XCTAssertEqual(result.pools.map { $0.progress.spent }, [20, 60])
        XCTAssertEqual(result.pools[0].categories.first?.spent, 80)
        XCTAssertEqual(result.pools[0].spendingOutsidePool[food.id], 60)
        XCTAssertTrue(result.pools[1].spendingOutsidePool.isEmpty)
        XCTAssertEqual(result.attention.map { $0.progress.remaining }, [-30, -20])
        XCTAssertTrue(result.attention.allSatisfy { !$0.isPool })
    }

    func testPoolAndCategoryOverspendingHaveSeparateDestinations() {
        let food = category("Food")
        let budget = makeBudget([.init(categoryId: food.id, groupId: firstPool, limit: "80")])
        let result = BudgetOverviewData(budget: budget, transactions: [transaction("150", category: food)], categories: [food])
        XCTAssertEqual(result.attention.count, 2)
        XCTAssertEqual(result.attention.map { $0.progress.remaining }, [-70, -50])
        XCTAssertEqual(result.attention.map(\.isPool), [false, true])
        XCTAssertEqual(Set(result.attention.map(\.id)).count, 2)
        XCTAssertTrue(result.pools[1].categories.isEmpty)
    }

    func testMonthMarkerUsesCompletedCalendarDaysAndHidesForOtherMonths() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12))!
        XCTAssertEqual(try XCTUnwrap(BudgetOverviewData.monthProgress(month: date, now: date, calendar: calendar)), 8.0 / 31, accuracy: 0.0001)
        for offset in [-1, 1] {
            let otherMonth = calendar.date(byAdding: .month, value: offset, to: date)!
            XCTAssertNil(BudgetOverviewData.monthProgress(month: otherMonth, now: date, calendar: calendar))
        }
        let firstDay = calendar.date(from: DateComponents(year: 2028, month: 2, day: 1))!
        let leapDay = calendar.date(from: DateComponents(year: 2028, month: 2, day: 29))!
        XCTAssertEqual(BudgetOverviewData.monthProgress(month: firstDay, now: firstDay, calendar: calendar), 0)
        XCTAssertEqual(try XCTUnwrap(BudgetOverviewData.monthProgress(month: leapDay, now: leapDay, calendar: calendar)), 28.0 / 29, accuracy: 0.0001)
    }

    @MainActor
    func testOverviewRendersSeparateNativePoolCardsInBothAppearances() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let defaults = UserDefaults(suiteName: "BudgetOverviewTests.Rendering")!
        defaults.set("USD", forKey: AppPreferences.defaultCurrencyKey)
        defer { defaults.removePersistentDomain(forName: "BudgetOverviewTests.Rendering") }
        let food = category("Food")
        let housing = category("Housing")
        let budget = makeBudget([
            .init(categoryId: food.id, groupId: firstPool, limit: "80"),
            .init(categoryId: housing.id, groupId: nil, limit: "329976")
        ])
        let spending = transaction("150", category: food, at: .now)
        for scheme in [ColorScheme.light, .dark] {
            let view = NavigationStack { BudgetOverviewView() }
                .environmentObject(AccountStore.preview(accounts: []))
                .environmentObject(TransactionStore.preview(transactions: [spending, transaction("30000", category: housing, at: .now)]))
                .environmentObject(BudgetStore.preview(budget))
                .defaultAppStorage(defaults)
                .preferredColorScheme(scheme)
                .environment(\.dynamicTypeSize, .large)
            let controller = UIHostingController(rootView: view)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            try await Task.sleep(for: .milliseconds(400))
            controller.view.layoutIfNeeded()
            func collection(in view: UIView) -> UICollectionView? {
                if let list = view as? UICollectionView { return list }
                return view.subviews.compactMap { collection(in: $0) }.first
            }
            let list = try XCTUnwrap(collection(in: controller.view))
            // Summary, attention, two pools, standalone categories, and the bottom spacer.
            XCTAssertGreaterThanOrEqual(list.numberOfSections, 6)
            XCTAssertGreaterThanOrEqual(list.visibleCells.count, 3)
            for cell in list.visibleCells {
                XCTAssertLessThanOrEqual(cell.frame.maxX, list.bounds.width)
                XCTAssertGreaterThanOrEqual(cell.frame.minX, 0)
            }
            let categoryIndex = IndexPath(item: 0, section: list.numberOfSections - 2)
            list.scrollToItem(at: categoryIndex, at: .bottom, animated: false)
            try await Task.sleep(for: .milliseconds(200))
            let categoryCell = try XCTUnwrap(list.cellForItem(at: categoryIndex))
            XCTAssertLessThanOrEqual(categoryCell.bounds.height, 82, "A category with a limit should fit a compact row")
            XCTAssertGreaterThanOrEqual(categoryCell.bounds.height, 44, "Keep the row comfortably tappable")
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Budget-overview-\(scheme)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testCollapsedBudgetTitleLeadsOnOlderIOS() async throws {
        guard #unavailable(iOS 26.0) else { return }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let defaults = UserDefaults(suiteName: "BudgetOverviewTests.Title")!
        defaults.set("USD", forKey: AppPreferences.defaultCurrencyKey)
        defer { defaults.removePersistentDomain(forName: "BudgetOverviewTests.Title") }
        let food = category("Food")
        let budget = makeBudget([.init(categoryId: food.id, groupId: firstPool, limit: "80")])
        for scheme in [ColorScheme.light, .dark] {
            let view = NavigationStack(path: .constant([1])) {
                Text("Home")
                    .navigationTitle("Home")
                    .navigationDestination(for: Int.self) { _ in BudgetOverviewView() }
            }
            .environmentObject(AccountStore.preview(accounts: []))
            .environmentObject(TransactionStore.preview(transactions: [transaction("150", category: food, at: .now)]))
            .environmentObject(BudgetStore.preview(budget))
            .defaultAppStorage(defaults)
            .preferredColorScheme(scheme)
            let controller = UIHostingController(rootView: view)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            try await Task.sleep(for: .milliseconds(500))
            func navigation(in controller: UIViewController) -> UINavigationController? {
                (controller as? UINavigationController) ?? controller.children.compactMap { navigation(in: $0) }.first
            }
            func collection(in view: UIView) -> UICollectionView? {
                (view as? UICollectionView) ?? view.subviews.compactMap { collection(in: $0) }.first
            }
            let navigation = try XCTUnwrap(navigation(in: controller))
            let page = try XCTUnwrap(navigation.topViewController)
            let list = try XCTUnwrap(collection(in: page.view))
            XCTAssertEqual(page.navigationItem.title, "Budget")
            XCTAssertGreaterThan(navigation.viewControllers.count, 1)
            let title = try XCTUnwrap(page.navigationItem.titleView as? LegacyLeadingNavigationTitle.TitleView)
            XCTAssertTrue(title.label.isHidden, "The expanded large title must not have a duplicate inline title")
            list.setContentOffset(CGPoint(x: 0, y: 260), animated: false)
            try await Task.sleep(for: .milliseconds(350))
            XCTAssertFalse(title.label.isHidden, "The inline title must appear when the large title collapses")
            let frame = title.label.convert(title.label.bounds, to: navigation.navigationBar)
            XCTAssertLessThan(frame.minX, 100, "The collapsed title should sit beside the back button")
            XCTAssertGreaterThanOrEqual(frame.width, title.label.intrinsicContentSize.width - 1)
            XCTAssertEqual(title.label.textAlignment, .left)
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Budget-collapsed-title-\(scheme)"
            attachment.lifetime = .keepAlways
            add(attachment)
            list.setContentOffset(CGPoint(x: 0, y: -list.adjustedContentInset.top), animated: false)
            try await Task.sleep(for: .milliseconds(350))
            XCTAssertTrue(title.label.isHidden, "Expanding the large title again must hide the inline title")
        }
    }

    @MainActor
    func testPoolHeadersFitNarrowWidthsInBothAppearancesAndExpansionStates() throws {
        for scheme in [ColorScheme.light, .dark] {
            for size in [DynamicTypeSize.large, .accessibility3] {
                for expanded in [false, true] {
                    let progress = BudgetLimitProgress(id: firstPool, name: "Everyday spending", limit: 200_000, spent: expanded ? 225_200 : 125_200)
                    let view = VStack(alignment: .leading, spacing: 16) {
                        BudgetPoolHeader(progress: progress, categoryCount: 2, iconName: "cart",
                            tint: BudgetGroupPalette.color(for: firstPool), monthProgress: 0.6,
                            isExpanded: expanded, currency: "KZT")
                        if expanded {
                            BudgetLimitRow(name: "Groceries", spent: 80_000, limit: nil, currency: "KZT") {
                                AppIcon("cart", size: 20)
                            }
                            BudgetLimitRow(name: "Restaurants", spent: 45_200, limit: 40_000, currency: "KZT") {
                                AppIcon("cutlery", size: 20)
                            }
                        }
                        BudgetLimitRow(name: "Housing", spent: expanded ? 30_000 : 0, limit: 329_976, currency: "KZT",
                                       tint: AppColor.iconForeground(for: .indigo)) {
                            AppIcon("home-simple", size: 16)
                                .foregroundStyle(AppColor.iconForeground(for: .indigo))
                                .frame(width: 32, height: 32)
                        }
                        BudgetAttentionRow(item: .init(progress: .init(id: firstPool, name: "Restaurants", limit: 40_000, spent: 45_200), isPool: false), currency: "KZT")
                    }
                    .padding(16)
                    .frame(width: 320)
                    .background(AppColor.elevatedSurface)
                    .environment(\.dynamicTypeSize, size)
                    .environment(\.locale, Locale(identifier: "en_US"))
                    .environment(\.colorScheme, scheme)
                    let renderer = ImageRenderer(content: view)
                    let image = try XCTUnwrap(renderer.uiImage)
                    XCTAssertEqual(image.size.width, 320, accuracy: 0.5)
                    // The fixture includes both pooled categories and a standalone limit.
                    XCTAssertLessThan(image.size.height, size.isAccessibilitySize ? 1300 : 600)
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "Budget-\(scheme)-\(size)-\(expanded ? "expanded-over" : "collapsed")"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    private func makeBudget(_ assignments: [BudgetCategoryAssignment]) -> MonthlyBudget {
        MonthlyBudget(id: UUID(), accountId: nil, currency: "USD", monthlyLimit: "200",
            groups: [.init(id: secondPool, name: "Same name", limit: "100", sortOrder: 1),
                     .init(id: firstPool, name: "Same name", limit: "100", sortOrder: 0)],
            categoryAssignments: assignments, createdAt: now, updatedAt: now)
    }

    private func category(_ name: String, parent: UUID? = nil) -> TransactionCategory {
        TransactionCategory(id: UUID(), systemKey: nil, name: name, kind: .expense, parentId: parent,
            icon: "cart", color: .blue, isSystem: false, examples: nil, sortOrder: nil, createdAt: nil, updatedAt: nil)
    }

    private func transaction(_ amount: String, category: TransactionCategory, at date: Date? = nil) -> FinanceTransaction {
        FinanceTransaction(id: UUID(), accountId: accountID, kind: .expense, amount: amount, currency: "USD",
            category: category, note: nil, occurredAt: date ?? now, createdAt: now, updatedAt: now)
    }
}
