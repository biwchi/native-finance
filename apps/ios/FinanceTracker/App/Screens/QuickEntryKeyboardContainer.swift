import SwiftUI
import UIKit

/// Keep the entire presentation at its resting size while UIKit moves the
/// accessory. Ignoring the keyboard only on the accessory's sibling overlay
/// still lets the background list and its safe-area inset resize underneath it.
struct QuickEntryPresentation<Background: View, Composer: View>: View {
    @Binding var isPresented: Bool
    var isDismissing: Bool
    var onBackgroundTap: () -> Void
    @ViewBuilder var background: () -> Background
    @ViewBuilder var composer: () -> Composer

    var body: some View {
        ZStack {
            background()

            if isPresented {
                QuickEntryKeyboardContainer(
                    isDismissing: isDismissing,
                    onBackgroundTap: onBackgroundTap,
                    onDismiss: { isPresented = false },
                    content: composer
                )
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .transition(.identity)
            }
        }
        // Retain this through native dismissal, including interactive drags.
        // Other screens keep normal keyboard avoidance after the composer closes.
        .ignoresSafeArea(isPresented ? .keyboard : [], edges: .bottom)
    }
}

/// The navigation page has its own hosting view. Exclude keyboard safe-area
/// updates there as well so fixed-height decorations cannot recenter its list.
struct QuickEntryBackground<Content: View>: UIViewControllerRepresentable {
    var isPresented: Bool
    @ViewBuilder var content: () -> Content

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller(rootView: rootView(in: context))
        controller.host.safeAreaRegions = isPresented ? .container : .all
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.host.safeAreaRegions = isPresented ? .container : .all
        controller.host.rootView = rootView(in: context)
    }

    private func rootView(in context: Context) -> AnyView {
        AnyView(content().environment(\.self, context.environment))
    }

    // SwiftUI can flatten a representable that returns a hosting controller
    // directly. A separate parent preserves the host's safe-area policy.
    final class Controller: UIViewController {
        let host: UIHostingController<AnyView>

        init(rootView: AnyView) {
            host = UIHostingController(rootView: rootView)
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            host.view.backgroundColor = .clear
            host.view.translatesAutoresizingMaskIntoConstraints = false
            addChild(host)
            view.addSubview(host.view)
            host.didMove(toParent: self)
            NSLayoutConstraint.activate([
                host.view.topAnchor.constraint(equalTo: view.topAnchor),
                host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
        }
    }
}

/// The composer lives in the native keyboard accessory so both share UIKit's
/// interactive placement and dismissal animation.
struct QuickEntryKeyboardContainer<Content: View>: UIViewControllerRepresentable {
    var isDismissing: Bool
    var onBackgroundTap: () -> Void
    var onDismiss: () -> Void
    @ViewBuilder var content: () -> Content

    func makeUIViewController(context: Context) -> Controller {
        Controller(content: AnyView(content().environment(\.colorScheme, context.environment.colorScheme)),
                   onBackgroundTap: onBackgroundTap, onDismiss: onDismiss)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.host.rootView = AnyView(content().environment(\.colorScheme, context.environment.colorScheme))
        controller.onBackgroundTap = onBackgroundTap
        controller.onDismiss = onDismiss
        if isDismissing, !controller.isFinishingDismissal {
            // Resigning first responder emits keyboard/layout notifications.
            // Let this SwiftUI update finish before UIKit starts that work.
            DispatchQueue.main.async { [weak controller] in
                controller?.requestDismissal()
            }
        }
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.tearDown()
    }

    final class Controller: UIViewController, UIKeyInput {
        let accessoryController: AccessoryController
        var host: ComposerHostingController { accessoryController.host }
        var accessory: UIScrollView { accessoryController.scrollView }
        let scrollView = UIScrollView()
        var onBackgroundTap: () -> Void
        var onDismiss: () -> Void
        private(set) var isFinishingDismissal = false
        private var hasCompletedDismissal = false
        private var hasShownKeyboard = false
        private var hasRequestedFocus = false
        private var dismissalPans: [UIPanGestureRecognizer] = []
        private var releasedDragAllowsDismissal: Bool?
        private let dismissalDistance: CGFloat = 90
        private var dismissalCompletion: DispatchWorkItem?

        override var canBecomeFirstResponder: Bool { !isFinishingDismissal && !hasRequestedFocus }
        override var inputAccessoryViewController: UIInputViewController? { accessoryController }
        var hasText: Bool { accessoryController.textInput?.hasText ?? false }

        // Present keyboard and composer together. Forward any input arriving
        // before the composer's text field takes over first responder.
        func insertText(_ text: String) { accessoryController.textInput?.insertText(text) }
        func deleteBackward() { accessoryController.textInput?.deleteBackward() }

        init(content: AnyView, onBackgroundTap: @escaping () -> Void, onDismiss: @escaping () -> Void) {
            accessoryController = AccessoryController(content: content)
            self.onBackgroundTap = onBackgroundTap
            self.onDismiss = onDismiss
            super.init(nibName: nil, bundle: nil)
            accessoryController.onAttached = { [weak self] in
                DispatchQueue.main.async {
                    guard let self, !self.isFinishingDismissal, !self.hasRequestedFocus else { return }
                    if let editor = self.accessoryController.textInput as? QuickEntryTextView.Editor {
                        editor.shouldResign = { [weak self] in self?.allowsEditorResignation ?? true }
                    }
                    self.hasRequestedFocus = true
                    self.accessoryController.textInput?.becomeFirstResponder()
                }
            }
            accessoryController.onDetached = { [weak self] in
                guard let self, self.isFinishingDismissal, !self.hasShownKeyboard else { return }
                self.scheduleDismissalCompletion()
            }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            scrollView.frame = view.bounds
            scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            scrollView.backgroundColor = .clear
            scrollView.alwaysBounceVertical = true
            scrollView.keyboardDismissMode = .interactiveWithAccessory
            scrollView.contentInsetAdjustmentBehavior = .never
            scrollView.showsVerticalScrollIndicator = false
            view.addSubview(scrollView)
            scrollView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(backgroundTapped)))
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow),
                name: UIResponder.keyboardWillShowNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidHide),
                name: UIResponder.keyboardDidHideNotification, object: nil)
            accessoryController.loadViewIfNeeded()
            observeDismissalPan(scrollView.panGestureRecognizer)
            // The scroll view must stay in the fixed app coordinate space.
            // Let its native pan receive touches from the accessory without
            // moving the scroll view itself into the keyboard. A scroll view
            // inside the moving accessory amplifies the drag on iOS 26.
            accessory.panGestureRecognizer.isEnabled = false
            accessory.addGestureRecognizer(scrollView.panGestureRecognizer)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !isFinishingDismissal else { completeDismissal(); return }
            becomeFirstResponder()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            scrollView.contentSize = scrollView.bounds.size
            accessoryController.prepare(width: view.bounds.width)
        }

        func observeDismissalPan(_ pan: UIPanGestureRecognizer) {
            guard !dismissalPans.contains(where: { $0 === pan }) else { return }
            dismissalPans.append(pan)
            pan.addTarget(self, action: #selector(dismissalPanChanged))
        }

        @objc func dismissalPanChanged(_ pan: UIPanGestureRecognizer) {
            switch pan.state {
            case .began: releasedDragAllowsDismissal = nil
            case .ended:
                releasedDragAllowsDismissal = pan.translation(in: view.window).y >= dismissalDistance
                if releasedDragAllowsDismissal == true {
                    requestDismissal()
                } else {
                    restoreKeyboardAfterDrag()
                }
            case .cancelled:
                releasedDragAllowsDismissal = false
                restoreKeyboardAfterDrag()
            default: break
            }
        }

        private func restoreKeyboardAfterDrag() {
            scrollView.keyboardDismissMode = .none
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isFinishingDismissal,
                      self.accessoryController.textInput?.isFirstResponder == true else { return }
                // Denying resignation alone leaves UIKit's interactive placement
                // offscreen. Reload the same live input to settle it back using
                // the keyboard animation, without a focus handoff or draft reset.
                self.accessoryController.textInput?.reloadInputViews()
                self.scrollView.keyboardDismissMode = .interactiveWithAccessory
            }
        }

        private var allowsEditorResignation: Bool {
            if isFinishingDismissal { return true }
            // This gate only controls commitment. UIKit still tracks the finger
            // throughout the drag, even before the release distance is reached.
            if dismissalPans.contains(where: { $0.state == .began || $0.state == .changed }) { return false }
            if let pan = dismissalPans.first(where: { $0.state == .ended }) {
                return pan.translation(in: view.window).y >= dismissalDistance
            }
            return releasedDragAllowsDismissal ?? true
        }

        func requestDismissal() {
            guard !isFinishingDismissal else { return }
            isFinishingDismissal = true
            accessoryController.textInput?.resignFirstResponder()
            resignFirstResponder()
            // Accessory-only hardware keyboard presentations may emit no
            // software keyboard notifications. Never run a second animation.
            if !hasShownKeyboard {
                scheduleDismissalCompletion()
            }
        }

        @objc private func keyboardWillShow() {
            hasShownKeyboard = true
        }

        @objc private func keyboardDidHide() {
            // UIKit can finish hiding the bootstrap responder's keyboard after
            // the editor has already become first responder in the accessory.
            guard hasShownKeyboard, accessoryController.textInput?.isFirstResponder != true else { return }
            scheduleDismissalCompletion()
        }

        private func scheduleDismissalCompletion() {
            guard !hasCompletedDismissal else { return }
            dismissalCompletion?.cancel()
            // For a software keyboard, only keyboardDidHide reaches here.
            // iOS 26 can detach the accessory before its dismissal finishes;
            // neither detachment nor the advertised duration means it is gone.
            // Leave the notification's layout pass before restoring Home.
            let work = DispatchWorkItem { [weak self] in self?.completeDismissal() }
            dismissalCompletion = work
            DispatchQueue.main.async(execute: work)
        }

        private func completeDismissal() {
            guard !hasCompletedDismissal else { return }
            hasCompletedDismissal = true
            isFinishingDismissal = true
            onDismiss()
        }

        @objc private func backgroundTapped() {
            // Use the same native entry point as a completed drag. Publishing
            // SwiftUI state first starts keyboard dismissal during a view update.
            requestDismissal()
            onBackgroundTap()
        }
        override func accessibilityPerformEscape() -> Bool {
            backgroundTapped()
            return true
        }

        func tearDown() {
            NotificationCenter.default.removeObserver(self)
            hasCompletedDismissal = true
            isFinishingDismissal = true
            dismissalCompletion?.cancel()
            accessoryController.onAttached = nil
            accessoryController.onDetached = nil
            accessoryController.textInput?.resignFirstResponder()
            resignFirstResponder()
        }

        deinit { NotificationCenter.default.removeObserver(self) }
    }

    /// A real input view controller provides the containment UIKit requires when
    /// the keyboard reparents its accessory, including during fast swipes.
    final class AccessoryController: UIInputViewController {
        let host: ComposerHostingController
        let scrollView = UIScrollView()
        let sizingView = AccessoryInputView(frame: .zero, inputViewStyle: .default)
        var onAttached: (() -> Void)?
        var onDetached: (() -> Void)?

        var textInput: (UIView & UIKeyInput)? { findTextInput(in: host.view) }

        init(content: AnyView) {
            host = ComposerHostingController(rootView: content)
            super.init(nibName: nil, bundle: nil)
            host.composerAccessoryController = self
            host.onLayout = { [weak self] in self?.updateHeight() }
            sizingView.onAttached = { [weak self] in self?.onAttached?() }
            sizingView.onDetached = { [weak self] in self?.onDetached?() }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func loadView() { inputView = sizingView }

        override func viewDidLoad() {
            super.viewDidLoad()
            sizingView.backgroundColor = .clear
            sizingView.allowsSelfSizing = true
            scrollView.backgroundColor = .clear
            scrollView.frame = view.bounds
            scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            scrollView.alwaysBounceVertical = true
            scrollView.keyboardDismissMode = .none
            scrollView.contentInsetAdjustmentBehavior = .never
            scrollView.showsVerticalScrollIndicator = false
            scrollView.showsHorizontalScrollIndicator = false
            scrollView.delaysContentTouches = false
            view.addSubview(scrollView)

            host.safeAreaRegions = []
            host.sizingOptions = [.intrinsicContentSize]
            host.view.backgroundColor = .clear
            host.view.translatesAutoresizingMaskIntoConstraints = false
            addChild(host)
            scrollView.addSubview(host.view)
            host.didMove(toParent: self)
            NSLayoutConstraint.activate([
                host.view.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor),
                host.view.topAnchor.constraint(equalTo: scrollView.frameLayoutGuide.topAnchor),
                host.view.bottomAnchor.constraint(equalTo: scrollView.frameLayoutGuide.bottomAnchor),
            ])
        }

        func prepare(width: CGFloat) {
            loadViewIfNeeded()
            if sizingView.bounds.width == 0 { sizingView.frame.size.width = width }
            updateHeight()
        }

        func updateHeight() {
            guard isViewLoaded, sizingView.bounds.width > 0 else { return }
            let height = ceil(host.sizeThatFits(in: CGSize(width: sizingView.bounds.width, height: .greatestFiniteMagnitude)).height)
            if abs(sizingView.contentHeight - height) > 0.5 {
                sizingView.contentHeight = height
                sizingView.frame.size.height = height
                preferredContentSize = CGSize(width: sizingView.bounds.width, height: height)
                sizingView.invalidateIntrinsicContentSize()
            }
            if let input = textInput as? UITextView, input.keyboardDismissMode != .none {
                input.keyboardDismissMode = .none
            }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            scrollView.contentSize = scrollView.bounds.size
            updateHeight()
        }

        private func findTextInput(in view: UIView) -> (UIView & UIKeyInput)? {
            if let input = view as? (UIView & UIKeyInput) { return input }
            return view.subviews.lazy.compactMap { self.findTextInput(in: $0) }.first
        }
    }

    final class AccessoryInputView: UIInputView {
        var contentHeight: CGFloat = 0
        var onAttached: (() -> Void)?
        var onDetached: (() -> Void)?
        private var hasBeenAttached = false

        override var intrinsicContentSize: CGSize {
            CGSize(width: UIView.noIntrinsicMetric, height: contentHeight)
        }

        override func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize {
            CGSize(width: targetSize.width, height: contentHeight)
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                hasBeenAttached = true
                onAttached?()
            } else if hasBeenAttached {
                onDetached?()
            }
        }
    }

    final class ComposerHostingController: UIHostingController<AnyView> {
        var onLayout: (() -> Void)?
        weak var composerAccessoryController: UIInputViewController?
        override var inputAccessoryViewController: UIInputViewController? { composerAccessoryController }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            onLayout?()
        }
    }
}
