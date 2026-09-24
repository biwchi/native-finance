import SwiftUI
import UIKit
import XCTest
import Vision
@testable import FinanceTracker

@MainActor
final class LegacyAppearanceTests: XCTestCase {
    func testRowActionsShowTwoTapTargetsBeforeCollapsingToMenu() async throws {
        let actions: [AppRowActions.Action] = [
            .init(title: "Review", icon: "view") {},
            .init(title: "Dismiss", icon: "xmark", role: .destructive) {},
            .init(title: "Retry", icon: "refresh") {},
        ]
        for scheme in [ColorScheme.light, .dark] {
            for count in 1...3 {
                let content = AppRowActions(actions: Array(actions.prefix(count)))
                    .environment(\.colorScheme, scheme)
                    .environment(\.dynamicTypeSize, .accessibility1)
                let controller = UIHostingController(rootView: content)
                let size = controller.sizeThatFits(in: CGSize(width: 300, height: 100))
                XCTAssertEqual(size.width, count == 2 ? 96 : 44, accuracy: 0.5)
                XCTAssertGreaterThanOrEqual(size.height, AppControlSize.minimumTapTarget)
            }
            let window = try makeWindow(AppList {
                AppSection("Actions") {
                    ForEach(1...3, id: \.self) { count in
                        HStack {
                            Text("\(count) actions")
                            Spacer()
                            AppRowActions(actions: Array(actions.prefix(count)))
                        }
                    }
                }
            }.preferredColorScheme(scheme))
            defer { window.isHidden = true }
            try await settle(window)
            attach(window, name: "Row-actions-\(scheme)")
        }
    }

