import SwiftUI
import UIKit
import XCTest
import Vision
@testable import FinanceTracker

@MainActor
final class CircleSwipeActionsTests: XCTestCase {
    func testCircleSwipeDirectionAndCommitDistance() {
        XCTAssertFalse(CircleSwipeMetrics.accepts(velocity: CGPoint(x: -20, y: 100), isOpen: false))
        XCTAssertFalse(CircleSwipeMetrics.accepts(velocity: CGPoint(x: 100, y: 0), isOpen: false))
        XCTAssertTrue(CircleSwipeMetrics.accepts(velocity: CGPoint(x: -100, y: 10), isOpen: false))
        XCTAssertTrue(CircleSwipeMetrics.accepts(velocity: CGPoint(x: 100, y: 10), isOpen: true))
        // A fast, short flick can reveal the buttons, but must never delete.
        XCTAssertEqual(CircleSwipeMetrics.destination(reveal: 40, velocity: -1500, width: 340,
                                                      actionCount: 2, canCommit: true), .open)
        XCTAssertEqual(CircleSwipeMetrics.destination(reveal: 20, velocity: 0, width: 340,
                                                      actionCount: 2, canCommit: true), .closed)
        XCTAssertEqual(CircleSwipeMetrics.destination(reveal: 240, velocity: 0, width: 340,
                                                      actionCount: 2, canCommit: true), .commit)
        XCTAssertEqual(CircleSwipeMetrics.destination(reveal: 240, velocity: 0, width: 340,
                                                      actionCount: 2, canCommit: false), .open)
    }

