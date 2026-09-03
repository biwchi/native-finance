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
        ]
        for (saved, expected) in examples {
            XCTAssertEqual(AppIcons.canonicalName(saved), expected)
            XCTAssertEqual(AppIcons.canonicalName(expected), expected)
        }
        XCTAssertEqual(CategoryIconCatalog.group(containing: "banknote.fill")?.title, "Finance")
        XCTAssertEqual(CategoryIconCatalog.group(containing: "cup.and.saucer.fill")?.title, "Food")
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
        let choices = CategoryIconCatalog.choices
            + CategoryIconCatalog.groups.map(\.symbol)
            + AccountIcon.choices
            + AccountType.allCases.map(\.iconName)
            + AppTheme.allCases.map(\.iconName)
        for name in Set(choices) {
            XCTAssertNotNil(AppIcons.artwork[name], "Missing Hugeicons mapping: \(name)")
            XCTAssertEqual(AppIcons.canonicalName(name), name, "Invalid icon choice: \(name)")
        }
        for name in Set(choices + Array(AppIcons.legacyNames.keys) + Array(AppIcons.artwork.keys)) {
            let image = try XCTUnwrap(AppIcons.uiImage(named: name), "Missing artwork: \(name)")
            XCTAssertEqual(image.renderingMode, .alwaysTemplate)
            XCTAssertGreaterThan(image.size.width, 0)
            XCTAssertGreaterThan(image.size.height, 0)
        }
    }

    func testPickerGroupsDoNotContainDuplicateIdentities() {
        for group in CategoryIconCatalog.groups {
            XCTAssertEqual(Set(group.icons.map(\.id)).count, group.icons.count, group.title)
        }
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
                Text("Hugeicons Stroke Rounded · Finance Tracker").font(.title2.bold())
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
                CategoryIconPicker(selection: .constant("cash"), color: .teal)
                CategoryIconPicker(selection: .constant("coffee-cup"), color: .orange)
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
            attachment.name = "Hugeicons controls — \(scheme)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
