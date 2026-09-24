import XCTest
import UIKit
import SwiftUI
@testable import FinanceTracker

final class FinanceToolbarBlurTests: XCTestCase {
    @MainActor
    func testBottomFadeStaysBelowKeyboardWhileFormAvoidsIt() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let originalKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let textField = UITextField()
        textField.placeholder = "Name"
        // A fixed input view also exercises keyboard avoidance when the simulator
        // has a hardware keyboard connected.
        textField.inputView = UIInputView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 300), inputViewStyle: .keyboard
        )
        let controller = UIHostingController(rootView: NavigationStack {
            AppForm {
                Section("Account details") {
                    KeyboardTextField(textField: textField)
                }
                Section("Icon") {
                    ForEach(0..<12) { index in
                        Text("Icon \(index)")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Add account")
                    .frame(height: 56)
                    .padding(.vertical, 12)
            }
        })
        window.rootViewController = controller
        window.makeKeyAndVisible()
        let keyboardGuide = controller.view.keyboardLayoutGuide
        defer {
            textField.resignFirstResponder()
            window.isHidden = true
            originalKeyWindow?.makeKey()
        }

        for appearance in [UIUserInterfaceStyle.light, .dark] {
            window.overrideUserInterfaceStyle = appearance
            try await Task.sleep(for: .milliseconds(300))
            let fade = try XCTUnwrap(bottomFade(in: controller.view))
            let restingFrame = fade.convert(fade.bounds, to: window)
            XCTAssertGreaterThan(restingFrame.height, 0)
            XCTAssertEqual(restingFrame.maxY, window.bounds.maxY, accuracy: 1)

            XCTAssertTrue(textField.becomeFirstResponder())
            try await Task.sleep(for: .milliseconds(600))
            window.layoutIfNeeded()
            let keyboardTop = controller.view.convert(keyboardGuide.layoutFrame, to: window).minY
            XCTAssertLessThan(keyboardTop, window.bounds.maxY - 100, "The software keyboard must be open")
            let editingFrame = fade.convert(fade.bounds, to: window)
            XCTAssertGreaterThanOrEqual(editingFrame.minY, keyboardTop,
                "The decorative fade must stay behind the keyboard, away from visible form content")
            let fieldFrame = textField.convert(textField.bounds, to: window)
            XCTAssertLessThanOrEqual(fieldFrame.maxY, keyboardTop, "The form must still avoid the keyboard")

            textField.resignFirstResponder()
            try await Task.sleep(for: .milliseconds(600))
            window.layoutIfNeeded()
            let restoredFrame = fade.convert(fade.bounds, to: window)
            XCTAssertEqual(restoredFrame.minY, restingFrame.minY, accuracy: 1)
            XCTAssertEqual(restoredFrame.maxY, restingFrame.maxY, accuracy: 1)
        }
    }

    @MainActor
    private func bottomFade(in view: UIView) -> ScrollEdgeBlurView.BlurView? {
        if let fade = view as? ScrollEdgeBlurView.BlurView, fade.edge == .bottom { return fade }
        return view.subviews.lazy.compactMap { self.bottomFade(in: $0) }.first
    }

    @MainActor
    func testToolbarBlurRetainsDetailAfterLayoutAndAppearanceChanges() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        // Host through SwiftUI: UIKit-only fixtures do not reproduce the mask reset.
        func content(width: CGFloat) -> some View {
            StripeBackdrop()
                .frame(width: width, height: 180)
                .overlay {
                    ScrollEdgeBlurView(transitionHeight: 56)
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
                    .overlay { ScrollEdgeBlurView(transitionHeight: 56) }
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

private struct KeyboardTextField: UIViewRepresentable {
    let textField: UITextField
    func makeUIView(context: Context) -> UITextField { textField }
    func updateUIView(_ view: UITextField, context: Context) {}
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
