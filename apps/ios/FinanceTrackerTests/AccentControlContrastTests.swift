import SwiftUI
import UIKit
import XCTest
@testable import FinanceTracker

@MainActor
final class AccentControlContrastTests: XCTestCase {
    func testSwitchTrackContrastsWithWhiteThumbAndNativeSurfaces() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for accessibilityContrast in [UIAccessibilityContrast.normal, .high] {
                let traits = UITraitCollection {
                    $0.userInterfaceStyle = style
                    $0.accessibilityContrast = accessibilityContrast
                }
                let track = UIColor(AppColor.switchTrack).resolvedColor(with: traits)
                for adjacentColor in [UIColor.white, .systemBackground, .secondarySystemGroupedBackground] {
                    XCTAssertGreaterThanOrEqual(
                        contrast(luminance(track), luminance(adjacentColor.resolvedColor(with: traits))), 3,
                        "Switch track must remain distinct from its thumb and surface in \(traits)."
                    )
                }
            }
        }
    }

    func testPaletteForegroundsContrastWithEveryFillInBothAppearances() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            for accessibilityContrast in [UIAccessibilityContrast.normal, .high] {
                let traits = UITraitCollection {
                    $0.userInterfaceStyle = style
                    $0.accessibilityContrast = accessibilityContrast
                }
                let pairs = CategoryColor.allCases.map { ($0.swiftUIColor, $0.selectionForegroundColor) }
                    + AccountIconColor.allCases.map { ($0.color, $0.foregroundColor) }
                    + [(AppColor.accent, AppColor.foreground(on: AppColor.accent))]
                for (fill, foreground) in pairs {
                    XCTAssertGreaterThanOrEqual(
                        contrast(luminance(UIColor(fill).resolvedColor(with: traits)),
                                 luminance(UIColor(foreground).resolvedColor(with: traits))), 4.5,
                        "Palette labels and checkmarks must contrast with their fill in \(traits)."
                    )
                }
            }
        }
    }

    func testDisabledCustomFilledLabelsRemainVisibleInBothAppearances() throws {
        for scheme in [ColorScheme.light, .dark] {
            try assertVisibleContent(
                AccentSelectionButton("MMMM", isSelected: true) {}.disabled(true),
                scheme: scheme, fillOpacity: 0.45, minimumContrast: 3
            )
            for appearance in PrimaryActionButton.Appearance.allCases {
                let button = PrimaryActionButton("MMMM", appearance: appearance) {}.disabled(true)
                try assertVisibleContent(button, scheme: scheme, fillColor: AppColor.disabledControlFill)
                let renderer = ImageRenderer(content: button.frame(width: 200, height: 64).environment(\.colorScheme, scheme))
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.cgImage)
                var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
                let context = try XCTUnwrap(CGContext(data: &pixels, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                for y in 24..<40 {
                    for x in 92..<108 {
                        XCTAssertEqual(pixels[(y * image.width + x) * 4 + 3], 255,
                            "Disabled primary buttons must stay opaque in \(scheme), \(appearance)")
                    }
                }
            }
        }
    }

    func testCircleSwipeIconsContrastWithTheirTranslucentFill() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            for color in [AppColor.destructive, Color.gray] {
                let ink = UIColor(AppColor.iconForeground(for: color)).resolvedColor(with: traits)
                let tint = UIColor(color).resolvedColor(with: traits)
                let surface = UIColor.secondarySystemGroupedBackground.resolvedColor(with: traits)
                let fill = blend(tint, over: surface, opacity: 0.14)
                XCTAssertGreaterThanOrEqual(contrast(luminance(ink), luminance(fill)), 3)
                var alpha: CGFloat = 0
                ink.getRed(nil, green: nil, blue: nil, alpha: &alpha)
                XCTAssertEqual(alpha, 1, "Only the circle fill should be translucent")
            }
        }
    }

    func testPaletteArtworkContrastsWithNativeAndTintedSurfaces() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let colors = CategoryColor.allCases.map(\.swiftUIColor)
                + AccountIconColor.allCases.map(\.color) + [AppColor.accent, AppColor.positive]
            for color in colors {
                let ink = UIColor(AppColor.iconForeground(for: color)).resolvedColor(with: traits)
                let tint = UIColor(color).resolvedColor(with: traits)
                for surface in [UIColor.systemBackground, .secondarySystemGroupedBackground,
                                .tertiarySystemGroupedBackground] {
                    let surface = surface.resolvedColor(with: traits)
                    for background in [surface, blend(tint, over: surface, opacity: 0.14),
                                       blend(UIColor.secondaryLabel.resolvedColor(with: traits),
                                             over: surface, opacity: 0.12)] {
                        XCTAssertGreaterThanOrEqual(contrast(luminance(ink), luminance(background)), 3)
                    }
                }
            }
        }
    }

    func testPaletteControlsRenderInBothAppearances() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let controls = VStack(spacing: 20) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                    ForEach(CategoryColor.allCases) { color in
                        VStack {
                            HStack(spacing: 4) {
                                AppIcon("check", size: 14)
                                    .foregroundStyle(color.selectionForegroundColor)
                                    .frame(width: 30, height: 30)
                                    .background(color.swiftUIColor, in: Circle())
                                AppIcon("tag", size: 14)
                                    .foregroundStyle(AppColor.iconForeground(for: color.swiftUIColor))
                                    .frame(width: 30, height: 30)
                                    .background(color.swiftUIColor.opacity(0.12), in: Circle())
                            }
                            Text(color.title).font(.caption2)
                        }
                    }
                }
                IconPicker(selection: .constant("cart"))
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColor.elevatedSurface)
            .preferredColorScheme(scheme)
            try await attachGlassSnapshot(controls, name: "Palette-controls-\(scheme)")
        }
    }

    func testNativeControlsRenderInBothAppearances() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let controls = Form {
                Section("Switches") {
                    Toggle("On", isOn: .constant(true))
                    Toggle("Off", isOn: .constant(false))
                    Toggle("Disabled on", isOn: .constant(true)).disabled(true)
                    Toggle("Disabled off", isOn: .constant(false)).disabled(true)
                }
                .toggleStyle(SwitchToggleStyle(tint: AppColor.switchTrack))
                Section("Selected date") {
                    DatePicker("Date", selection: .constant(Date(timeIntervalSince1970: 1_788_600_000)),
                               displayedComponents: [.date])
                        .datePickerStyle(.graphical)
                }
            }
            .tint(AppColor.accent)
            .preferredColorScheme(scheme)
            try await attachGlassSnapshot(controls, name: "Native-controls-\(scheme)")
        }
    }

    func testMetricIconsContrastAgainstTheirBadgesInBothAppearances() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            for (ink, fill) in [(AppColor.tealIcon, AppColor.tealIconBackground),
                                (AppColor.orangeIcon, AppColor.orangeIconBackground),
                                (AppColor.blueIcon, AppColor.blueIconBackground)] {
                XCTAssertGreaterThanOrEqual(
                    contrast(luminance(UIColor(ink).resolvedColor(with: traits)),
                             luminance(UIColor(fill).resolvedColor(with: traits))), 3
                )
            }
        }
    }

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

    func testSummaryStatusTextContrastInBothAppearances() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            for token in [AppColor.positiveText, AppColor.destructiveText, AppColor.warningText] {
                let foreground = UIColor(token).resolvedColor(with: traits)
                let surface = UIColor.secondarySystemGroupedBackground.resolvedColor(with: traits)
                XCTAssertGreaterThanOrEqual(contrast(luminance(foreground), luminance(surface)), 4.5)
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
                Group {
                    HStack {
                        PrimaryIconButton(
                            "Glass Add",
                            iconName: "plus",
                            iconSize: 26,
                            appearance: .glass
                        ) {}
                        PrimaryIconButton(
                            "Disabled Glass Add",
                            iconName: "plus",
                            iconSize: 26,
                            appearance: .glass
                        ) {}
                        .disabled(true)
                    }
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

    func testTransactionGlassControlsRenderInBothAppearances() async throws {
        let account = Account(
            id: UUID(), name: "Main account", currency: "USD",
            icon: "credit-card", iconColor: .blue, createdAt: "", updatedAt: ""
        )
        for scheme in [ColorScheme.light, .dark] {
            let controls = VStack(spacing: 20) {
                ForEach(QuickTransactionMode.allCases) { mode in
                    TransactionModeSelector(modes: QuickTransactionMode.allCases, selection: .constant(mode))
                }
                TransactionModeSelector(modes: QuickTransactionMode.allCases, selection: .constant(.expense))
                    .disabled(true)
                TransactionMetadataBar(
                    accounts: [account], selectedAccountID: account.id,
                    accountBalance: "$1,240.00",
                    date: .constant(Date(timeIntervalSince1970: 1_788_600_000)),
                    hasExtraDetails: true, onSelectAccount: { _ in }
                )
                PrimaryActionButton("Add transaction", appearance: .glass) {}
                    .controlSize(.large)
                PrimaryActionButton("Disabled", appearance: .glass) {}
                    .controlSize(.large)
                    .disabled(true)
                PrimaryActionButton("Saving…", isLoading: true, appearance: .glass) {}
                    .controlSize(.large)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColor.groupedBackground)
            .preferredColorScheme(scheme)
            try await attachGlassSnapshot(
                controls,
                name: "Transaction-glass-\(scheme)"
            )
        }
    }

    func testTransactionTypeSegmentsMatchToolbarHeight() async throws {
        let modes: [QuickTransactionMode] = [.income, .expense]
        for scheme in [ColorScheme.light, .dark] {
            var previousWidth: CGFloat?
            for mode in modes {
                let control = TransactionModeSelector(modes: modes, selection: .constant(mode))
                    .environment(\.dynamicTypeSize, .large)
                    .preferredColorScheme(scheme)
                let controller = UIHostingController(rootView: control)
                let size = controller.sizeThatFits(in: CGSize(width: 320, height: 100))
                XCTAssertEqual(size.height, AppControlSize.minimumTapTarget, accuracy: 0.5)
                if let previousWidth {
                    XCTAssertEqual(size.width, previousWidth, accuracy: 0.5, "Changing type must not resize the toolbar")
                }
                previousWidth = size.width
            }
            let controls = VStack(spacing: 20) {
                ForEach(modes) { mode in
                    HStack(spacing: AppSpacing.medium) {
                        AppIcon("xmark", size: 18)
                            .frame(width: AppControlSize.minimumTapTarget, height: AppControlSize.minimumTapTarget)
                            .modifier(TransactionGlassSurface(shape: Circle(), isToolbarControl: true))
                        TransactionModeSelector(modes: modes, selection: .constant(mode))
                    }
                }
                TransactionModeSelector(modes: modes, selection: .constant(.expense))
                    .disabled(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColor.groupedBackground)
            .preferredColorScheme(scheme)
            try await attachGlassSnapshot(controls, name: "Transaction-type-capsules-\(scheme)")
        }
    }

    func testTransactionGlassSelectorAtAccessibilitySize() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let controls = TransactionModeSelector(modes: QuickTransactionMode.allCases, selection: .constant(.expense))
                .environment(\.dynamicTypeSize, .accessibility3)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColor.groupedBackground)
                .preferredColorScheme(scheme)
            try await attachGlassSnapshot(controls, name: "Transaction-glass-large-text-\(scheme)")
        }
    }

    func testCategoryTypeToolbarInBothAppearances() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let content = AppColor.groupedBackground
                .appSheet(isPresented: .constant(true)) {
                    CategoryEditorView(editor: CategoryEditor(category: nil, kind: .income))
                        .environmentObject(TransactionStore.preview(transactions: []))
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
                .preferredColorScheme(scheme)
            try await attachGlassSnapshot(content, name: "Category-type-toolbar-\(scheme)", fullScreen: true)
        }
    }

    private final class TypeSelectionFixture: ObservableObject {
        @Published var mode = QuickTransactionMode.income
    }

    private struct TypeSelectionPreview: View {
        @ObservedObject var fixture: TypeSelectionFixture
        var animatesParent = false

        var body: some View {
            TransactionModeSelector(modes: QuickTransactionMode.allCases, selection: $fixture.mode)
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColor.groupedBackground)
                .ignoresSafeArea()
                .animation(animatesParent ? .easeInOut(duration: 0.6) : nil, value: fixture.mode)
        }
    }

    private final class TypeFrameRecorder: NSObject {
        let window: UIWindow
        var frames: [(milliseconds: Int, data: Data)] = []
        private var displayLink: CADisplayLink?
        private var startedAt = 0.0

        init(window: UIWindow) { self.window = window }

        func start() {
            frames = []
            startedAt = CACurrentMediaTime()
            let link = CADisplayLink(target: self, selector: #selector(captureFrame))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func stop() {
            displayLink?.invalidate()
            displayLink = nil
        }

        @objc private func captureFrame() {
            let milliseconds = Int((CACurrentMediaTime() - startedAt) * 1_000)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let data = autoreleasepool {
                UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
                    XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: false))
                }.pngData()!
            }
            frames.append((milliseconds, data))
        }
    }

    func testTransactionTypeTransitionFrames() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for scheme in [ColorScheme.light, .dark] {
            for (animationsDisabled, animatesParent) in [(false, false), (true, false), (false, true)] {
                let fixture = TypeSelectionFixture()
                let content = TypeSelectionPreview(fixture: fixture, animatesParent: animatesParent)
                    .transaction { $0.disablesAnimations = animationsDisabled }
                    .preferredColorScheme(scheme)
                let controller = UIHostingController(rootView: content)
                let window = UIWindow(windowScene: scene)
                window.frame = CGRect(x: 0, y: 0, width: 390, height: 100)
                window.rootViewController = controller
                window.makeKeyAndVisible()
                defer { window.isHidden = true }
                controller.view.frame = window.bounds
                try await Task.sleep(for: .milliseconds(250))
                let recorder = TypeFrameRecorder(window: window)
                defer { recorder.stop() }

                func assertSettled(_ name: String, after milliseconds: Int = 250) throws {
                    let settled = try XCTUnwrap(recorder.frames.first { $0.milliseconds >= milliseconds })
                    let last = try XCTUnwrap(recorder.frames.last)
                    let early = try XCTUnwrap(UIImage(data: settled.data)?.cgImage)
                    let final = try XCTUnwrap(UIImage(data: last.data)?.cgImage)
                    func pixels(_ image: CGImage) -> [UInt8] {
                        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
                        bytes.withUnsafeMutableBytes { buffer in
                            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                                    space: CGColorSpaceCreateDeviceRGB(),
                                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                        }
                        return bytes
                    }
                    let lhs = pixels(early)
                    let rhs = pixels(final)
                    let changed = stride(from: 0, to: lhs.count, by: 4).filter { offset in
                        (0..<3).contains { abs(Int(lhs[offset + $0]) - Int(rhs[offset + $0])) > 12 }
                    }.count
                    XCTAssertLessThan(Double(changed) / Double(early.width * early.height), 0.001,
                                      "\(name): pixels still changing after \(settled.milliseconds) ms with parent animation=\(animatesParent)")
                }

                func attachFrames(_ name: String) {
                    XCTAssertGreaterThan(recorder.frames.count, 5)
                    for (index, frame) in recorder.frames.enumerated() {
                        let attachment = XCTAttachment(data: frame.data, uniformTypeIdentifier: "public.png")
                        attachment.name = "Type-motion-\(scheme)-disabled-\(animationsDisabled)-parent-\(animatesParent)-\(name)-frame-\(index)-\(frame.milliseconds)ms"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                    }
                }
                // Adjacent transitions in both directions and jumps across the selector.
                for mode in [QuickTransactionMode.expense, .transfer, .debt, .transfer, .expense, .income, .debt, .income] {
                    let origin = fixture.mode
                    recorder.start()
                    fixture.mode = mode
                    try await Task.sleep(for: .milliseconds(600))
                    recorder.stop()
                    attachFrames("\(origin.rawValue)-to-\(mode.rawValue)")
                    try assertSettled("\(origin.rawValue)-to-\(mode.rawValue)")
                }
                recorder.start()
                for mode in [QuickTransactionMode.debt, .expense, .transfer, .income] {
                    fixture.mode = mode
                    try await Task.sleep(for: .milliseconds(40))
                }
                try await Task.sleep(for: .milliseconds(600))
                recorder.stop()
                attachFrames("rapid-switch-income")
                try assertSettled("rapid-switch-income", after: 410)
            }
        }
    }

    func testTransactionGlassSheetInBothAppearances() async throws {
        let accounts = ["Main", "Savings"].map { name in
            Account(id: UUID(), name: name, currency: "USD",
                    icon: "credit-card", iconColor: .blue, createdAt: "", updatedAt: "")
        }
        let now = Date.now
        let categories = [
            ("Food & Drink", "cutlery", CategoryColor.orange),
            ("Groceries", "cart", CategoryColor.green),
            ("Transport", "car", CategoryColor.blue),
        ].enumerated().map { index, item in
            TransactionCategory(
                id: UUID(), systemKey: nil, name: item.0, kind: .expense,
                icon: item.1, color: item.2, isSystem: false, examples: nil,
                sortOrder: index, createdAt: now, updatedAt: now
            )
        }
        let transactions = categories.map { category in
            FinanceTransaction(
                id: UUID(), accountId: accounts[0].id, kind: .expense,
                amount: "24.50", currency: "USD", category: category, note: nil,
                occurredAt: now, createdAt: now, updatedAt: now
            )
        }
        for scheme in [ColorScheme.light, .dark] {
            let content = Color(uiColor: .systemGroupedBackground)
                .appSheet(isPresented: .constant(true)) {
                    AddTransactionView()
                        .environmentObject(AccountStore.preview(accounts: accounts, selectedAccountID: accounts[0].id))
                        .environmentObject(TransactionStore.preview(transactions: transactions))
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
                .preferredColorScheme(scheme)
            try await attachGlassSnapshot(content, name: "Transaction-glass-sheet-\(scheme)", fullScreen: true)
        }
    }

    private func attachGlassSnapshot<Content: View>(
        _ content: Content,
        name: String,
        fullScreen: Bool = false
    ) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let controller = UIHostingController(rootView: content)
        let window = UIWindow(windowScene: scene)
        window.frame = fullScreen ? scene.coordinateSpace.bounds : CGRect(x: 0, y: 0, width: 390, height: 760)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.frame = window.bounds
        try await Task.sleep(for: .milliseconds(750))
        controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertVisibleContent<Content: View>(
        _ content: Content,
        scheme: ColorScheme,
        sampleSize: Int = 24,
        fillOpacity: Double = 1,
        fillColor: Color = AppColor.accent,
        minimumContrast: Double = 4.5,
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
        let fill = UIColor(fillColor).resolvedColor(with: traits)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        fill.getRed(&red, green: &green, blue: &blue, alpha: nil)
        let surface = scheme == .dark ? 0.0 : 1.0
        let fillLuminance = luminance(
            red: Double(red) * fillOpacity + surface * (1 - fillOpacity),
            green: Double(green) * fillOpacity + surface * (1 - fillOpacity),
            blue: Double(blue) * fillOpacity + surface * (1 - fillOpacity)
        )
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
                if ratio >= minimumContrast { contrastingPixels += 1 }
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

    private func blend(_ foreground: UIColor, over background: UIColor, opacity: Double) -> UIColor {
        func components(_ color: UIColor) -> [CGFloat] {
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: nil)
            return [red, green, blue]
        }
        let rgb = zip(components(foreground), components(background)).map {
            $0 * opacity + $1 * (1 - opacity)
        }
        return UIColor(red: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
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
