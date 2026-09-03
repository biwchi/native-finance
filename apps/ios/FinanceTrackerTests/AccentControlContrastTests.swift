import SwiftUI
import UIKit
import XCTest
@testable import FinanceTracker

@MainActor
final class AccentControlContrastTests: XCTestCase {
    func testAccentAssetsContrastInBothAppearances() throws {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let fill = try XCTUnwrap(UIColor(named: "AccentColor")).resolvedColor(with: traits)
            let foreground = try XCTUnwrap(UIColor(named: "OnAccentColor")).resolvedColor(with: traits)

            XCTAssertGreaterThanOrEqual(
                contrast(luminance(fill), luminance(foreground)), 4.5,
                "Accent text must contrast with its fill in \(style)."
            )
            for surface in [UIColor.systemBackground, .secondarySystemGroupedBackground] {
                XCTAssertGreaterThanOrEqual(
                    contrast(luminance(fill), luminance(surface.resolvedColor(with: traits))), 4.5,
                    "Accent links must remain readable on native surfaces in \(style)."
                )
            }
        }
    }

    func testSelectedLabelRemainsVisibleInBothAppearances() throws {
        for scheme in [ColorScheme.light, .dark] {
            try assertVisibleContent(
                AccentSelectionButton("MMMM", isSelected: true) {},
                scheme: scheme
            )
        }
    }

    func testPrimaryLabelsRemainVisibleInBothAppearances() throws {
        for scheme in [ColorScheme.light, .dark] {
            for appearance in PrimaryActionButton.Appearance.allCases {
                try assertVisibleContent(
                    PrimaryActionButton("MMMM", appearance: appearance) {},
                    scheme: scheme
                )
            }
        }
    }

    func testPrimaryIconRemainsVisibleInBothAppearances() throws {
        for scheme in [ColorScheme.light, .dark] {
            try assertVisibleContent(
                PrimaryIconButton("Review", iconName: "arrow-up") {},
                scheme: scheme,
                sampleSize: 12
            )
        }
    }

    func testControlStatesRenderInBothAppearances() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for scheme in [ColorScheme.light, .dark] {
            let content = VStack(spacing: 16) {
                HStack {
                    AccentSelectionButton("Unselected", isSelected: false) {}
                    AccentSelectionButton("Selected", isSelected: true) {}
                }
                HStack {
                    AccentSelectionButton("Disabled", isSelected: false) {}.disabled(true)
                    AccentSelectionButton("Selected", isSelected: true) {}.disabled(true)
                }
                ForEach(PrimaryActionButton.Appearance.allCases, id: \.self) { appearance in
                    HStack {
                        PrimaryActionButton("Save", appearance: appearance) {}
                        PrimaryActionButton("Disabled", appearance: appearance) {}.disabled(true)
                    }
                    PrimaryActionButton("Saving…", isLoading: true, appearance: appearance) {}
                        .disabled(true)
                }
                HStack {
                    PrimaryIconButton("Add", iconName: "plus") {}
                    PrimaryIconButton("Disabled", iconName: "plus") {}.disabled(true)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
            .preferredColorScheme(scheme)
            let controller = UIHostingController(rootView: content)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 820)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.frame = window.bounds
            try await Task.sleep(for: .milliseconds(200))
            controller.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Accent-controls-\(scheme)"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
        }
    }

    private func assertVisibleContent<Content: View>(
        _ content: Content,
        scheme: ColorScheme,
        sampleSize: Int = 24,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        // Conflicting parent colors must not leak into the component's label or fill.
        let renderer = ImageRenderer(content: content
            .frame(width: 200, height: 64)
            .foregroundStyle(.white)
            .tint(.pink)
            .background(scheme == .dark ? Color.black : Color.white)
            .environment(\.colorScheme, scheme)
        )
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage, file: file, line: line)
        let width = image.width
        let height = image.height
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        let fill = try XCTUnwrap(UIColor(named: "AccentColor"), file: file, line: line)
            .resolvedColor(with: traits)
        let fillLuminance = luminance(fill)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), file: file, line: line)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var contrastingPixels = 0
        var fillPixels = 0
        // Sample only the center, away from rounded edges and the surrounding surface.
        for y in (height / 2 - sampleSize)..<(height / 2 + sampleSize) {
            for x in (width / 2 - sampleSize)..<(width / 2 + sampleSize) {
                let offset = (y * width + x) * 4
                let value = luminance(
                    red: Double(pixels[offset]) / 255,
                    green: Double(pixels[offset + 1]) / 255,
                    blue: Double(pixels[offset + 2]) / 255
                )
                let ratio = contrast(value, fillLuminance)
                if ratio >= 4.5 { contrastingPixels += 1 }
                if ratio < 1.5 { fillPixels += 1 }
            }
        }

        XCTAssertGreaterThan(contrastingPixels, 10, "Label/icon is unreadable in \(scheme).", file: file, line: line)
        XCTAssertGreaterThan(fillPixels, 10, "Accent fill did not render in \(scheme).", file: file, line: line)
    }

    private func luminance(_ color: UIColor) -> Double {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: nil)
        return luminance(red: Double(red), green: Double(green), blue: Double(blue))
    }

    private func luminance(red: Double, green: Double, blue: Double) -> Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    private func contrast(_ first: Double, _ second: Double) -> Double {
        (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }
}