    func testCircleSwipeRevealKeepsCornersAndCommitsRightmostAction() async throws {
        for scheme in [ColorScheme.light, .dark] {
            var performed: [String] = []
            let window = try makeWindow(AppList {
                AppSection("Transactions") {
                    ForEach(0..<2) { row in
                        Button("Transaction \(row)") { performed.append("row") }
                            .buttonStyle(.plain)
                            .circleSwipeActions {
                                CircleSwipeAction(title: "Delete", icon: "trash") { performed.append("delete") }
                                CircleSwipeAction(title: "Edit", icon: "edit-pencil", tint: .gray) { performed.append("edit") }
                            }
                    }
                }
            }.listStyle(.insetGrouped).preferredColorScheme(scheme))
            defer { window.isHidden = true }
            try await settle(window)
            let list = try XCTUnwrap(findCollection(in: window))
            let probes = swipeObservers(in: window).sorted {
                $0.convert($0.bounds, to: window).minY < $1.convert($1.bounds, to: window).minY
            }
            XCTAssertEqual(probes.count, 2)
            let probe = try XCTUnwrap(probes.first)
            let other = try XCTUnwrap(probes.last)
            XCTAssertNotNil(probe.pan.view)
            let cells = list.visibleCells
            let radii = cells.map { $0.layer.cornerRadius }
            let masks = cells.map { $0.layer.maskedCorners }
            func assertCorners() {
                XCTAssertEqual(cells.map { $0.layer.cornerRadius }, radii)
                XCTAssertEqual(cells.map { $0.layer.maskedCorners }, masks)
                if #unavailable(iOS 26.0) {
                    XCTAssertTrue(radii.contains(26))
                }
            }
            let width = probe.bounds.width
            probe.configuration.onBegin()
            probe.configuration.onChange(-35, width)
            try await settle(window)
            assertCorners()
            XCTAssertEqual(probe.configuration.revealedWidth, 35, accuracy: 0.5)
            attach(window, name: "Circle-actions-partial-\(scheme)")
            probe.configuration.onChange(-100, width)
            probe.configuration.onEnd(0, width, false)
            try await settle(window)
            XCTAssertTrue(performed.isEmpty)
            XCTAssertEqual(probe.configuration.revealedWidth, 128, accuracy: 0.5)
            assertCorners()
            attach(window, name: "Circle-actions-open-\(scheme)")
            // Opening another row dismisses the first one.
            other.configuration.onBegin()
            other.configuration.onChange(-80, width)
            other.configuration.onEnd(0, width, false)
            try await settle(window)
            XCTAssertEqual(probe.configuration.revealedWidth, 0)
            // Cancellation after crossing the threshold must never perform an action.
            other.configuration.onBegin()
            other.configuration.onChange(-width, width)
            other.configuration.onEnd(0, width, true)
            try await settle(window)
            XCTAssertTrue(performed.isEmpty)
            XCTAssertEqual(other.configuration.revealedWidth, 0)
            probe.configuration.onBegin()
            probe.configuration.onChange(-width * 0.8, width)
            try await settle(window)
            assertCorners()
            attach(window, name: "Circle-actions-armed-\(scheme)")
            probe.configuration.onEnd(0, width, false)
            XCTAssertTrue(performed.isEmpty, "Finish the full-swipe animation before performing the action")
            try await Task.sleep(for: .milliseconds(950))
            try await settle(window)
            XCTAssertEqual(performed, ["delete"])
            XCTAssertEqual(probe.configuration.revealedWidth, 0)
            assertCorners()
        }
    }

    func testDisabledCircleSwipeCannotPerformActions() async throws {
        for scheme in [ColorScheme.light, .dark] {
            var performed = false
            let window = try makeWindow(AppList {
                AppSection {
                    Text("Disabled row").circleSwipeActions(isEnabled: false) {
                        CircleSwipeAction(title: "Delete", icon: "trash") { performed = true }
                    }
                    Text("Disabled action").circleSwipeActions {
                        CircleSwipeAction(title: "Delete", icon: "trash", isEnabled: false) { performed = true }
                    }
                }
            }.listStyle(.insetGrouped).preferredColorScheme(scheme))
            defer { window.isHidden = true }
            try await settle(window)
            let probes = swipeObservers(in: window)
            XCTAssertEqual(probes.count, 2)
            for probe in probes {
                probe.configuration.onBegin()
                probe.configuration.onChange(-probe.bounds.width, probe.bounds.width)
                probe.configuration.onEnd(0, probe.bounds.width, false)
            }
            try await settle(window)
            XCTAssertFalse(performed)
            let disabledRow = try XCTUnwrap(probes.first { !$0.pan.isEnabled })
            XCTAssertEqual(disabledRow.configuration.revealedWidth, 0)
            attach(window, name: "Circle-actions-disabled-\(scheme)")
        }
    }

    func testSingleCircleActionRendersOutsideTransactionAndGrows() async throws {
        let account = Account(id: UUID(), name: "Kaspi", type: .checking, currency: "KZT",
                              icon: "credit-card", iconColor: .red, createdAt: "", updatedAt: "")
        let now = Date.now
        let transaction = FinanceTransaction(id: UUID(), accountId: account.id, kind: .expense,
                                             amount: "20000", currency: "KZT", category: nil,
                                             note: nil, occurredAt: now, createdAt: now, updatedAt: now)
        for scheme in [ColorScheme.light, .dark] {
            let window = try makeWindow(AppList {
                AppSection("9 September 2026") {
                    Button {} label: {
                        TransactionRow(transaction: transaction, account: account, titleOverride: "Gym")
                    }
                    .buttonStyle(.plain)
                    .circleSwipeActions {
                        CircleSwipeAction(title: "Delete", icon: "trash") {}
                    }
                }
            }.listStyle(.insetGrouped).preferredColorScheme(scheme))
            defer { window.isHidden = true }
            try await settle(window)
            let probe = try XCTUnwrap(swipeObservers(in: window).first)
            let width = probe.bounds.width
            let frame = probe.convert(probe.bounds, to: window)
            probe.configuration.onBegin()
            probe.configuration.onChange(-64, width)
            probe.configuration.onEnd(0, width, false)
            try await settle(window)
            let openImage = screenshot(window)
            let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
            let page = UIColor.systemGroupedBackground.resolvedColor(with: traits)
            // The gap between the moving card and the action must expose the page,
            // not the card's elevated surface. This failed in the original implementation.
            try assertPixel(in: openImage, at: CGPoint(x: frame.maxX - 60, y: frame.midY), matches: page)
            // The card's exposed top-right corner remains rounded with the app radius.
            try assertPixel(in: openImage, at: CGPoint(x: frame.maxX - 66, y: frame.minY + 3), matches: page)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: XCTUnwrap(openImage.cgImage), options: [:]).perform([request])
            let words = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            XCTAssertTrue(words.contains("Delete"), "The action needs a visible label: \(words)")
            attach(window, name: "Transaction-external-action-\(scheme)")
            // A further 70-point drag must visibly widen the action into the new space.
            let growthPoint = CGPoint(x: frame.maxX - 85, y: frame.midY - 9)
            probe.configuration.onBegin()
            probe.configuration.onChange(-70, width)
            try await settle(window)
            let expanded = try pixel(in: screenshot(window), at: growthPoint)
            XCTAssertGreaterThan(expanded[0] - expanded[1], 0.05, "The red action should occupy the additional swipe space")
            attach(window, name: "Transaction-growing-action-\(scheme)")
            probe.configuration.onEnd(0, width, true)
        }
    }

    func testCloseHasIntermediateFramesAndKeepsBackgroundInStep() async throws {
        let window = try makeWindow(AppList {
            AppSection {
                Text("Animated row").circleSwipeActions {
                    CircleSwipeAction(title: "Delete", icon: "trash") {}
                }
            }
        }.listStyle(.insetGrouped).preferredColorScheme(.dark))
        defer { window.isHidden = true }
        try await settle(window)
        let probe = try XCTUnwrap(swipeObservers(in: window).first)
        probe.configuration.onBegin()
        probe.configuration.onChange(-64, probe.bounds.width)
        try await settle(window)
        probe.configuration.onClose()
        try await Task.sleep(for: .milliseconds(70))
        let intermediate = probe.configuration.revealedWidth
        XCTAssertGreaterThan(intermediate, 1)
        XCTAssertLessThan(intermediate, 63)
        attach(window, name: "Swipe-close-intermediate-frame")
        // Both the content and the List-hosted background must move, not just the icons.
        let frame = probe.convert(probe.bounds, to: window)
        let surface = UIColor.secondarySystemGroupedBackground.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .dark))
        try assertPixel(in: screenshot(window), at: CGPoint(x: frame.maxX - 62, y: frame.midY), matches: surface)
        try await settle(window)
        XCTAssertEqual(probe.configuration.revealedWidth, 0)
    }

    func testSettlingCanBeInterruptedWithoutJumpingOrRunningOldCompletion() async throws {
        let motion = CircleSwipeMotion()
        motion.drag(to: 160)
        var completed = false
        motion.settle(to: 0, reduceMotion: false) { completed = true }
        try await Task.sleep(for: .milliseconds(80))
        let displayed = motion.reveal
        XCTAssertGreaterThan(displayed, 0)
        XCTAssertLessThan(displayed, 160)
        motion.beginDrag()
        XCTAssertEqual(motion.reveal, displayed)
        motion.drag(to: displayed + 12)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(motion.reveal, displayed + 12)
        XCTAssertFalse(completed)
        XCTAssertFalse(motion.isAnimating)
    }

    func testReleaseVelocityAndReduceMotion() async throws {
        let slow = CircleSwipeMotion()
        let fast = CircleSwipeMotion()
        slow.drag(to: 30)
        fast.drag(to: 30)
        slow.settle(to: 128, reduceMotion: false)
        fast.settle(to: 128, velocity: 600, reduceMotion: false)
        try await Task.sleep(for: .milliseconds(70))
        XCTAssertGreaterThan(fast.reveal, slow.reveal, "A fast swipe should carry momentum into the settling motion")
        slow.reset()
        fast.reset()
        var completions = 0
        fast.settle(to: 128, reduceMotion: true) { completions += 1 }
        XCTAssertEqual(fast.reveal, 128)
        XCTAssertFalse(fast.isAnimating)
        XCTAssertEqual(completions, 1)
    }

    @MainActor
    private final class DeletionFixture: ObservableObject {
        @Published var rows = [0, 1, 2]
        @Published var isBusy = false
        var succeeds = true
        var calls = 0

        func delete(_ id: Int) async -> Bool {
            calls += 1
            isBusy = true
            defer { isBusy = false }
            // Match the asynchronous screen action and its disabled-state updates.
            try? await Task.sleep(for: .milliseconds(200))
            guard succeeds else { return false }
            rows.removeAll { $0 == id }
            return true
        }
    }

    private struct DeletionList: View {
        @ObservedObject var model: DeletionFixture
        var separateSections = false

        var body: some View {
            AppList {
                if separateSections {
                    ForEach(model.rows, id: \.self) { id in
                        AppSection("Day \(id)") { row(id) }
                    }
                } else {
                    AppSection("Transactions") {
                        ForEach(model.rows, id: \.self) { row($0) }
                    }
                }
            }
            .animateListChanges(value: model.rows)
            .listStyle(.insetGrouped)
            // Home suppresses period-filter animations. Stored-row deletions must
            // still animate inside that boundary.
            .transaction { $0.animation = nil }
        }

        private func row(_ id: Int) -> some View {
            Text("Transaction \(id)")
                .circleSwipeActions(isEnabled: !model.isBusy) {
                    CircleSwipeAction.delete { await model.delete(id) }
                }
        }
    }

    func testSuccessfulDeleteKeepsRowOffscreenAndAnimatesGapAndSectionRemoval() async throws {
        for separateSections in [false, true] {
            let model = DeletionFixture()
            let window = try makeWindow(DeletionList(model: model, separateSections: separateSections)
                .preferredColorScheme(.dark))
            defer { window.isHidden = true }
            try await settle(window)
            let probes = swipeObservers(in: window).sorted {
                $0.convert($0.bounds, to: window).minY < $1.convert($1.bounds, to: window).minY
            }
            let deleting = try XCTUnwrap(probes.first)
            let followingCell = try XCTUnwrap(probes.dropFirst().first?.pan.view)
            let initialY = followingCell.frame.minY
            let width = deleting.bounds.width
            deleting.configuration.onBegin()
            deleting.configuration.onChange(-width * 0.8, width)
            deleting.configuration.onEnd(0, width, false)
            var positions: [CGFloat] = []
            var observedPendingWrite = false
            for _ in 0..<60 {
                try await Task.sleep(for: .milliseconds(25))
                positions.append(followingCell.layer.presentation()?.frame.minY ?? followingCell.frame.minY)
                if model.isBusy && model.rows.contains(0) {
                    observedPendingWrite = true
                    XCTAssertEqual(deleting.configuration.revealedWidth, width, accuracy: 0.5,
                                   "A pending deletion must not slide back into the list")
                }
            }
            let finalY = followingCell.frame.minY
            XCTAssertTrue(observedPendingWrite)
            XCTAssertEqual(model.calls, 1)
            XCTAssertEqual(model.rows, [1, 2])
            XCTAssertLessThan(finalY, initialY - 30)
            XCTAssertTrue(positions.contains { $0 > finalY + 2 && $0 < initialY - 2 },
                          "The following row must move through intermediate positions, including when a date header disappears: \(positions)")
            attach(window, name: "Deleted-row-gap-closed-sections-\(separateSections)")
        }
    }

    func testDeleteButtonUsesTheSameExitWithoutClosingFirst() async throws {
        let model = DeletionFixture()
        let window = try makeWindow(DeletionList(model: model))
        defer { window.isHidden = true }
        try await settle(window)
        let deleting = try XCTUnwrap(swipeObservers(in: window).min {
            $0.convert($0.bounds, to: window).minY < $1.convert($1.bounds, to: window).minY
        })
        let width = deleting.bounds.width
        deleting.configuration.onBegin()
        deleting.configuration.onChange(-64, width)
        deleting.configuration.onEnd(0, width, false)
        try await settle(window)
        var visited = Set<ObjectIdentifier>()
        let elements = accessibilityObjects(in: window, visited: &visited)
        let match = elements.first(where: { element in
            let identifier = (element as? UIAccessibilityIdentification)?.accessibilityIdentifier
            return identifier == "circle-swipe-action.0" || element.accessibilityLabel == "Delete"
        })
        guard let button = match else {
            if #available(iOS 26.0, *), elements.allSatisfy({ $0.accessibilityLabel == nil }) {
                // iOS 26 exposes none of this hosted SwiftUI screen's accessibility
                // nodes in-process. Keep the activation regression on iOS 18;
                // both runtimes still exercise the shared removal path via a swipe.
                throw XCTSkip("iOS 26 does not expose SwiftUI accessibility nodes to hosted unit tests")
            }
            XCTFail("Missing Delete button. Accessible actions: \(elements.compactMap { $0.accessibilityLabel })")
            return
        }
        XCTAssertTrue(button.accessibilityActivate(), "Activate the revealed Delete button")
        var sawExit = false
        for _ in 0..<55 {
            try await Task.sleep(for: .milliseconds(25))
            if model.rows.contains(0) {
                let offset = deleting.configuration.revealedWidth
                XCTAssertGreaterThanOrEqual(offset, 63.5, "Delete must slide out, never close the swipe first")
                if offset > 70 && offset < width - 2 { sawExit = true }
            }
        }
        XCTAssertTrue(sawExit)
        XCTAssertEqual(model.calls, 1)
        XCTAssertEqual(model.rows, [1, 2])
    }

    private func accessibilityObjects(in object: NSObject, visited: inout Set<ObjectIdentifier>, depth: Int = 0) -> [NSObject] {
        guard depth < 30, visited.insert(ObjectIdentifier(object)).inserted else { return [] }
        var result = [object]
        let count = object.accessibilityElementCount()
        if count > 0 && count < 200 {
            for index in 0..<count {
                if let child = object.accessibilityElement(at: index) as? NSObject {
                    result += accessibilityObjects(in: child, visited: &visited, depth: depth + 1)
                }
            }
        }
        for child in ((object.automationElements ?? []) + (object.accessibilityElements ?? [])).compactMap({ $0 as? NSObject }) {
            result += accessibilityObjects(in: child, visited: &visited, depth: depth + 1)
        }
        if let view = object as? UIView {
            for child in view.subviews {
                result += accessibilityObjects(in: child, visited: &visited, depth: depth + 1)
            }
        }
        return result
    }

    func testDeleteAtMaximumSwipeDoesNotLeaveTheActionVisible() async throws {
        let model = DeletionFixture()
        let window = try makeWindow(DeletionList(model: model).preferredColorScheme(.dark))
        defer { window.isHidden = true }
        try await settle(window)
        let deleting = try XCTUnwrap(swipeObservers(in: window).min {
            $0.convert($0.bounds, to: window).minY < $1.convert($1.bounds, to: window).minY
        })
        let width = deleting.bounds.width
        let frame = deleting.convert(deleting.bounds, to: window)
        deleting.configuration.onBegin()
        deleting.configuration.onChange(-width, width)
        deleting.configuration.onEnd(0, width, false)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertTrue(model.isBusy)
        XCTAssertEqual(model.rows, [0, 1, 2])
        let page = UIColor.systemGroupedBackground.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        try assertPixel(in: screenshot(window), at: CGPoint(x: frame.midX, y: frame.midY - 9), matches: page)
        try await settle(window)
        XCTAssertEqual(model.rows, [1, 2])
    }

    func testCommittedDeleteStillRunsOnceWhenRowDisappearsDuringExit() async throws {
        let model = DeletionFixture()
        let window = try makeWindow(DeletionList(model: model))
        defer { window.isHidden = true }
        try await settle(window)
        let deleting = try XCTUnwrap(swipeObservers(in: window).min {
            $0.convert($0.bounds, to: window).minY < $1.convert($1.bounds, to: window).minY
        })
        let width = deleting.bounds.width
        deleting.configuration.onBegin()
        deleting.configuration.onChange(-width * 0.8, width)
        deleting.configuration.onEnd(0, width, false)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(model.calls, 0)
        window.rootViewController = UIHostingController(rootView: Text("Another screen"))
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertEqual(model.calls, 1)
        XCTAssertEqual(model.rows, [1, 2])
    }

    func testFailedDeleteRestoresRowWithoutCollapsingTheList() async throws {
        let model = DeletionFixture()
        model.succeeds = false
        let window = try makeWindow(DeletionList(model: model))
        defer { window.isHidden = true }
        try await settle(window)
        let probes = swipeObservers(in: window).sorted {
            $0.convert($0.bounds, to: window).minY < $1.convert($1.bounds, to: window).minY
        }
        let deleting = try XCTUnwrap(probes.first)
        let followingCell = try XCTUnwrap(probes.dropFirst().first?.pan.view)
        let initialY = followingCell.frame.minY
        let width = deleting.bounds.width
        deleting.configuration.onBegin()
        deleting.configuration.onChange(-width * 0.8, width)
        deleting.configuration.onEnd(0, width, false)
        try await Task.sleep(for: .milliseconds(1400))
        XCTAssertEqual(model.calls, 1)
        XCTAssertEqual(model.rows, [0, 1, 2])
        XCTAssertEqual(deleting.configuration.revealedWidth, 0)
        XCTAssertEqual(followingCell.frame.minY, initialY)
        XCTAssertTrue(deleting.pan.isEnabled)
    }

    private func pixel(in image: UIImage, at point: CGPoint) throws -> [CGFloat] {
        let crop = try XCTUnwrap(image.cgImage?.cropping(to: CGRect(
            x: point.x * image.scale, y: point.y * image.scale, width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8,
                                             bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return bytes.prefix(3).map { CGFloat($0) / 255 }
    }

    private func assertPixel(in image: UIImage, at point: CGPoint, matches color: UIColor,
                             file: StaticString = #filePath, line: UInt = #line) throws {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: nil)
        let actual = try pixel(in: image, at: point)
        for (value, expected) in zip(actual, [red, green, blue]) {
            XCTAssertEqual(value, expected, accuracy: 0.035, file: file, line: line)
        }
    }

    private func swipeObservers(in view: UIView) -> [CircleSwipeGesture.ObserverView] {
        if let probe = view as? CircleSwipeGesture.ObserverView { return [probe] }
        return view.subviews.flatMap { swipeObservers(in: $0) }
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
        try await Task.sleep(for: .milliseconds(550))
    }

    private func findCollection(in view: UIView) -> UICollectionView? {
        if let list = view as? UICollectionView { return list }
        return view.subviews.lazy.compactMap { self.findCollection(in: $0) }.first
    }

    private func screenshot(_ window: UIWindow) -> UIImage {
        UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
    }

    private func attach(_ window: UIWindow, name: String) {
        let attachment = XCTAttachment(image: screenshot(window))
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
