import XCTest
import UIKit
import SwiftUI
@testable import FinanceTracker

final class FinanceToolbarBlurTests: XCTestCase {
    @MainActor
    func testToolbarBlurRetainsDetailAfterLayoutAndAppearanceChanges() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Custom toolbar blur requires iOS 26") }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        // Host through SwiftUI: UIKit-only fixtures do not reproduce the mask reset.
        func content(width: CGFloat) -> some View {
            StripeBackdrop()
                .frame(width: width, height: 180)
                .overlay {
                    FinanceToolbarBlurView(transitionHeight: 56)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .ignoresSafeArea()
        }
        let controller = UIHostingController(rootView: content(width: 300))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        for appearance in [UIUserInterfaceStyle.light, .dark, .light] {
            window.overrideUserInterfaceStyle = appearance
            for width in [CGFloat(300), 280, 300] {
                controller.rootView = content(width: width)
                controller.view.setNeedsLayout()
                window.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(150))
                let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                    XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
                }
                let contrast = try stripeContrast(in: image)
                XCTAssertGreaterThan(contrast, 10, "A layout or theme change must not reset to full blur and erase the stripes")
                XCTAssertLessThan(contrast, 110, "The stripes must be softened, rather than remaining sharp")
            }
        }
    }

    @MainActor
    func testToolbarBlurRetainsDetailWhenReturningToTabs() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Custom toolbar blur requires iOS 26") }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for appearance in [UIUserInterfaceStyle.light, .dark] {
            let window = UIWindow(windowScene: scene)
            window.overrideUserInterfaceStyle = appearance
            let tabs = UITabBarController()
            let pages = (0..<3).map { _ in
                UIHostingController(rootView: StripeBackdrop()
                    .frame(width: 300, height: 180)
                    .overlay { FinanceToolbarBlurView(transitionHeight: 56) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .ignoresSafeArea())
            }
            tabs.tabs = pages.enumerated().map { index, page in
                UITab(title: "Page \(index)", image: nil, identifier: "\(index)") { _ in page }
            }
            window.rootViewController = tabs
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            var initialContrasts: [Int: Double] = [:]
            for index in [0, 1, 0, 2, 0, 1, 2, 0] {
                tabs.selectedTab = tabs.tabs[index]
                try await Task.sleep(for: .milliseconds(350))
                let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                    XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
                }
                let contrast = try stripeContrast(in: image)
                XCTAssertGreaterThan(contrast, 10, "Returning to a tab must retain blurred detail")
                XCTAssertLessThan(contrast, 110, "Returning to a tab must keep the blur active")
                if let initial = initialContrasts[index] {
                    XCTAssertEqual(contrast, initial, accuracy: 2, "Returning must preserve the tab's original blur intensity")
                } else {
                    initialContrasts[index] = contrast
                }
            }
        }
    }

    private func stripeContrast(in image: UIImage) throws -> Double {
        let cgImage = try XCTUnwrap(image.cgImage)
        let crop = CGRect(x: 30 * image.scale, y: 30 * image.scale, width: 200 * image.scale, height: 20 * image.scale)
        let sample = try XCTUnwrap(cgImage.cropping(to: crop))
        var pixels = [UInt8](repeating: 0, count: sample.width * sample.height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: sample.width, height: sample.height,
                bitsPerComponent: 8, bytesPerRow: sample.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(sample, in: CGRect(x: 0, y: 0, width: sample.width, height: sample.height))
        }
        let values = stride(from: 0, to: pixels.count, by: 4).map { Double(pixels[$0]) }
        let mean = values.reduce(0, +) / Double(values.count)
        return sqrt(values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count))
    }
}

private struct StripeBackdrop: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        for index in 0..<75 {
            let stripe = UIView(frame: CGRect(x: index * 4, y: 0, width: 4, height: 180))
            stripe.backgroundColor = index.isMultiple(of: 2) ? .white : .black
            view.addSubview(stripe)
        }
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {}
}
