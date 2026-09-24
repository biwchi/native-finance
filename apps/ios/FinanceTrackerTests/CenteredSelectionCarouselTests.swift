import SwiftUI
import UIKit
import XCTest
@testable import FinanceTracker

@MainActor
final class CenteredSelectionCarouselTests: XCTestCase {
    func testInlineHelperDoesNotChangeViewportOrSelectionRange() async throws {
        for scheme in [ColorScheme.light, .dark] {
            for usesTapAction in [false, true] {
                let state = Selection()
                let helper = usesTapAction
                    ? CenteredSelectionCarouselItem(id: 0, title: "Back", iconName: "nav-arrow-down",
                        color: .blue, tapAction: { state.helperTaps += 1 })
                    : CenteredSelectionCarouselItem(id: 0, title: "All", iconName: "view-grid",
                        color: .blue, action: { state.helperTaps += 1 })
                let values = (1...3).map {
                    CenteredSelectionCarouselItem(id: $0, title: "Value \($0)", iconName: "cart", color: .orange)
                }
                let window = try makeWindow(Fixture(state: state, items: [helper] + values)
                    .preferredColorScheme(scheme))
                defer { window.isHidden = true }
                try await settle()
                let scroll = try XCTUnwrap(descendants(window).compactMap { $0 as? UIScrollView }.first)

                XCTAssertEqual(scroll.bounds.width, 360, accuracy: 0.5,
                    "Helpers must not reserve a separate column or move the viewport center.")
                let firstOffset = -scroll.adjustedContentInset.left
                let lastOffset = scroll.contentSize.width - scroll.bounds.width + scroll.adjustedContentInset.right
                XCTAssertEqual(lastOffset - firstOffset, 92, accuracy: 0.5,
                    "Only the two steps between three real values belong in the scroll range.")
                XCTAssertEqual(scroll.contentOffset.x, firstOffset, accuracy: 0.5)
                XCTAssertEqual(state.id, 1)
                attach(window, name: "Carousel-\(scheme)-\(usesTapAction ? "back" : "all")")

                let helperPoint = scroll.convert(CGPoint(x: scroll.bounds.midX - 46,
                    y: scroll.bounds.minY + 22), to: window)
                let valuePoint = scroll.convert(CGPoint(x: scroll.bounds.midX,
                    y: scroll.bounds.minY + 22), to: window)
                let helperHit = try XCTUnwrap(window.hitTest(helperPoint, with: nil))
                let valueHit = try XCTUnwrap(window.hitTest(valuePoint, with: nil))
                XCTAssertEqual(String(describing: type(of: helperHit)), String(describing: type(of: valueHit)),
                    "The inline helper must remain inside the same interactive content as the values.")

                state.id = 2
                try await settle()
                XCTAssertEqual(scroll.contentOffset.x, firstOffset + 46, accuracy: 0.5)
                state.id = 1
                try await settle()
                XCTAssertEqual(scroll.contentOffset.x, firstOffset, accuracy: 0.5)
                XCTAssertEqual(state.id, 1)
                XCTAssertEqual(state.helperTaps, 0, "Changing selection must never invoke a helper.")
            }
        }
    }

    func testHelperRemainsAvailableWithoutSelectableValues() async throws {
        let state = Selection()
        state.id = nil
        let helper = CenteredSelectionCarouselItem(id: 0, title: "All", iconName: "view-grid",
            color: .blue, action: { state.helperTaps += 1 })
        let window = try makeWindow(Fixture(state: state, items: [helper]))
        defer { window.isHidden = true }
        try await settle()
        let scroll = try XCTUnwrap(descendants(window).compactMap { $0 as? UIScrollView }.first)
        XCTAssertEqual(scroll.bounds.width, 360, accuracy: 0.5)
        XCTAssertNil(state.id)
        XCTAssertEqual(state.helperTaps, 0)
        attach(window, name: "Carousel-helper-only")
    }

    private final class Selection: ObservableObject {
        @Published var id: Int? = 1
        var helperTaps = 0
    }

    private struct Fixture: View {
        @ObservedObject var state: Selection
        let items: [CenteredSelectionCarouselItem<Int>]

        var body: some View {
            CenteredSelectionCarousel(items: items, selection: $state.id)
                .frame(width: 360)
                .padding(.vertical, 8)
                .background(AppColor.elevatedSurface)
        }
    }

    private func makeWindow<Content: View>(_ content: Content) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: content)
        window.makeKeyAndVisible()
        return window
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(300))
    }

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func attach(_ window: UIWindow, name: String) {
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