    func testFinancesUsesReferenceInsetsAndRowHeightsInBothAppearances() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let window = try makeWindow(NavigationStack { FinancesView() }.preferredColorScheme(scheme))
            defer { window.isHidden = true }
            try await settle(window)
            let list = try XCTUnwrap(findCollection(in: window))
            let rows = list.visibleCells.sorted { $0.frame.minY < $1.frame.minY }
            XCTAssertGreaterThanOrEqual(rows.count, 3)
            for row in rows.prefix(3) {
                XCTAssertEqual(row.frame.minX, 16, accuracy: 0.5)
                XCTAssertEqual(row.frame.width, window.bounds.width - 32, accuracy: 0.5)
                XCTAssertEqual(row.frame.height, 94, accuracy: 0.5)
                if #unavailable(iOS 26.0) {
                    XCTAssertEqual(row.layer.cornerRadius, 26)
                    XCTAssertEqual(row.layer.cornerCurve, .continuous)
                }
            }
            try assertTitleIsClear("Finances", pointSize: 34, in: window)
            attach(window, name: "Finances-\(scheme)")
        }
    }

    func testLegacyCornersSurviveCellReuseAndAppearanceChanges() async throws {
        guard #unavailable(iOS 26.0) else { throw XCTSkip("Native sections own iOS 26 rounding") }
        let window = try makeWindow(AppList {
            AppSection("Items") {
                ForEach(0..<60) { Text("Item \($0)") }
            }
        }.listStyle(.insetGrouped))
        defer { window.isHidden = true }
        try await settle(window)
        let list = try XCTUnwrap(findCollection(in: window))
        let delegate = list.delegate
        let dataSource = list.dataSource
        let first = try XCTUnwrap(list.visibleCells.first { $0.layer.cornerRadius > 0 })
        let corners = first.layer.maskedCorners
        // UIKit reconfigures these layers on selection and reuse.
        first.layer.cornerRadius = 10
        XCTAssertEqual(first.layer.cornerRadius, 26)
        XCTAssertEqual(first.layer.maskedCorners, corners)
        for style in [UIUserInterfaceStyle.dark, .light] {
            window.overrideUserInterfaceStyle = style
            for offset in [CGFloat(900), 1800, 0] {
                list.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
                try await settle(window)
                let roundedRows = list.visibleCells.filter { $0.layer.cornerRadius > 0 }
                XCTAssertFalse(roundedRows.isEmpty)
                XCTAssertTrue(roundedRows.allSatisfy { $0.layer.cornerRadius == 26 })
            }
        }
        XCTAssertTrue(list.delegate === delegate)
        XCTAssertTrue(list.dataSource === dataSource)
    }

    func testCustomRowInsetsAndHeightArePreserved() async throws {
        let window = try makeWindow(AppList {
            AppSection {
                Color.blue.frame(height: 80)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }.listStyle(.insetGrouped))
        defer { window.isHidden = true }
        try await settle(window)
        let list = try XCTUnwrap(findCollection(in: window))
        let row = try XCTUnwrap(list.visibleCells.first { $0.frame.height >= 80 })
        XCTAssertEqual(row.frame.height, 80, accuracy: 0.5)
    }

    func testGlassControlsAtAccessibilityTextSize() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let window = try makeWindow(VStack(spacing: 20) {
                TransactionModeSelector(modes: QuickTransactionMode.allCases, selection: .constant(.expense))
                PrimaryIconButton("Add", iconName: "plus", appearance: .glass) {}
                PrimaryIconButton("Disabled", iconName: "plus", appearance: .glass) {}.disabled(true)
                PrimaryActionButton("Save", appearance: .glass) {}
                PrimaryActionButton("Saving", isLoading: true, appearance: .glass) {}
                PrimaryActionButton("Disabled", appearance: .glass) {}.disabled(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColor.groupedBackground)
            .environment(\.dynamicTypeSize, .accessibility1)
            .preferredColorScheme(scheme))
            defer { window.isHidden = true }
            try await settle(window)
            attach(window, name: "Large-text-controls-\(scheme)")
        }
    }

    func testSectionHeadersKeepTheirOriginalCaseAfterLayoutAndScrolling() async throws {
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 12))!
        for scheme in [ColorScheme.light, .dark] {
            let window = try makeWindow(AppList {
                AppSection {
                    Text("Coffee")
                } header: {
                    Text(date, format: .dateTime.month(.wide).day().year())
                        .opacity(1)
                }
                AppSection("Spending pools") {
                    ForEach(0..<30) { Text("Item \($0)") }
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.locale, Locale(identifier: "en_GB"))
            .preferredColorScheme(scheme))
            defer { window.isHidden = true }
            try await settle(window)
            let list = try XCTUnwrap(findCollection(in: window))
            list.setContentOffset(CGPoint(x: 0, y: 500), animated: false)
            try await settle(window)
            list.setContentOffset(CGPoint(x: 0, y: -list.adjustedContentInset.top), animated: false)
            try await Task.sleep(for: .seconds(1))
            let image = screenshot(window)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-GB"]
            try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage), options: [:]).perform([request])
            let labels = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            XCTAssertTrue(labels.contains("10 September 2026"), "Rendered headers: \(labels)")
            XCTAssertTrue(labels.contains("Spending pools"), "Rendered headers: \(labels)")
            attach(window, name: "Header-case-\(scheme)")
        }
    }

    func testAccountToolbarAndOverviewSpacing() async throws {
        let accounts = AccountStore.preview(accounts: [])
        let transactions = TransactionStore.preview(transactions: [])
        let defaults = UserDefaults(suiteName: "LegacyAppearanceTests.AccountToolbar")!
        defaults.set("USD", forKey: AppPreferences.defaultCurrencyKey)
        defer { defaults.removePersistentDomain(forName: "LegacyAppearanceTests.AccountToolbar") }
        for scheme in [ColorScheme.light, .dark] {
            let window = try makeWindow(NavigationStack {
                AppList(usesCompactTopSpacing: true) {
                    AppSection {
                        FinancePageHeader(dateSelection: .constant(FinanceDateFilter()))
                        Color.gray.frame(height: 220).listRowInsets(EdgeInsets())
                    }
                    .modifier(FinanceSectionMargins())
                    AppSection("10 September 2026") { Text("Coffee") }
                }
                .listStyle(.insetGrouped)
                .listSectionSpacing(.custom(AppSpacing.large))
                .environment(\.defaultMinListRowHeight, 0)
                .environment(\.defaultMinListHeaderHeight, 0)
                .leadingAccountSelectorToolbar()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 0) {
                            AppIcon("view-grid").frame(width: 44, height: 44)
                            AppIcon("settings").frame(width: 44, height: 44)
                        }.legacyToolbarControl(horizontalPadding: 0)
                    }
                }
            }
            .environmentObject(accounts)
            .environmentObject(transactions)
            .defaultAppStorage(defaults)
            .preferredColorScheme(scheme))
            defer { window.isHidden = true }
            try await Task.sleep(for: .seconds(1))
            attach(window, name: "Account-toolbar-\(scheme)")
            let list = try XCTUnwrap(findCollection(in: window))
            let rows = list.visibleCells.sorted { $0.frame.minY < $1.frame.minY }
            XCTAssertEqual(rows.count, 3)
            guard rows.count == 3 else { continue }
            XCTAssertEqual(rows[0].frame.height, 56, accuracy: 0.5)
            XCTAssertEqual(rows[1].frame.minY, rows[0].frame.maxY, accuracy: 0.5)
            XCTAssertEqual(rows[1].frame.height, 220, accuracy: 0.5)
            // iOS 26 reference at the standard text size, including the date header.
            XCTAssertEqual(rows[2].frame.minY - rows[1].frame.maxY, 48.333, accuracy: 0.5)
            for row in rows {
                XCTAssertEqual(row.frame.minX, 16, accuracy: 0.5)
                XCTAssertEqual(row.frame.width, window.bounds.width - 32, accuracy: 0.5)
            }
        }
    }

    func testNativeAccountToolbarAppearance() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Native toolbar glass requires iOS 26") }
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository, name: "Travel", currency: "USD")
        let accounts = AccountStore(repository: repository)
        let transactions = TransactionStore(repository: repository)
        let suiteName = "LegacyAppearanceTests.NativeAccountToolbar"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set("USD", forKey: AppPreferences.defaultCurrencyKey)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        for scheme in [ColorScheme.light, .dark] {
            for state in ["all", "selected", "disabled"] {
                accounts.selectedAccountID = state == "selected" ? account.id : nil
                let window = try makeWindow(NavigationStack {
                    AppList {
                        AppSection {
                            FinancePageHeader(dateSelection: .constant(FinanceDateFilter()))
                            Text("Account selector appearance").frame(height: 220)
                        }
                    }
                    .financePage()
                    .leadingAccountSelectorToolbar()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            HStack(spacing: 0) {
                                Button {} label: { AppIcon("view-grid").frame(width: 44, height: 44) }
                                Button {} label: { AppIcon("settings").frame(width: 44, height: 44) }
                            }
                        }
                    }
                    .disabled(state == "disabled")
                }
                .environmentObject(accounts)
                .environmentObject(transactions)
                .defaultAppStorage(defaults)
                .preferredColorScheme(scheme))
                defer { window.isHidden = true }
                try await Task.sleep(for: .seconds(1))
                attach(window, name: "Native-account-\(scheme)-\(state)")
                if state == "selected" {
                    let badge = try blueBadgeBounds(in: screenshot(window))
                    XCTAssertEqual(badge.width, 36, accuracy: 0.5, "The toolbar must not clip the circular badge")
                    XCTAssertEqual(badge.height, 36, accuracy: 0.5)
                    XCTAssertEqual(badge.minX, 20, accuracy: 0.5, "Keep a four-point inset inside the toolbar capsule")
                }
            }
        }
    }

    private func blueBadgeBounds(in image: UIImage) throws -> CGRect {
        let cgImage = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: cgImage.width, height: cgImage.height,
                bitsPerComponent: 8, bytesPerRow: cgImage.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        }
        var minX = cgImage.width, minY = cgImage.height, maxX = -1, maxY = -1
        // The fixture's blue account badge is the only colored content in this toolbar region.
        for y in 0..<min(cgImage.height, Int(150 * image.scale)) {
            for x in 0..<min(cgImage.width, Int(100 * image.scale)) {
                let index = (y * cgImage.width + x) * 4
                if Int(pixels[index + 2]) - Int(pixels[index]) > 12 {
                    minX = min(minX, x); minY = min(minY, y)
                    maxX = max(maxX, x); maxY = max(maxY, y)
                }
            }
        }
        XCTAssertGreaterThanOrEqual(maxX, minX, "The selected account badge must be visible")
        return CGRect(x: CGFloat(minX) / image.scale, y: CGFloat(minY) / image.scale,
                      width: CGFloat(maxX - minX + 1) / image.scale,
                      height: CGFloat(maxY - minY + 1) / image.scale)
    }

    func testSettingsRowsAndSectionSpacingMatchReference() async throws {
        let suiteName = "LegacyAppearanceTests.Settings"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set("KZT", forKey: AppPreferences.defaultCurrencyKey)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        for scheme in [ColorScheme.light, .dark] {
            defaults.set(scheme == .dark ? AppTheme.dark.rawValue : AppTheme.light.rawValue,
                         forKey: AppPreferences.themeKey)
            let window = try makeWindow(NavigationStack {
                SettingsView().navigationBarTitleDisplayMode(.inline)
            }
            .defaultAppStorage(defaults)
            .environment(\.locale, Locale(identifier: "en_GB"))
            .preferredColorScheme(scheme))
            defer { window.isHidden = true }
            try await Task.sleep(for: .seconds(1))
            let list = try XCTUnwrap(findCollection(in: window))
            // Locate Categories and Default currency even if a sync warning is present above them.
            let preferences = try XCTUnwrap((0..<list.numberOfSections).first {
                list.numberOfItems(inSection: $0) == 2
            })
            func row(_ section: Int, _ item: Int = 0) throws -> CGRect {
                try XCTUnwrap(list.layoutAttributesForItem(at: IndexPath(item: item, section: section))).frame
            }
            let categories = try row(preferences)
            let currency = try row(preferences, 1)
            XCTAssertEqual(list.numberOfItems(inSection: preferences + 1), 4)
            let theme = try row(preferences + 1)
            let weekday = try row(preferences + 1, 1)
            let roundTotals = try row(preferences + 1, 2)
            let budgetSummary = try row(preferences + 1, 3)
            let quickEntry = try row(preferences + 2)
            let reminders = try row(preferences + 3)
            for frame in [categories, currency, theme, weekday, roundTotals, budgetSummary, quickEntry, reminders] {
                XCTAssertEqual(frame.height, 52, accuracy: 0.5)
                XCTAssertEqual(frame.minX, 16, accuracy: 0.5)
                XCTAssertEqual(frame.width, window.bounds.width - 32, accuracy: 0.5)
            }
            XCTAssertEqual(theme.minY - currency.maxY, 58, accuracy: 0.5)
            XCTAssertGreaterThan(quickEntry.minY - budgetSummary.maxY, 58)
            XCTAssertGreaterThan(reminders.minY - quickEntry.maxY, 58)
            attach(window, name: "Settings-spacing-\(scheme)")
        }
    }

    func testBackControlIsInstalledBeforeTransitionsAndSurvivesToolbarUpdates() async throws {
        guard #unavailable(iOS 26.0) else { throw XCTSkip("iOS 26 owns its navigation controls") }
        for scheme in [ColorScheme.light, .dark] {
            let route = NavigationRoute()
            let window = try makeWindow(NavigationFixture(route: route).preferredColorScheme(scheme))
            defer { window.isHidden = true }
            try await settle(window)
            let navigation = try XCTUnwrap(navigationController(in: window.rootViewController))
            let delegate = navigation.delegate
            withAnimation { route.path = [1] }
            try await assertBackControlsDuringTransition(navigation)
            window.layoutIfNeeded()
            let item = try XCTUnwrap(navigation.topViewController?.navigationItem)
            let back = try XCTUnwrap(findBackButton(in: navigation.navigationBar))
            XCTAssertTrue(item.hidesBackButton)
            XCTAssertEqual(back.bounds.width, 44, accuracy: 0.5)
            XCTAssertEqual(back.bounds.height, 44, accuracy: 0.5)
            let frame = back.convert(back.bounds, to: navigation.navigationBar)
            XCTAssertGreaterThanOrEqual(frame.minY, -0.5, "The circle must fit below the top of the bar")
            XCTAssertLessThanOrEqual(frame.maxY, navigation.navigationBar.bounds.maxY + 0.5)
            let title = try XCTUnwrap(item.titleView as? LegacyLeadingNavigationTitle.TitleView)
            let titleFrame = title.label.convert(title.label.bounds, to: navigation.navigationBar)
            XCTAssertGreaterThanOrEqual(titleFrame.minX - frame.maxX, 8, "The title needs a gap after the back control")

            XCTAssertTrue(navigation.delegate === delegate)
            let gesture = try XCTUnwrap(navigation.interactivePopGestureRecognizer)
            XCTAssertTrue(gesture.isEnabled)
            XCTAssertEqual(gesture.delegate?.gestureRecognizer?(gesture, shouldReceive: UIEvent()), true)
            XCTAssertEqual(gesture.delegate?.gestureRecognizerShouldBegin?(gesture), true)
            gesture.isEnabled = false
            XCTAssertTrue(gesture.isEnabled, "SwiftUI disabling the native back item must not disable edge pans")
            attach(window, name: "Navigation-back-\(scheme)")

            back.isHighlighted = true
            XCTAssertEqual(back.alpha, 0.55, accuracy: 0.001)
            back.isHighlighted = false
            back.isEnabled = false
            XCTAssertEqual(back.alpha, 0.35, accuracy: 0.001)
            back.isEnabled = true
            XCTAssertEqual(back.alpha, 1)

            route.isSaving = true
            try await settle(window)
            XCTAssertFalse(back.isEnabled, "A save must block the custom Back button")
            XCTAssertEqual(gesture.delegate?.gestureRecognizer?(gesture, shouldReceive: UIEvent()), false)
            XCTAssertEqual(gesture.delegate?.gestureRecognizerShouldBegin?(gesture), false)
            back.sendActions(for: .touchUpInside)
            XCTAssertEqual(route.path, [1])
            route.isSaving = false
            try await settle(window)
            XCTAssertTrue(back.isEnabled)

            withAnimation { route.path = [1, 2] }
            try await assertBackControlsDuringTransition(navigation)
            let nested = try XCTUnwrap(findBackButton(in: navigation.navigationBar))
            XCTAssertEqual(nested.ancestorActions().map(\.title), ["Budget", "Home"])
            nested.sendActions(for: .touchUpInside)
            try await assertBackControlsDuringTransition(navigation)
            XCTAssertEqual(route.path, [1], "Back must keep the SwiftUI path in sync")
            let restored = try XCTUnwrap(findBackButton(in: navigation.navigationBar))
            restored.sendActions(for: .touchUpInside)
            try await assertBackControlsDuringTransition(navigation)
            XCTAssertEqual(route.path, [])
            XCTAssertNil(findBackButton(in: navigation.navigationBar))
            XCTAssertEqual(gesture.delegate?.gestureRecognizerShouldBegin?(gesture), false)
        }
    }

    func testStandaloneToolbarIconsHaveEqualCircularBounds() async throws {
        guard #unavailable(iOS 26.0) else { throw XCTSkip("Native glass owns iOS 26 geometry") }
        for scheme in [ColorScheme.light, .dark] {
            for icon in ["plus", "settings", "xmark", "information-circle", "help-circle"] {
                let control = Button {} label: { Label("Action", icon: icon) }
                    .legacyToolbarIcon()
                    .environment(\.dynamicTypeSize, .accessibility1)
                let host = UIHostingController(rootView: control)
                let size = host.sizeThatFits(in: CGSize(width: 200, height: 100))
                XCTAssertEqual(size.width, 44, accuracy: 0.5, icon)
                XCTAssertEqual(size.height, 44, accuracy: 0.5, icon)
            }
            let window = try makeWindow(NavigationStack {
                AppList { Text("Toolbar geometry") }
                    .navigationTitle("Icons")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {} label: { Label("Add", icon: "plus") }.legacyToolbarIcon()
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {} label: { Label("Settings", icon: "settings") }.legacyToolbarIcon()
                        }
                    }
            }.preferredColorScheme(scheme))
            defer { window.isHidden = true }
            try await settle(window)
            attach(window, name: "Circular-toolbar-icons-\(scheme)")
        }
    }

    func testLargeNavigationTitleCollapsesWithSpaceForBackAndMonthControls() async throws {
        guard #unavailable(iOS 26.0) else { throw XCTSkip("iOS 26 owns large-title layout") }
        for scheme in [ColorScheme.light, .dark] {
            let route = NavigationRoute()
            let window = try makeWindow(NavigationFixture(route: route, usesLargeTitle: true).preferredColorScheme(scheme))
            defer { window.isHidden = true }
            try await settle(window)
            withAnimation { route.path = [1] }
            let navigation = try XCTUnwrap(navigationController(in: window.rootViewController))
            try await assertBackControlsDuringTransition(navigation)
            let title = try XCTUnwrap(navigation.topViewController?.navigationItem.titleView as? LegacyLeadingNavigationTitle.TitleView)
            XCTAssertTrue(title.label.isHidden, "The expanded page must show only its large title")
            attach(window, name: "Navigation-large-\(scheme)")
            let list = try XCTUnwrap(findCollection(in: window))
            list.setContentOffset(CGPoint(x: 0, y: 250), animated: false)
            try await settle(window)
            let back = try XCTUnwrap(findBackButton(in: navigation.navigationBar))
            let backFrame = back.convert(back.bounds, to: navigation.navigationBar)
            let titleFrame = title.label.convert(title.label.bounds, to: navigation.navigationBar)
            XCTAssertFalse(title.label.isHidden)
            XCTAssertGreaterThanOrEqual(backFrame.minY, -0.5)
            XCTAssertGreaterThanOrEqual(titleFrame.minX - backFrame.maxX, 8)
            XCTAssertGreaterThan(titleFrame.width, 0)
            attach(window, name: "Navigation-collapsed-\(scheme)")
        }
    }

    private func findBackButton(in view: UIView) -> LegacyNavigationAppearance.BackButton? {
        if let button = view as? LegacyNavigationAppearance.BackButton { return button }
        return view.subviews.lazy.compactMap { self.findBackButton(in: $0) }.first
    }

    private func assertBackControlsDuringTransition(_ navigation: UINavigationController) async throws {
        var sawAnimatedTransition = false
        for frameIndex in 0..<40 {
            try await Task.sleep(for: .milliseconds(16))
            sawAnimatedTransition = sawAnimatedTransition || navigation.transitionCoordinator?.isAnimated == true
            if [4, 12].contains(frameIndex), let window = navigation.view.window {
                attach(window, name: "Navigation-transition-\(frameIndex)")
            }
            for item in (navigation.navigationBar.items ?? []).dropFirst() {
                XCTAssertTrue(item.hidesBackButton, "Every transition frame must hide the native back item")
            }
        }
        XCTAssertTrue(sawAnimatedTransition, "Custom back controls must retain animated navigation")
    }

    func testLegacyNavigationDoesNotModifyIOS26() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Checks the native iOS 26 path") }
        let root = UIViewController()
        let destination = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        navigation.pushViewController(destination, animated: false)
        let original = navigation.navigationBar.standardAppearance.backIndicatorImage
        LegacyNavigationAppearance.apply(to: navigation)
        XCTAssertEqual(navigation.navigationBar.standardAppearance.backIndicatorImage, original)
        XCTAssertNil(destination.navigationItem.leftBarButtonItem)
        XCTAssertFalse(destination.navigationItem.hidesBackButton)

        let route = NavigationRoute()
        let window = try makeWindow(NavigationFixture(route: route))
        defer { window.isHidden = true }
        try await settle(window)
        withAnimation { route.path = [1] }
        try await Task.sleep(for: .milliseconds(600))
        let stack = try XCTUnwrap(navigationController(in: window.rootViewController))
        XCTAssertNil(findBackButton(in: stack.navigationBar))
        XCTAssertFalse(try XCTUnwrap(stack.topViewController).navigationItem.hidesBackButton)
    }

    private final class NavigationRoute: ObservableObject {
        @Published var path: [Int] = []
        @Published var isSaving = false
    }

    private struct NavigationFixture: View {
        @ObservedObject var route: NavigationRoute
        var usesLargeTitle = false
        var body: some View {
            NavigationStack(path: $route.path) {
                AppList { Text("Home") }
                    .navigationTitle("Home")
                    .navigationDestination(for: Int.self) { value in
                        AppList { ForEach(0..<30) { Text("Row \($0)") } }
                            .navigationTitle(value == 1 ? "Budget" : "Settings")
                            .navigationBarTitleDisplayMode(usesLargeTitle ? .large : .inline)
                            .legacyLeadingNavigationTitle(value == 1 ? "Budget" : "Settings")
                            .appBackNavigationDisabled(route.isSaving)
                            .legacyNavigationDestination()
                            .toolbar {
                                if usesLargeTitle {
                                    ToolbarItem(placement: .topBarTrailing) {
                                        Button("September") {}.legacyToolbarControl()
                                    }
                                }
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button {} label: { Image(systemName: "gearshape") }
                                        .legacyToolbarControl(horizontalPadding: 0)
                                }
                            }
                    }
            }
        }
    }

    private func screenshot(_ window: UIWindow) -> UIImage {
        UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
    }

    func testSettingsScrollEdgesStaySoftAfterScrolling() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let window = try makeWindow(NavigationStack {
                SettingsView().navigationBarTitleDisplayMode(.inline)
            }.preferredColorScheme(scheme))
            defer { window.isHidden = true }
            try await settle(window)
            let list = try XCTUnwrap(findCollection(in: window))
            if #unavailable(iOS 26.0) {
                let navigation = try XCTUnwrap(navigationController(in: window.rootViewController))
                let appearance = UINavigationBarAppearance()
                appearance.configureWithTransparentBackground()
                navigation.navigationBar.standardAppearance = appearance
                navigation.topViewController?.navigationItem.standardAppearance = appearance
                navigation.topViewController?.navigationItem.scrollEdgeAppearance = appearance
                try await settle(window)
                XCTAssertFalse(LegacyNavigationAppearance.needsUpdate(navigation),
                               "Hiding the native background must retain the navigation coordinator")
            }
            for offset in [CGFloat(180), 500, 0] {
                list.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
                try await Task.sleep(for: .milliseconds(350))
                let fades = scrollFades(in: window)
                assertTopEdge(in: list, fades: fades)
                XCTAssertEqual(fades.filter { $0.edge == .bottom }.count, 1)
                for fade in fades {
                    XCTAssertNotNil(fade.mask)
                    XCTAssertFalse(fade.isUserInteractionEnabled)
                    XCTAssertGreaterThan(fade.bounds.height, 0)
                    let frame = fade.convert(fade.bounds, to: window)
                    if fade.edge == .top {
                        XCTAssertEqual(frame.minY, window.bounds.minY, accuracy: 0.5)
                    } else {
                        XCTAssertEqual(frame.maxY, window.bounds.maxY, accuracy: 0.5)
                    }
                }
                try assertTitleIsClear("Settings", pointSize: 17, in: window)
                if offset == 180 { attach(window, name: "Settings-scrolled-fades-\(scheme)") }
            }
        }
    }

    func testGradientPagesUseOneFadePerEdge() async throws {
        let window = try makeWindow(NavigationStack { FinancesView() })
        defer { window.isHidden = true }
        try await settle(window)
        let fades = scrollFades(in: window)
        assertTopEdge(in: try XCTUnwrap(findCollection(in: window)), fades: fades)
        XCTAssertEqual(fades.filter { $0.edge == .bottom }.count, 1)
    }

    func testLargeNavigationTitlesStayClearOfFades() async throws {
        for scheme in [ColorScheme.light, .dark] {
            for gradient in [false, true] {
                let window = try makeWindow(NavigationStack {
                    AppList(usesScrollEdgeFades: !gradient) {
                        AppSection {
                            ForEach(0..<40) { Text("Row \($0)") }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .financePage(enabled: gradient)
                    .navigationTitle("Title clarity")
                    .navigationBarTitleDisplayMode(.large)
                }.preferredColorScheme(scheme))
                defer { window.isHidden = true }
                try await settle(window)
                let list = try XCTUnwrap(findCollection(in: window))
                let restingOffset = list.contentOffset
                for collapsed in [false, true, false] {
                    list.setContentOffset(collapsed ? CGPoint(x: 0, y: 500) : restingOffset, animated: false)
                    try await Task.sleep(for: .milliseconds(350))
                    try assertTitleIsClear("Title clarity", pointSize: collapsed ? 17 : 34, in: window)
                    assertTopEdge(in: list, fades: scrollFades(in: window))
                    attach(window, name: "Title-\(gradient ? "gradient" : "list")-\(collapsed ? "collapsed" : "expanded")-\(scheme)")
                }
            }
        }
    }

    private func assertTopEdge(in list: UIScrollView, fades: [ScrollEdgeBlurView.BlurView],
                               file: StaticString = #filePath, line: UInt = #line) {
        if #available(iOS 26.0, *) {
            XCTAssertEqual(list.topEdgeEffect.style, .soft, file: file, line: line)
            XCTAssertFalse(list.topEdgeEffect.isHidden, file: file, line: line)
            XCTAssertTrue(list.bottomEdgeEffect.isHidden, file: file, line: line)
            XCTAssertTrue(fades.allSatisfy { $0.edge == .bottom },
                          "A custom top overlay would cover native large titles", file: file, line: line)
        } else {
            XCTAssertEqual(fades.filter { $0.edge == .top }.count, 1, file: file, line: line)
        }
    }

    private func assertTitleIsClear(_ text: String, pointSize: CGFloat, in window: UIWindow,
                                    file: StaticString = #filePath, line: UInt = #line) throws {
        func labels(in view: UIView) -> [UILabel] {
            (view as? UILabel).map { [$0] } ?? view.subviews.flatMap { labels(in: $0) }
        }
        let label = try XCTUnwrap(labels(in: window).first {
            $0.text == text && abs($0.font.pointSize - pointSize) < 0.5
        }, file: file, line: line)
        let foreground = label.textColor.resolvedColor(with: label.traitCollection)
        let reference = UIGraphicsImageRenderer(size: label.bounds.size).image { context in
            let isDark = label.traitCollection.userInterfaceStyle == .dark
            (isDark ? UIColor.black : UIColor.white).setFill()
            context.fill(label.bounds)
            (text as NSString).draw(in: label.bounds, withAttributes: [
                .font: label.font as Any,
                .foregroundColor: foreground
            ])
        }
        let rendered = screenshot(window)
        let frame = label.convert(label.bounds, to: window)
        let crop = frame.applying(CGAffineTransform(scaleX: rendered.scale, y: rendered.scale))
        let actual = try XCTUnwrap(rendered.cgImage?.cropping(to: crop), file: file, line: line)
        let expectedInk = try foregroundPixelCount(in: XCTUnwrap(reference.cgImage), color: foreground)
        let visibleInk = try foregroundPixelCount(in: actual, color: foreground)
        XCTAssertGreaterThan(expectedInk, 100, "The reference title must contain visible glyphs", file: file, line: line)
        XCTAssertGreaterThanOrEqual(Double(visibleInk), Double(expectedInk) * 0.9,
                                   "The page title must retain its unblurred foreground, even under a scroll edge", file: file, line: line)
    }

    private func foregroundPixelCount(in image: CGImage, color: UIColor) throws -> Int {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let targetRed = Int(red * 255)
        let targetGreen = Int(green * 255)
        let targetBlue = Int(blue * 255)
        var count = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            if abs(Int(pixels[index]) - targetRed) < 20,
               abs(Int(pixels[index + 1]) - targetGreen) < 20,
               abs(Int(pixels[index + 2]) - targetBlue) < 20 {
                count += 1
            }
        }
        return count
    }

    func testBottomFadeIncludesFloatingControls() async throws {
        let window = try makeWindow(NavigationStack {
            AppList(usesScrollEdgeFades: false) {
                AppSection {
                    ForEach(0..<40) { Text("Item \($0)") }
                }
            }
            .modifier(ScrollEdgeFadeModifier(background: AppColor.groupedBackground, usesNativeTopEdge: false))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PrimaryIconButton("Add", iconName: "plus", appearance: .glass) {}
                    .frame(width: 62, height: 62)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        })
        defer { window.isHidden = true }
        try await settle(window)
        XCTAssertEqual(scrollFades(in: window).filter { $0.edge == .top }.count, 1,
                       "Title-free pages with detached content retain the dashboard's custom top fade")
        if #available(iOS 26.0, *) {
            let list = try XCTUnwrap(findCollection(in: window))
            XCTAssertTrue(list.topEdgeEffect.isHidden, "The custom fade must not stack with the native effect")
        }
        let bottom = try XCTUnwrap(scrollFades(in: window).first { $0.edge == .bottom })
        // Dashboard reference: the 78-point accessory plus the 34-point home-indicator inset.
        XCTAssertEqual(bottom.bounds.height, (78 + 34 + 40) * 2 / 3, accuracy: 0.5)
        XCTAssertEqual(bottom.convert(bottom.bounds, to: window).maxY, window.bounds.maxY, accuracy: 0.5)
        attach(window, name: "Floating-control-fade")
    }

    private func scrollFades(in view: UIView) -> [ScrollEdgeBlurView.BlurView] {
        if let fade = view as? ScrollEdgeBlurView.BlurView { return [fade] }
        return view.subviews.flatMap { scrollFades(in: $0) }
    }

    private func navigationController(in controller: UIViewController?) -> UINavigationController? {
        if let navigation = controller as? UINavigationController { return navigation }
        return controller?.children.lazy.compactMap { self.navigationController(in: $0) }.first
    }

    private func makeWindow<Content: View>(_ content: Content) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = UIHostingController(rootView: content.environment(\.dynamicTypeSize, .large))
        window.makeKeyAndVisible()
        return window
    }

    private func settle(_ window: UIWindow) async throws {
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(250))
    }

    private func findCollection(in view: UIView) -> UICollectionView? {
        if let list = view as? UICollectionView { return list }
        return view.subviews.lazy.compactMap { self.findCollection(in: $0) }.first
    }

    private func attach(_ window: UIWindow, name: String) {
        let attachment = XCTAttachment(image: screenshot(window))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
