import SwiftUI
import UIKit
import XCTest
@testable import FinanceTracker

@MainActor
final class AppSheetTests: XCTestCase {
    func testTransactionToolbarHasSymmetricSheetInsets() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let window = try makeWindow(Color.blue.appSheet(isPresented: .constant(true)) {
                AddTransactionView()
                    .environmentObject(AccountStore.preview(accounts: []))
                    .environmentObject(TransactionStore.preview(transactions: []))
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }.preferredColorScheme(scheme))
            defer { window.isHidden = true }
            try await settle()
            let presented = try XCTUnwrap(window.rootViewController?.presentedViewController)
            let navigation = try XCTUnwrap(controllers(presented).compactMap { $0 as? UINavigationController }.first)
            let controls = descendants(navigation.navigationBar).filter {
                abs($0.bounds.width - 44) < 0.5 && abs($0.bounds.height - 44) < 0.5
            }.map { $0.convert($0.bounds, to: presented.view) }
            let close = try XCTUnwrap(controls.first { $0.minX < 40 })
            if #available(iOS 26.0, *) {
                XCTAssertEqual(close.minX, AppSpacing.extraLarge, accuracy: 0.5)
            } else {
                XCTAssertEqual(close.minX, AppSpacing.large, accuracy: 0.5)
            }
            XCTAssertEqual(close.minY, AppSpacing.large, accuracy: 0.5,
                           "Keep the native iOS 26 top gap; on older iOS it matches the 16-point leading inset")
            try assertContinuousHeader(window, presented: presented, name: "Transaction \(scheme)")
            attach(window, name: "Transaction-sheet-toolbar-insets-\(scheme)")
        }
    }

    func testProductionNavigationSheetLayouts() async throws {
        let accounts = AccountStore.preview(accounts: [])
        let transactions = TransactionStore.preview(transactions: [])
        let scans = ScanDraftStore(previewItems: [])
        let screens: [(String, AnyView)] = [
            ("Quick-entry review", AnyView(QuickEntryReviewView(
                presentation: QuickEntryReviewPresentation(prompt: "Coffee", drafts: []), onCommit: { _ in 0 }))),
            ("Scan review", AnyView(QuickEntryReviewView(
                presentation: QuickEntryReviewPresentation(prompt: "Receipt", drafts: [], source: .photo)))),
            ("Document review", AnyView(QuickEntryReviewView(
                presentation: QuickEntryReviewPresentation(prompt: "Statement", drafts: [], source: .document)))),
            ("CSV review", AnyView(QuickEntryReviewView(
                presentation: QuickEntryReviewPresentation(prompt: "CSV rows", drafts: [], source: .csv)))),
            ("Scan drafts", AnyView(ScanDraftsView(onReview: { _ in }, onReplace: { _ in }, onManualEntry: { _ in }))),
            ("Accounts", AnyView(AccountManagementView())),
            ("Account editor", AnyView(AccountEditorView())),
            ("Rate help", AnyView(CurrencyRateHelpView())),
            ("Recipients", AnyView(DebtRecipientsView())),
            ("Recipient editor", AnyView(DebtEditorView(onSave: { _ in }))),
            ("Category editor", AnyView(CategoryEditorView(editor: CategoryEditor(category: nil, kind: .expense)))),
            ("New category", AnyView(NewTransactionCategoryView(kind: .expense, onCreated: { _ in }))),
            ("Delete confirmation", AnyView(DeleteDataConfirmationView(title: "Delete data", explanation: "Test fixture", delete: { _ in }))),
            ("CSV help", AnyView(CSVImportHelpView())),
            ("Metric detail", AnyView(DashboardSummaryMetrics.Detail(metric: .net, amount: 10, currency: "USD"))),
        ]
        for scheme in [ColorScheme.light, .dark] {
            for (name, screen) in screens {
                let window = try makeWindow(Color.blue.appSheet(isPresented: .constant(true)) {
                    screen
                        .environmentObject(accounts)
                        .environmentObject(transactions)
                        .environmentObject(scans)
                        .presentationDragIndicator(.visible)
                }.preferredColorScheme(scheme))
                defer { window.endEditing(true); window.isHidden = true; window.rootViewController = nil }
                try await settle()
                window.endEditing(true)
                try await Task.sleep(for: .milliseconds(350))
                let presented = try XCTUnwrap(window.rootViewController?.presentedViewController, name)
                let navigation = try XCTUnwrap(controllers(presented).compactMap { $0 as? UINavigationController }.first, name)
                let frame = navigation.view.convert(navigation.view.bounds, to: presented.view)
                let expectedInset: CGFloat
                if #available(iOS 26.0, *) { expectedInset = 0 } else { expectedInset = AppSpacing.legacySheetToolbarTopInset }
                XCTAssertEqual(frame.minY, 0, accuracy: 0.5, "\(name): background reaches the sheet edge")
                XCTAssertEqual(presented.additionalSafeAreaInsets.top, expectedInset, accuracy: 0.5, name)
                XCTAssertEqual(frame.minX, 0, accuracy: 0.5, name)
                XCTAssertEqual(frame.maxX, presented.view.bounds.maxX, accuracy: 0.5, name)
                if #unavailable(iOS 26.0), name == "Quick-entry review" {
                    let buttons = descendants(navigation.navigationBar).filter {
                        abs($0.bounds.height - 44) < 0.5 && $0.bounds.width >= 44 && $0.bounds.width < 130
                    }.map { $0.convert($0.bounds, to: presented.view) }
                    let close = try XCTUnwrap(buttons.first { $0.minX == AppSpacing.large })
                    XCTAssertEqual(close.minY, AppSpacing.large, accuracy: 0.5)
                }
                try assertContinuousHeader(window, presented: presented, name: "\(name) \(scheme)")
                attach(window, name: "Sheet-layout-\(name)-\(scheme)")
            }
        }
    }

    func testNativeIOS26Reference() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("iOS 26 visual reference") }
        for scheme in [ColorScheme.light, .dark] {
            for radius in [CGFloat?.none, AppRadius.sheet] {
                let state = Fixture()
                let window = try makeWindow(ReferenceHost(state: state, radius: radius).preferredColorScheme(scheme))
                defer { window.isHidden = true }
                try await settle()
                state.presented = true
                try await settle()
                XCTAssertNotNil(window.rootViewController?.presentedViewController)
                attach(window, name: "Reference-\(radius == nil ? "native" : "app-radius")-\(scheme)")
            }
        }
    }

    func testBindingsDetentsScrollingKeyboardAndNestedDismissal() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let state = Fixture()
            let window = try makeWindow(SheetHost(state: state).preferredColorScheme(scheme))
            defer { window.isHidden = true }
            try await settle()
            state.presented = true
            try await settle()
            let parent = try XCTUnwrap(window.rootViewController?.presentedViewController)
            let sheet = try XCTUnwrap(parent.sheetPresentationController)
            XCTAssertEqual(sheet.preferredCornerRadius, AppRadius.sheet)
            XCTAssertEqual(Set(sheet.detents.map(\.identifier)), [.medium, .large])
            XCTAssertTrue(sheet.prefersGrabberVisible)
            try assertContinuousHeader(window, presented: parent, name: "Medium \(scheme)")
            attach(window, name: "AppSheet-medium-\(scheme)")

            sheet.animateChanges { sheet.selectedDetentIdentifier = .large }
            try await settle()
            let list = try XCTUnwrap(descendants(parent.view).compactMap { $0 as? UICollectionView }.first)
            list.setContentOffset(CGPoint(x: 0, y: 500), animated: false)
            try await settle()
            XCTAssertGreaterThan(list.contentOffset.y, 400)
            XCTAssertEqual(sheet.preferredCornerRadius, AppRadius.sheet)
            attach(window, name: "AppSheet-scrolled-\(scheme)")
            list.setContentOffset(CGPoint(x: 0, y: -list.adjustedContentInset.top), animated: false)
            try await settle()
            let guide = parent.view.keyboardLayoutGuide
            state.field.inputView = UIInputView(frame: CGRect(x: 0, y: 0, width: window.bounds.width, height: 300), inputViewStyle: .keyboard)
            XCTAssertTrue(state.field.becomeFirstResponder())
            try await settle()
            let keyboardTop = parent.view.convert(guide.layoutFrame, to: window).minY
            XCTAssertLessThan(keyboardTop, window.bounds.maxY - 100)
            XCTAssertLessThanOrEqual(list.convert(list.bounds, to: window).maxY - list.adjustedContentInset.bottom, keyboardTop + 1)
            attach(window, name: "AppSheet-keyboard-\(scheme)")
            state.field.resignFirstResponder()
            try await settle()

            state.path = [1]
            try await settle()
            XCTAssertTrue(controllers(parent).compactMap { $0 as? UINavigationController }
                .contains { $0.viewControllers.count == 2 })
            attach(window, name: "AppSheet-navigation-\(scheme)")
            state.path = []
            try await settle()
            state.blocksDismissal = true
            try await settle()
            XCTAssertTrue(parent.isModalInPresentation)
            state.blocksDismissal = false
            state.item = Route(id: 7)
            try await settle()
            let child = try XCTUnwrap(parent.presentedViewController)
            XCTAssertEqual(child.sheetPresentationController?.preferredCornerRadius, AppRadius.sheet)
            let childNavigation = try XCTUnwrap(controllers(child).compactMap { $0 as? UINavigationController }.first)
            let childFrame = childNavigation.view.convert(childNavigation.view.bounds, to: child.view)
            XCTAssertEqual(childFrame.minY, 0, accuracy: 0.5)
            if #available(iOS 26.0, *) {
                XCTAssertEqual(child.additionalSafeAreaInsets.top, 0, accuracy: 0.5)
            } else {
                XCTAssertEqual(child.additionalSafeAreaInsets.top, AppSpacing.legacySheetToolbarTopInset, accuracy: 0.5,
                               "Item-based nested navigation sheets receive the default inset exactly once")
            }
            try assertContinuousHeader(window, presented: child, name: "Nested \(scheme)")
            XCTAssertEqual(state.receivedItem, 7)
            XCTAssertEqual(state.inheritedValue, "Inherited environment")
            attach(window, name: "AppSheet-nested-\(scheme)")
            try XCTUnwrap(state.dismissItem)()
            try await settle()
            XCTAssertNil(state.item)
            XCTAssertEqual(state.itemDismissals, 1)
            XCTAssertTrue(state.presented)
            XCTAssertNil(parent.presentedViewController)
            if #unavailable(iOS 26.0) {
                XCTAssertEqual(parent.additionalSafeAreaInsets.top, AppSpacing.legacySheetToolbarTopInset,
                               "Dismissing a child must not change its parent's inset")
            }
            try assertContinuousHeader(window, presented: parent, name: "After nested dismissal \(scheme)")
            try XCTUnwrap(state.dismissParent)()
            try await settle()
            XCTAssertFalse(state.presented)
            XCTAssertEqual(state.dismissals, 1)
            XCTAssertNil(window.rootViewController?.presentedViewController)
        }
    }

    func testChangingLayoutRestoresSheetSafeArea() async throws {
        let state = Fixture()
        let window = try makeWindow(SheetHost(state: state))
        defer { window.isHidden = true }
        try await settle()
        state.presented = true
        try await settle()
        let controller = try XCTUnwrap(window.rootViewController?.presentedViewController)
        let expected: CGFloat
        if #available(iOS 26.0, *) { expected = 0 } else { expected = AppSpacing.legacySheetToolbarTopInset }
        XCTAssertEqual(controller.additionalSafeAreaInsets.top, expected)
        state.layout = .content
        try await settle()
        XCTAssertEqual(controller.additionalSafeAreaInsets.top, 0)
        state.layout = .navigation
        try await settle()
        XCTAssertEqual(controller.additionalSafeAreaInsets.top, expected, "Reinstall the inset without accumulating it")
    }

    func testItemReplacementAndBindingDismissal() async throws {
        let state = Fixture()
        let window = try makeWindow(SheetHost(state: state))
        defer { window.isHidden = true }
        try await settle()
        state.presented = true
        try await settle()
        state.item = Route(id: 1)
        try await settle()
        XCTAssertEqual(state.receivedItem, 1)
        state.item = Route(id: 2)
        try await settle()
        XCTAssertEqual(state.receivedItem, 2)
        state.item = nil
        try await settle()
        XCTAssertNil(window.rootViewController?.presentedViewController?.presentedViewController)
        state.presented = false
        try await settle()
        XCTAssertEqual(state.dismissals, 1)
    }

    func testCameraSheetSafeAreasInBothAppearances() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let state = Fixture()
            let window = try makeWindow(CameraHost(state: state).preferredColorScheme(scheme))
            defer { window.isHidden = true }
            try await settle()
            state.presented = true
            try await settle()
            let controller = try XCTUnwrap(window.rootViewController?.presentedViewController)
            XCTAssertEqual(controller.sheetPresentationController?.preferredCornerRadius, AppRadius.sheet)
            XCTAssertFalse(try XCTUnwrap(controller.sheetPresentationController).prefersGrabberVisible)
            XCTAssertGreaterThan(controller.view.safeAreaInsets.bottom, 0)
            XCTAssertGreaterThan(state.cameraBarHeight, 76)
            XCTAssertLessThan(state.cameraBarHeight, controller.view.bounds.height / 2)
            attach(window, name: "AppSheet-camera-safe-areas-\(scheme)")
            state.presented = false
            try await settle()
        }
    }

    private final class SharedEnvironment: ObservableObject {
        let value = "Inherited environment"
    }

    private struct SheetHost: View {
        @ObservedObject var state: Fixture
        @StateObject private var shared = SharedEnvironment()
        var body: some View {
            Color.blue
                .appSheet(isPresented: $state.presented, layout: state.layout, onDismiss: { state.dismissals += 1 }) {
                    SheetContent(state: state)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .interactiveDismissDisabled(state.blocksDismissal)
                }
                .environmentObject(shared)
        }
    }

    private struct SheetContent: View {
        @ObservedObject var state: Fixture
        @Environment(\.dismiss) private var dismiss
        var body: some View {
            NavigationStack(path: $state.path) {
                AppForm {
                    AppSection {
                        Field(field: state.field).frame(height: 44)
                        NavigationLink("Details", value: 1)
                        ForEach(0..<40) { Text("Row \($0)") }
                    }
                }
                .navigationTitle("Shared sheet")
                .navigationDestination(for: Int.self) { _ in Text("Sheet details").navigationTitle("Details") }
            }
            .onAppear { state.dismissParent = { dismiss() } }
            .appSheet(item: $state.item, background: AppColor.elevatedSurface,
                      onDismiss: { state.itemDismissals += 1 }) { route in
                NestedContent(state: state, route: route)
                    .presentationDetents([.height(280)])
                    .presentationDragIndicator(.hidden)
            }
        }
    }

    private struct NestedContent: View {
        @ObservedObject var state: Fixture
        let route: Route
        @Environment(\.dismiss) private var dismiss
        @EnvironmentObject private var shared: SharedEnvironment
        var body: some View {
            NavigationStack {
                Text("Nested sheet \(route.id)")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle("Nested sheet")
                    .navigationBarTitleDisplayMode(.inline)
            }
                .onAppear {
                    state.receivedItem = route.id
                    state.inheritedValue = shared.value
                    state.dismissItem = { dismiss() }
                }
                .onChange(of: route.id) { _, id in state.receivedItem = id }
        }
    }

    private struct Field: UIViewRepresentable {
        let field: UITextField
        func makeUIView(context: Context) -> UITextField {
            field.placeholder = "Keyboard avoidance"
            return field
        }
        func updateUIView(_ uiView: UITextField, context: Context) {}
    }

    private struct CameraHost: View {
        @ObservedObject var state: Fixture
        @StateObject private var drafts = ScanDraftStore(previewItems: [])
        var body: some View {
            Color.blue.appSheet(isPresented: $state.presented, layout: .content, background: AppColor.cameraBackground) {
                ReceiptScannerView(defaultAccountID: UUID(), onBottomActionBarHeightChange: { state.cameraBarHeight = $0 })
                    .environmentObject(drafts)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
            }
        }
    }

    private final class Fixture: ObservableObject {
        @Published var presented = false
        @Published var item: Route?
        @Published var blocksDismissal = false
        @Published var layout: AppSheetLayout = .navigation
        @Published var path: [Int] = []
        let field = UITextField()
        var dismissParent: (() -> Void)?
        var dismissItem: (() -> Void)?
        var receivedItem: Int?
        var inheritedValue: String?
        var cameraBarHeight: CGFloat = 0
        var dismissals = 0
        var itemDismissals = 0
    }

    private struct Route: Identifiable {
        let id: Int
    }

    private struct ReferenceHost: View {
        @ObservedObject var state: Fixture
        var radius: CGFloat?
        var body: some View {
            Color.blue.sheet(isPresented: $state.presented) {
                NavigationStack {
                    Text("Native iOS 26 reference")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .navigationTitle("Reference")
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(radius)
            }
        }
    }

    private func makeWindow<Content: View>(_ content: Content) throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: content)
        window.makeKeyAndVisible()
        return window
    }

    private func settle() async throws {
        try await Task.sleep(for: .seconds(1))
    }

    private func controllers(_ controller: UIViewController) -> [UIViewController] {
        [controller] + controller.children.flatMap { controllers($0) }
    }

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

    /// Sample on both sides of the old padding boundary, away from the grabber and controls.
    /// Frame assertions alone cannot detect a contrasting strip behind the grabber.
    private func assertContinuousHeader(_ window: UIWindow, presented: UIViewController, name: String,
                                        file: StaticString = #filePath, line: UInt = #line) throws {
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let cgImage = try XCTUnwrap(image.cgImage)
        var pixels = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: cgImage.width, height: cgImage.height,
                                                bitsPerComponent: 8, bytesPerRow: cgImage.width * 4,
                                                space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        }
        for fraction in [CGFloat(0.3), 0.7] {
            let above = presented.view.convert(CGPoint(x: presented.view.bounds.width * fraction, y: 3), to: window)
            let below = presented.view.convert(CGPoint(x: presented.view.bounds.width * fraction, y: 13), to: window)
            let indices = [above, below].map {
                (Int($0.y * image.scale) * cgImage.width + Int($0.x * image.scale)) * 4
            }
            for channel in 0..<3 {
                XCTAssertEqual(Double(pixels[indices[0] + channel]), Double(pixels[indices[1] + channel]),
                               accuracy: 3, "\(name): contrasting strip at the sheet's top edge", file: file, line: line)
            }
        }
    }

    private func attach(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
