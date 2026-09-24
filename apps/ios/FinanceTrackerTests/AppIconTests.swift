import SwiftUI
import UIKit
import XCTest
@testable import FinanceTracker

@MainActor
final class AppIconTests: XCTestCase {
    func testPreviouslySavedIconsKeepTheirMeaning() {
        let examples = [
            "creditcard.fill": "credit-card",
            "banknote.fill": "cash",
            "cup.and.saucer.fill": "coffee-cup",
            "fork.knife": "cutlery",
            "house.fill": "home-simple",
            "chart.line.uptrend.xyaxis": "graph-up",
            "ellipsis.circle.fill": "more-horiz-circle",
            "briefcase.fill": "suitcase",
            "arrow.3.trianglepath": "refresh",
            "stethoscope": "healthcare",
        ]
        for (saved, expected) in examples {
            XCTAssertEqual(AppIcons.canonicalName(saved), expected)
            XCTAssertEqual(AppIcons.canonicalName(expected), expected)
        }
        XCTAssertEqual(AppIconCatalog.group(containing: "banknote.fill")?.title, "Money & accounts")
        XCTAssertEqual(AppIconCatalog.group(containing: "cup.and.saucer.fill")?.title, "Food & drink")
    }

    func testSavedIconoirIdentifiersResolveToHugeiconsArtwork() {
        let examples = [
            "credit-card": "creditCard",
            "cash": "cash01",
            "coffee-cup": "coffee02",
            "cutlery": "restaurant01",
            "home-simple": "home03",
            "graph-up": "chartIncrease",
            "label": "tag01",
            "arrow-down-left-circle": "circleArrowDownLeft",
            "arrow-up-right-circle": "circleArrowUpRight",
            "equal": "equalSign",
            // Picker cleanup must not change the artwork on saved entities.
            "more-horiz-circle": "moreHorizontalCircle01",
            "more-vertical": "moreVertical",
            "view": "view",
            "suitcase": "briefcase01",
            "luggage": "luggage01",
            "refresh": "refresh",
            "recycling": "recycle01",
            "skateboard": "rollerSkate",
            "doctor": "stethoscope",
        ]
        for (identifier, expected) in examples {
            XCTAssertEqual(AppIcons.canonicalName(identifier), identifier)
            XCTAssertEqual(AppIcons.resolve(identifier).swiftIdentifier, expected)
        }
        for (saved, identifier) in AppIcons.legacyNames {
            XCTAssertNotNil(AppIcons.artwork[identifier], "Unmapped saved icon: \(saved)")
            XCTAssertEqual(AppIcons.resolve(saved), AppIcons.resolve(identifier))
        }
        XCTAssertEqual(AppIcons.canonicalName("nosign"), "prohibition")
    }

    func testAllPickerChoicesAndLegacyIconsHaveBundledArtwork() throws {
        let choices = AppIconCatalog.choices
            + AppIconCatalog.groups.map(\.symbol)
            + AppTheme.allCases.map(\.iconName)
        for name in Set(choices) {
            XCTAssertTrue(
                AppIcons.artwork[name] != nil || AppIcons.assetNames.contains(name),
                "Missing bundled artwork: \(name)"
            )
            XCTAssertEqual(AppIcons.canonicalName(name), name, "Invalid icon choice: \(name)")
        }
        let allNames = choices
            + Array(AppIcons.legacyNames.keys)
            + Array(AppIcons.artwork.keys)
            + Array(AppIcons.assetNames)
        for name in Set(allNames) {
            let image = try XCTUnwrap(AppIcons.uiImage(named: name), "Missing artwork: \(name)")
            XCTAssertEqual(image.renderingMode, .alwaysTemplate)
            XCTAssertGreaterThan(image.size.width, 0)
            XCTAssertGreaterThan(image.size.height, 0)
        }
    }

    func testBrandAndCryptoGroupsExposeBundledAssets() {
        let expectedGroups = [
            "Brands": [
                "brand-apple", "brand-google", "brand-netflix", "brand-spotify",
                "brand-youtube", "brand-apple-music", "brand-apple-tv", "brand-hbo",
                "brand-steam", "brand-playstation", "brand-twitch", "brand-patreon",
                "brand-tinder", "brand-ebay", "brand-airbnb", "brand-uber",
                "brand-paypal", "brand-visa", "brand-mastercard", "brand-wise",
                "brand-revolut", "brand-alipay", "brand-robinhood",
            ],
            "Crypto": [
                "crypto-bitcoin", "crypto-ethereum", "crypto-solana", "crypto-tether",
                "crypto-usdc", "crypto-bnb", "brand-binance", "brand-bybit",
            ],
        ]

        for (title, expectedNames) in expectedGroups {
            let group = AppIconCatalog.groups.first { $0.title == title }
            XCTAssertEqual(group?.icons.map(\.symbol), expectedNames)
            XCTAssertTrue(expectedNames.allSatisfy(AppIcons.assetNames.contains))
        }
        XCTAssertEqual(AppIconCatalog.groups.suffix(2).map(\.title), ["Brands", "Crypto"])
    }

