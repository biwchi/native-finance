import SwiftUI
import UIKit

/// Shared sheet appearance. Present through `appSheet` so styling stays at the presentation boundary.
struct AppSheet<Content: View>: View {
    var layout: AppSheetLayout = .navigation
    var background: Color = AppColor.sheetBackground
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background {
                if topInset > 0 { TopSafeAreaInset(amount: topInset) }
            }
            .presentationCornerRadius(AppRadius.sheet)
            .presentationBackground(background)
    }

    /// Change the hosting controller's safe area so navigation backgrounds extend
    /// through the inset. SwiftUI padding leaves an uncovered strip above them.
    private struct TopSafeAreaInset: UIViewControllerRepresentable {
        let amount: CGFloat

        func makeUIViewController(context: Context) -> Controller { Controller(amount: amount) }
        func updateUIViewController(_ controller: Controller, context: Context) { controller.apply() }
        static func dismantleUIViewController(_ controller: Controller, coordinator: ()) { controller.restore() }

        final class Controller: UIViewController {
            let amount: CGFloat
            weak var owner: UIViewController?
            var originalTop: CGFloat = 0

            init(amount: CGFloat) {
                self.amount = amount
                super.init(nibName: nil, bundle: nil)
            }
            required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
            override func loadView() {
                view = UIView()
                view.backgroundColor = .clear
                view.isUserInteractionEnabled = false
            }
            override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); apply() }
            override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); apply() }

            func apply() {
                guard var target = parent else { return }
                while let parent = target.parent { target = parent }
                guard target.presentingViewController != nil, target.sheetPresentationController != nil else { return }
                if owner !== target {
                    restore()
                    owner = target
                    originalTop = target.additionalSafeAreaInsets.top
                }
                let top = originalTop + amount
                if target.additionalSafeAreaInsets.top != top {
                    target.additionalSafeAreaInsets.top = top
                }
            }

            func restore() {
                if let owner, owner.additionalSafeAreaInsets.top == originalTop + amount {
                    owner.additionalSafeAreaInsets.top = originalTop
                }
                owner = nil
            }
        }
    }

    private var topInset: CGFloat {
        if #available(iOS 26.0, *) { return 0 }
        return layout == .navigation ? AppSpacing.legacySheetToolbarTopInset : 0
    }
}

extension View {
    /// Keeps SwiftUI's binding, dismissal, environment, and sheet adaptation behavior.
    func appSheet<Content: View>(
        isPresented: Binding<Bool>,
        layout: AppSheetLayout = .navigation,
        background: Color = AppColor.sheetBackground,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            AppSheet(layout: layout, background: background, content: content)
        }
    }

    func appSheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        layout: AppSheetLayout = .navigation,
        background: Color = AppColor.sheetBackground,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        sheet(item: item, onDismiss: onDismiss) { item in
            AppSheet(layout: layout, background: background) { content(item) }
        }
    }
}
