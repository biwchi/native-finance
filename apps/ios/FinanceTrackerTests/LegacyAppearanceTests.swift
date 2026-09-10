import SwiftUI
import UIKit
import XCTest
import Vision
@testable import FinanceTracker

@MainActor
final class LegacyAppearanceTests: XCTestCase {
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
            // Locate the three-row preferences section even if a sync warning is present above it.
            let preferences = try XCTUnwrap((0..<list.numberOfSections).first {
                list.numberOfItems(inSection: $0) == 3
            })
            func row(_ section: Int, _ item: Int = 0) throws -> CGRect {
                try XCTUnwrap(list.layoutAttributesForItem(at: IndexPath(item: item, section: section))).frame
            }
            let exchangeRates = try row(preferences - 1)
            let categories = try row(preferences)
            let currency = try row(preferences, 1)
            let theme = try row(preferences, 2)
            let weekday = try row(preferences + 1)
            let roundTotals = try row(preferences + 1, 1)
            let quickEntry = try row(preferences + 2)
            let reminders = try row(preferences + 3)
            for frame in [exchangeRates, categories, theme, weekday, roundTotals, quickEntry, reminders] {
                XCTAssertEqual(frame.height, 52, accuracy: 0.5)
                XCTAssertEqual(frame.minX, 16, accuracy: 0.5)
                XCTAssertEqual(frame.width, window.bounds.width - 32, accuracy: 0.5)
            }
            // Native iOS 26 measurements at standard text size, including multiline content.
            XCTAssertEqual(currency.height, 74.667, accuracy: 0.5)
            XCTAssertEqual(categories.minY - exchangeRates.maxY, 35, accuracy: 0.5)
            XCTAssertEqual(weekday.minY - theme.maxY, 58, accuracy: 0.5)
            XCTAssertEqual(quickEntry.minY - roundTotals.maxY, 86, accuracy: 0.5)
            XCTAssertEqual(reminders.minY - quickEntry.maxY, 86, accuracy: 0.5)
            attach(window, name: "Settings-spacing-\(scheme)")
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
                               "Hiding the native background must retain the circular back indicator")
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