    func testPickerGroupsDoNotContainDuplicateIdentities() {
        for group in AppIconCatalog.groups {
            XCTAssertEqual(Set(group.icons.map(\.id)).count, group.icons.count, group.title)
        }
    }

    func testSuggestionsMatchEnglishAndRussianTerms() {
        XCTAssertEqual(AppIconCatalog.suggestions(matching: "gro").first?.symbol, "cart")
        XCTAssertEqual(AppIconCatalog.suggestions(matching: "Продукты").first?.symbol, "cart")
        XCTAssertEqual(AppIconCatalog.suggestions(matching: "  пРоДуКтЫ  ").first?.symbol, "cart")
        XCTAssertEqual(AppIconCatalog.suggestions(matching: "кошелек").first?.symbol, "wallet")
        XCTAssertEqual(AppIconCatalog.suggestions(matching: "вода").map(\.symbol), ["droplet"])
        XCTAssertEqual(AppIconCatalog.suggestions(matching: "нетфликс").first?.symbol, "brand-netflix")
        XCTAssertEqual(AppIconCatalog.suggestions(matching: "биткоин").first?.symbol, "crypto-bitcoin")
        XCTAssertEqual(AppIconCatalog.suggestions(matching: "байбит").first?.symbol, "brand-bybit")
        XCTAssertTrue(AppIconCatalog.suggestions(matching: "   ").isEmpty)
    }

    func testUnrecognizedSavedIconStillRenders() throws {
        XCTAssertEqual(AppIcons.canonicalName("unknown-future-icon"), "label")
        XCTAssertNotNil(AppIcons.uiImage(named: "unknown-future-icon"))
    }

    func testIconsScaleWithDynamicType() throws {
        let standard = ImageRenderer(content: AppIcon("credit-card").dynamicTypeSize(.large))
        let accessible = ImageRenderer(content: AppIcon("credit-card").dynamicTypeSize(.accessibility1))
        let standardSize = try XCTUnwrap(standard.uiImage).size
        let accessibleSize = try XCTUnwrap(accessible.uiImage).size
        XCTAssertGreaterThan(accessibleSize.width, standardSize.width)
        XCTAssertGreaterThan(accessibleSize.height, standardSize.height)
    }

    func testIconControlsRenderInBothAppearances() throws {
        for scheme in [ColorScheme.light, .dark] {
            let content = VStack(alignment: .leading, spacing: 20) {
                Text("Finance Tracker icons").font(.title2.bold())
                HStack(spacing: 24) {
                    ForEach(["home-simple", "settings", "plus", "calendar", "percentage-circle", "coins-swap"], id: \.self) {
                        AppIcon($0, size: 24)
                    }
                }
                HStack {
                    AccentSelectionButton("Unselected", isSelected: false) {}
                    AccentSelectionButton("Selected", isSelected: true) {}
                    AccentSelectionButton("Disabled", isSelected: true) {}.disabled(true)
                }
                HStack {
                    PrimaryIconButton("Send", iconName: "arrow-up") {}
                    PrimaryIconButton("Disabled", iconName: "arrow-up") {}.disabled(true)
                    PrimaryActionButton("Saving…", isLoading: true) {}
                }
                IconPicker(selection: .constant("brand-netflix"))
                IconPicker(selection: .constant("crypto-bitcoin"))
                    .disabled(true)
                HStack {
                    ForEach([false, true], id: \.self) { selected in
                        AccentSelectionButton(
                            "Bank", isSelected: selected, iconName: "bank",
                            appearance: .iconBadge, selectionTint: .blue
                        ) {}
                        AccentSelectionButton(
                            "Disabled bank", isSelected: selected, iconName: "bank",
                            appearance: .iconBadge, selectionTint: .blue
                        ) {}.disabled(true)
                        AccentSelectionButton(
                            "Disabled icon", isSelected: selected, iconName: "bank",
                            appearance: .icon
                        ) {}.disabled(true)
                    }
                }
                Label("Warning message", icon: "warning-triangle").foregroundStyle(.secondary)
            }
                .padding(20)
                .frame(width: 420)
                .foregroundStyle(Color.primary)
                .background(Color(uiColor: .systemBackground))
                .environment(\.colorScheme, scheme)

            // Render through UIKit so native spinners and scroll views are captured too.
            let host = UIHostingController(rootView: content)
            host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
            let size = host.sizeThatFits(in: CGSize(width: 420, height: 2_000))
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = host
            window.isHidden = false
            defer { window.isHidden = true }
            host.view.frame = window.bounds
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { _ in
                XCTAssertTrue(host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Icon controls - \(scheme)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
