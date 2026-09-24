import SwiftUI
import UIKit
import ObjectiveC

/// Destination toolbars declare their back control before SwiftUI builds the
/// transition. UIKit only supplies the native pop gesture and ancestor menu.
@MainActor
enum LegacyNavigationAppearance {
    private static var coordinatorKey: UInt8 = 0

    static func needsUpdate(_ navigation: UINavigationController) -> Bool {
        guard #unavailable(iOS 26.0) else { return false }
        return objc_getAssociatedObject(navigation, &coordinatorKey) == nil
    }

    static func apply(to navigation: UINavigationController) {
        guard #unavailable(iOS 26.0) else { return }
        if let coordinator = objc_getAssociatedObject(navigation, &coordinatorKey) as? Coordinator {
            coordinator.install()
            return
        }
        let coordinator = Coordinator(navigation)
        objc_setAssociatedObject(navigation, &coordinatorKey, coordinator, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        coordinator.install()
    }

    // Do not forward optional callbacks to UIKit's original gesture delegate:
    // those callbacks retain restrictions tied to the hidden native back item.
    private final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var navigation: UINavigationController?
        private var observations: [NSKeyValueObservation] = []

        init(_ navigation: UINavigationController) { self.navigation = navigation }

        func install() {
            guard let gesture = navigation?.interactivePopGestureRecognizer else { return }
            if gesture.delegate !== self {
                gesture.delegate = self
            }
            // SwiftUI may reset the recognizer after hiding the native back item.
            if observations.isEmpty {
                observations = [
                    gesture.observe(\.delegate) { [weak self] _, _ in self?.install() },
                    gesture.observe(\.isEnabled) { [weak self] _, _ in self?.restoreEnabledState() }
                ]
            }
            restoreEnabledState()
        }

        private func restoreEnabledState() {
            guard let navigation, navigation.viewControllers.count > 1,
                  let gesture = navigation.interactivePopGestureRecognizer, !gesture.isEnabled else { return }
            gesture.isEnabled = true
        }

        // The native delegate also rejects the initial event when the native
        // back item is hidden. Overriding shouldBegin alone never receives a pan.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive event: UIEvent) -> Bool {
            canPop
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            canPop
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool { canPop }

        private var canPop: Bool {
            guard let navigation, navigation.viewControllers.count > 1,
                  navigation.transitionCoordinator == nil else { return false }
            if let button = Self.backButton(in: navigation.navigationBar) { return button.isEnabled }
            return false
        }

        private static func backButton(in view: UIView) -> BackButton? {
            if let button = view as? BackButton { return button }
            return view.subviews.lazy.compactMap { backButton(in: $0) }.first
        }
    }

    struct Destination: ViewModifier {
        @State private var isBackDisabled = false

        @ViewBuilder
        func body(content: Content) -> some View {
            if #available(iOS 26.0, *) {
                content
            } else {
                content
                    .navigationBarBackButtonHidden(true)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Control()
                                .frame(width: AppControlSize.minimumTapTarget, height: AppControlSize.minimumTapTarget)
                                .disabled(isBackDisabled)
                        }
                    }
                    .onPreferenceChange(BackDisabled.self) { isBackDisabled = $0 }
            }
        }
    }

    struct BackDisabled: PreferenceKey {
        static let defaultValue = false
        static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
    }

    private struct Control: UIViewRepresentable {
        @Environment(\.dismiss) private var dismiss
        @Environment(\.isEnabled) private var isEnabled

        func makeUIView(context: Context) -> BackButton { BackButton() }
        func updateUIView(_ button: BackButton, context: Context) {
            button.isEnabled = isEnabled
            button.backAction = { dismiss() }
        }
    }

    final class BackButton: UIButton {
        var backAction: (() -> Void)?
        private let surface = UIHostingController(rootView: BackSurface())

        init() {
            super.init(frame: CGRect(x: 0, y: 0, width: AppControlSize.minimumTapTarget, height: AppControlSize.minimumTapTarget))
            var configuration = UIButton.Configuration.plain()
            configuration.image = UIImage(systemName: "chevron.backward")
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
            configuration.baseForegroundColor = .label
            configuration.contentInsets = .zero
            self.configuration = configuration
            accessibilityLabel = String(localized: "Back")
            accessibilityIdentifier = "legacyNavigationBackButton"
            surface.view.backgroundColor = .clear
            surface.view.isUserInteractionEnabled = false
            surface.view.accessibilityElementsHidden = true
            insertSubview(surface.view, at: 0)
            addAction(UIAction { [weak self] _ in
                guard let self, self.isEnabled else { return }
                self.backAction?()
            }, for: .touchUpInside)
            menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] completion in
                completion(self?.ancestorActions() ?? [])
            }])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            var responder: UIResponder? = self
            while let current = responder {
                if let navigation = current as? UINavigationController {
                    LegacyNavigationAppearance.apply(to: navigation)
                    break
                }
                responder = current.next
            }
        }

        override var intrinsicContentSize: CGSize {
            CGSize(width: AppControlSize.minimumTapTarget, height: AppControlSize.minimumTapTarget)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            surface.view.frame = bounds
            sendSubviewToBack(surface.view)
        }

        override var isHighlighted: Bool {
            didSet { alpha = isHighlighted ? 0.55 : (isEnabled ? 1 : 0.35) }
        }

        override var isEnabled: Bool {
            didSet { alpha = isEnabled ? 1 : 0.35 }
        }

        func ancestorActions() -> [UIAction] {
            var responder: UIResponder? = self
            while let current = responder {
                if let navigation = current as? UINavigationController {
                    return navigation.viewControllers.dropLast().reversed().map { ancestor in
                        let title = ancestor.navigationItem.title.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Back")
                        return UIAction(title: title) { [weak navigation, weak ancestor] _ in
                            guard let navigation, let ancestor, navigation.transitionCoordinator == nil else { return }
                            navigation.popToViewController(ancestor, animated: true)
                        }
                    }
                }
                responder = current.next
            }
            return []
        }
    }

    private struct BackSurface: View {
        var body: some View {
            Color.clear.modifier(LegacyGlassSurface(shape: Circle()))
        }
    }
}

extension View {
    func legacyNavigationDestination() -> some View {
        modifier(LegacyNavigationAppearance.Destination())
    }

    @ViewBuilder
    func appBackNavigationDisabled(_ disabled: Bool) -> some View {
        if #available(iOS 26.0, *) {
            navigationBarBackButtonHidden(disabled)
        } else {
            preference(key: LegacyNavigationAppearance.BackDisabled.self, value: disabled)
        }
    }
}
