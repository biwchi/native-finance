import SwiftUI
import UIKit
import XCTest
@testable import FinanceTracker

@MainActor
final class QuickEntryKeyboardTests: XCTestCase {
    private typealias Controller = QuickEntryKeyboardContainer<AnyView>.Controller

    func testBackgroundRestoresNormalKeyboardAvoidance() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let originalKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let presentation = PresentationState()
        presentation.requested = true
        let field = UITextField()
        field.inputView = UIInputView(frame: CGRect(x: 0, y: 0, width: 320, height: 300), inputViewStyle: .keyboard)
        let host = UIHostingController(rootView: FormFixture(presentation: presentation, field: field))
        // iOS 18 starts observing keyboard geometry when the guide is created.
        // Install it before focus, rather than first querying it after the show.
        let keyboardGuide = host.view.keyboardLayoutGuide
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            field.resignFirstResponder()
            window.isHidden = true
            window.rootViewController = nil
            originalKeyWindow?.makeKey()
        }
        try await Task.sleep(for: .milliseconds(150))
        presentation.requested = false
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(field.becomeFirstResponder())
        try await Task.sleep(for: .milliseconds(600))
        let list = try XCTUnwrap(findCollection(in: host.view))
        let keyboardTop = host.view.convert(keyboardGuide.layoutFrame, to: window).minY
        XCTAssertLessThan(keyboardTop, window.bounds.maxY - 100)
        XCTAssertLessThanOrEqual(list.convert(list.bounds, to: window).maxY - list.adjustedContentInset.bottom,
                                keyboardTop + 1 / window.screen.scale,
                                "Forms must resume keyboard avoidance once Quick Entry is dismissed")
    }

    func testDashboardStaysStillThroughoutKeyboardTransitions() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let originalKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "QuickEntryKeyboardTests.Layout"))
        defaults.set("USD", forKey: AppPreferences.defaultCurrencyKey)
        defer { defaults.removePersistentDomain(forName: "QuickEntryKeyboardTests.Layout") }
        let now = Date.now
        let account = Account(id: UUID(), name: "Everyday", currency: "USD",
            icon: "credit-card", iconColor: .blue, createdAt: "", updatedAt: "")
        let transactions = (0..<18).map { index in
            FinanceTransaction(id: UUID(), accountId: account.id, kind: .expense, amount: "4.50", currency: "USD",
                category: nil, note: nil, occurredAt: now, createdAt: now, updatedAt: now, counterparty: "Coffee \(index)")
        }

        for scheme in [ColorScheme.light, .dark] {
            let presentation = PresentationState()
            let transactionStore = TransactionStore.preview(transactions: transactions)
            transactionStore.quickEntryText = "Coffee 4.50"
            let host = UIHostingController(rootView: DashboardFixture(presentation: presentation)
                .environmentObject(AccountStore.preview(accounts: [account]))
                .environmentObject(transactionStore)
                .environmentObject(BudgetStore.preview(nil))
                .defaultAppStorage(defaults)
                .environment(\.colorScheme, scheme))
            let window = UIWindow(windowScene: scene)
            window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
                originalKeyWindow?.makeKey()
            }
            try await Task.sleep(for: .milliseconds(500))
            let list = try XCTUnwrap(findCollection(in: host.view))
            XCTAssertGreaterThan(list.visibleCells.count, 2, "Exercise the date filter, summary and transactions")

            // Also preserve an existing scroll position, not just the top of Home.
            for scrollDistance in [CGFloat(0), 120, 240] {
                list.setContentOffset(CGPoint(x: 0, y: -list.adjustedContentInset.top + scrollDistance), animated: false)
                try await Task.sleep(for: .milliseconds(150))
                let baseline = layout(of: list, in: window)
                let restingImage = scrollDistance == 0 ? snapshot(in: window, name: "Home-\(scheme)-resting") : nil
                presentation.dismissing = false
                presentation.requested = true
                try await assertStableLayout(of: list, in: window, baseline: baseline)
                let controller = try XCTUnwrap(findKeyboardController(in: host))
                let input = try XCTUnwrap(controller.accessoryController.textInput)
                XCTAssertTrue(input.isFirstResponder)
                // Supply a software keyboard even when the simulator has a
                // hardware keyboard connected, then exercise its frame changes.
                let editor = try XCTUnwrap(input as? UITextView)
                XCTAssertEqual(editor.text, transactionStore.quickEntryText, "Reopening the composer keeps the session text")
                editor.inputView = UIInputView(frame: CGRect(x: 0, y: 0, width: window.bounds.width, height: 300),
                                              inputViewStyle: .keyboard)
                editor.reloadInputViews()
                try await assertStableLayout(of: list, in: window, baseline: baseline)

                input.insertText("\nLunch 12\nBus 2\nTea 3")
                try await assertStableLayout(of: list, in: window, baseline: baseline)
                let draftText = editor.text
                XCTAssertEqual(transactionStore.quickEntryText, draftText)
                if let restingImage {
                    let editingImage = snapshot(in: window, name: "Home-\(scheme)-composer-open")
                    let summary = try XCTUnwrap(list.cellForItem(at: IndexPath(item: 1, section: 0)))
                    try assertMatchingSummary(restingImage, editingImage, frame: summary.convert(summary.bounds, to: window))
                }

                if scrollDistance == 0 {
                    let pan = SimulatedPan()
                    controller.observeDismissalPan(pan)
                    pan.reportedState = .changed
                    pan.distance = 100
                    XCTAssertFalse(input.resignFirstResponder())
                    pan.reportedState = .cancelled
                    controller.dismissalPanChanged(pan)
                    try await assertStableLayout(of: list, in: window, baseline: baseline)
                    XCTAssertTrue(presentation.requested)
                    XCTAssertTrue(input.isFirstResponder, "A cancelled dismissal keeps the draft active")
                    pan.reportedState = .ended
                    pan.distance = 90
                    controller.dismissalPanChanged(pan)
                } else if scrollDistance == 120 {
                    controller.perform(NSSelectorFromString("backgroundTapped"))
                } else {
                    presentation.dismissing = true
                }
                try await assertStableLayout(of: list, in: window, baseline: baseline)
                XCTAssertFalse(presentation.requested, "Restore the controls only after native dismissal completes")
                XCTAssertEqual(transactionStore.quickEntryText, draftText, "Dismissing the composer must keep unfinished text")
                if scrollDistance == 0 { _ = snapshot(in: window, name: "Home-\(scheme)-dismissed") }
            }
        }
    }

    func testAccessoryOpensFromAnAlreadyVisibleSwiftUIScreen() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let originalKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let presentation = PresentationState()
        let host = UIHostingController(rootView: PresentationFixture(presentation: presentation))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            originalKeyWindow?.makeKey()
        }
        try await Task.sleep(for: .milliseconds(100))
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { presentation.requested = true }
        try await Task.sleep(for: .milliseconds(900))
        let controller = try XCTUnwrap(findKeyboardController(in: host))
        XCTAssertNotNil(controller.accessory.window)
        XCTAssertGreaterThan(controller.accessory.bounds.height, 60)
        XCTAssertNotNil(firstResponder(in: controller.accessory))
        withTransaction(transaction) { presentation.requested = false }
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertNil(firstResponder(in: controller.accessory))
        if let accessoryWindow = controller.accessory.window {
            let frame = controller.accessory.convert(controller.accessory.bounds, to: accessoryWindow)
            XCTAssertGreaterThanOrEqual(frame.minY, accessoryWindow.bounds.maxY,
                "A cached keyboard accessory must be offscreen after removal: \(frame)")
        }
    }

    func testComposerIsInNativeAccessoryAndDismissesWithKeyboard() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let originalKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let dismissed = expectation(description: "Native keyboard dismissal completed")
        dismissed.assertForOverFulfill = true
        let controller = Controller(content: AnyView(EntryFixture()), onBackgroundTap: {},
            onDismiss: { dismissed.fulfill() })
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            controller.tearDown()
            window.isHidden = true
            window.rootViewController = nil
            originalKeyWindow?.makeKey()
        }
        try await Task.sleep(for: .milliseconds(900))
        XCTAssertTrue(controller.inputAccessoryViewController === controller.accessoryController)
        XCTAssertNotNil(controller.accessory.window)
        XCTAssertTrue(controller.host.view.isDescendant(of: controller.accessory))
        XCTAssertNotNil(firstResponder(in: controller.accessory), "The composer must retain a live text input in the system accessory")
        XCTAssertGreaterThan(controller.accessory.bounds.height, 60)
        XCTAssertLessThan(controller.accessory.bounds.height, 250)
        XCTAssertEqual(controller.accessory.keyboardDismissMode, .none)
        XCTAssertEqual(controller.scrollView.keyboardDismissMode, .interactiveWithAccessory)
        XCTAssertEqual(controller.host.view.transform, .identity)
        XCTAssertFalse(controller.isFinishingDismissal)

        NotificationCenter.default.post(name: UIResponder.keyboardDidHideNotification, object: nil)
        XCTAssertFalse(controller.isFinishingDismissal, "A stale hide notification during first-responder handoff must not close the live editor")

        let initialHeight = controller.accessory.bounds.height
        let input = try XCTUnwrap(controller.accessoryController.textInput)
        input.insertText("\nLunch 12\nBus 2\nTea 3")
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(input.isFirstResponder, "Editing the draft must preserve focus")
        XCTAssertGreaterThan(controller.accessory.bounds.height, initialHeight, "The accessory must grow with a multiline draft")

        let editor = try XCTUnwrap(input as? QuickEntryTextView.Editor)
        let pan = SimulatedPan()
        controller.observeDismissalPan(pan)
        pan.reportedState = .changed
        pan.distance = 260
        XCTAssertFalse(editor.resignFirstResponder(), "Even a long drag must retain focus while the finger is down")
        pan.reportedState = .ended
        pan.distance = 89
        controller.dismissalPanChanged(pan)
        XCTAssertFalse(editor.resignFirstResponder(), "A short released drag must keep the editor open")
        pan.reportedState = .cancelled
        pan.distance = 260
        controller.dismissalPanChanged(pan)
        XCTAssertFalse(editor.resignFirstResponder(), "An interrupted drag must retain the draft and focus")
        pan.reportedState = .ended
        pan.distance = 90
        controller.dismissalPanChanged(pan)
        XCTAssertFalse(editor.isFirstResponder, "A sufficiently long released drag dismisses the editor")
        await fulfillment(of: [dismissed], timeout: 3)
        XCTAssertNil(firstResponder(in: controller.accessory))
        XCTAssertEqual(controller.host.view.transform, .identity, "There must be no separate composer translation after UIKit dismisses the keyboard")
        controller.requestDismissal()
        try await Task.sleep(for: .milliseconds(100))
    }

    func testAccessoryHeightTracksContentWithoutIncludingKeyboardSafeArea() async throws {
        let controller = Controller(content: AnyView(Color.clear.frame(height: 120)), onBackgroundTap: {}, onDismiss: {})
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.layoutIfNeeded()
        for height in [CGFloat(120), 220, 160] {
            controller.host.rootView = AnyView(Color.clear.frame(height: height))
            controller.host.view.invalidateIntrinsicContentSize()
            try await Task.sleep(for: .milliseconds(40))
            controller.accessoryController.updateHeight()
            XCTAssertEqual(controller.accessoryController.sizingView.intrinsicContentSize.height, height, accuracy: 1)
        }
        XCTAssertTrue(controller.host.safeAreaRegions.isEmpty)
        controller.tearDown()
    }

    func testEarlyAccessoryDetachmentWaitsForKeyboardAnimation() async throws {
        var dismissalCount = 0
        let controller = Controller(content: AnyView(Color.clear.frame(height: 120)),
            onBackgroundTap: {}, onDismiss: { dismissalCount += 1 })
        controller.loadViewIfNeeded()
        defer { controller.tearDown() }

        NotificationCenter.default.post(name: UIResponder.keyboardWillShowNotification, object: nil)
        controller.requestDismissal()
        NotificationCenter.default.post(name: UIResponder.keyboardWillHideNotification, object: nil,
            userInfo: [UIResponder.keyboardAnimationDurationUserInfoKey: 0.01])
        controller.accessoryController.onDetached?()

        // iOS 26 can detach the accessory and outlast its advertised duration
        // while the keyboard's dismissal is still being rendered.
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(dismissalCount, 0, "Keep Home isolated until UIKit confirms the keyboard is hidden")
        NotificationCenter.default.post(name: UIResponder.keyboardDidHideNotification, object: nil)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(dismissalCount, 1)
    }

    func testOutsideTapStartsNativeDismissalBeforeUpdatingSwiftUI() async {
        var controller: Controller!
        var backgroundTapCount = 0
        let dismissed = expectation(description: "Outside tap dismissal completed")
        controller = Controller(content: AnyView(Color.clear.frame(height: 120)), onBackgroundTap: {
            backgroundTapCount += 1
            XCTAssertTrue(controller.isFinishingDismissal,
                "Start dismissal in the gesture handler, before its SwiftUI callback updates the presentation")
        }, onDismiss: { dismissed.fulfill() })
        controller.loadViewIfNeeded()
        defer {
            controller.tearDown()
            controller.onBackgroundTap = {}
        }
        controller.perform(NSSelectorFromString("backgroundTapped"))
        XCTAssertEqual(backgroundTapCount, 1)
        await fulfillment(of: [dismissed], timeout: 1)
    }

    func testHardwareKeyboardDismissalCompletesOnce() async {
        let dismissed = expectation(description: "Accessory-only dismissal completed")
        dismissed.assertForOverFulfill = true
        let controller = Controller(content: AnyView(Color.clear.frame(height: 120)), onBackgroundTap: {}, onDismiss: { dismissed.fulfill() })
        controller.loadViewIfNeeded()
        controller.requestDismissal()
        controller.requestDismissal()
        await fulfillment(of: [dismissed], timeout: 1)
        XCTAssertEqual(controller.host.view.transform, .identity)
    }

    private func firstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        return view.subviews.lazy.compactMap { self.firstResponder(in: $0) }.first
    }

    private func findCollection(in view: UIView) -> UICollectionView? {
        if let list = view as? UICollectionView { return list }
        return view.subviews.lazy.compactMap { self.findCollection(in: $0) }.first
    }

    private func layout(of list: UICollectionView, in window: UIWindow) -> [CGFloat] {
        let frame = list.convert(list.bounds, to: window)
        let layer = list.layer.presentation() ?? list.layer
        let renderedFrame = layer.convert(layer.bounds, to: window.layer.presentation() ?? window.layer)
        return [frame.minY, frame.height, list.contentOffset.y,
                list.adjustedContentInset.top, list.adjustedContentInset.bottom,
                renderedFrame.minY, renderedFrame.height]
    }

    private func snapshot(in window: UIWindow, name: String) -> UIImage {
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return image
    }

    private func assertMatchingSummary(_ before: UIImage, _ after: UIImage, frame: CGRect) throws {
        func pixels(in image: UIImage) throws -> [UInt8] {
            let crop = frame.applying(CGAffineTransform(scaleX: image.scale, y: image.scale))
            let sample = try XCTUnwrap(image.cgImage?.cropping(to: crop))
            var bytes = [UInt8](repeating: 0, count: sample.width * sample.height * 4)
            try bytes.withUnsafeMutableBytes { buffer in
                let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: sample.width, height: sample.height,
                    bitsPerComponent: 8, bytesPerRow: sample.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(sample, in: CGRect(x: 0, y: 0, width: sample.width, height: sample.height))
            }
            return bytes
        }
        let first = try pixels(in: before)
        let second = try pixels(in: after)
        XCTAssertEqual(first.count, second.count)
        let difference = zip(first, second).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) }
        XCTAssertLessThan(difference / Double(max(first.count, 1)) / 255, 0.015,
            "The detached summary must remain visible in the same position, not just retain an empty list placeholder")
    }

    private func assertStableLayout(of list: UICollectionView, in window: UIWindow, baseline: [CGFloat],
                                    file: StaticString = #filePath, line: UInt = #line) async throws {
        var maximumMovement: CGFloat = 0
        var largestChange = baseline
        // Sample during the animation, since settled-state assertions miss flicker.
        for _ in 0..<45 {
            try await Task.sleep(for: .milliseconds(16))
            let current = layout(of: list, in: window)
            let movement = zip(current, baseline).map { abs($0 - $1) }.max() ?? 0
            if movement > maximumMovement {
                maximumMovement = movement
                largestChange = current
            }
        }
        XCTAssertLessThanOrEqual(maximumMovement, 1,
            "Home's viewport, scroll offset and insets must remain fixed behind Quick Entry: \(baseline) → \(largestChange)",
            file: file, line: line)
    }

    private func findKeyboardController(in controller: UIViewController) -> Controller? {
        if let controller = controller as? Controller { return controller }
        if let presented = controller.presentedViewController, let found = findKeyboardController(in: presented) { return found }
        return controller.children.lazy.compactMap { self.findKeyboardController(in: $0) }.first
    }

    private struct PresentationFixture: View {
        @ObservedObject var presentation: PresentationState
        @State private var text = ""

        var body: some View {
            QuickEntryPresentation(isPresented: $presentation.requested, isDismissing: presentation.dismissing,
                                   onBackgroundTap: { presentation.dismissing = true }) {
                NavigationStack {
                    List {
                        Text("Transactions")
                    }
                    .safeAreaInset(edge: .bottom) {
                        Button("Add transaction") { presentation.requested = true }
                            .padding(.bottom, 16)
                    }
                    .navigationTitle("Dashboard")
                }
            } composer: {
                AnyView(QuickEntryTextView(text: $text).padding(16))
            }
        }
    }

    private struct DashboardFixture: View {
        @ObservedObject var presentation: PresentationState
        @EnvironmentObject private var transactionStore: TransactionStore

        var body: some View {
            QuickEntryPresentation(isPresented: $presentation.requested, isDismissing: presentation.dismissing,
                                   onBackgroundTap: { presentation.dismissing = true }) {
                DashboardView(isPresentingQuickEntry: presentation.requested,
                              onAddTransaction: { presentation.requested = true }, onScanTransaction: {})
            } composer: {
                AnyView(QuickEntryTextView(text: $transactionStore.quickEntryText).padding(16))
            }
        }
    }

    private struct FormFixture: View {
        @ObservedObject var presentation: PresentationState
        let field: UITextField

        var body: some View {
            QuickEntryPresentation(isPresented: .constant(false), isDismissing: false, onBackgroundTap: {}) {
                NavigationStack {
                    QuickEntryBackground(isPresented: presentation.requested) {
                        AppForm {
                            Section("Account") { FormField(field: field) }
                            ForEach(0..<16) { Text("Setting \($0)") }
                        }
                    }
                    .ignoresSafeArea()
                }
            } composer: {
                EmptyView()
            }
        }
    }

    private struct FormField: UIViewRepresentable {
        let field: UITextField
        func makeUIView(context: Context) -> UITextField { field }
        func updateUIView(_ view: UITextField, context: Context) {}
    }

    private struct EntryFixture: View {
        @State private var text = "Coffee 4.50 this morning"

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Account")
                QuickEntryTextView(text: $text)
                    .padding(12)
                    .background(.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 18))
            }
            .padding(8)
        }
    }

    private final class PresentationState: ObservableObject {
        @Published var requested = false
        @Published var dismissing = false
    }

    private final class SimulatedPan: UIPanGestureRecognizer {
        var reportedState: UIGestureRecognizer.State = .possible
        var distance: CGFloat = 0
        override var state: UIGestureRecognizer.State {
            get { reportedState }
            set { reportedState = newValue }
        }
        override func translation(in view: UIView?) -> CGPoint { CGPoint(x: 0, y: distance) }
    }
}
