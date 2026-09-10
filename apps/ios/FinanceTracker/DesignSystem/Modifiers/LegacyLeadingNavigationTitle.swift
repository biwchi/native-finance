import SwiftUI
import UIKit

/// Keeps the native large title and back button, aligning only the collapsed title on older iOS.
struct LegacyLeadingNavigationTitle: UIViewRepresentable {
    let title: String

    func makeUIView(context: Context) -> ObserverView { ObserverView() }

    func updateUIView(_ view: ObserverView, context: Context) {
        view.title = title
        view.scheduleUpdate()
    }

    static func dismantleUIView(_ view: ObserverView, coordinator: ()) { view.restoreTitle() }

    final class ObserverView: UIView {
        var title = ""
        private let leadingTitle = TitleView()
        private weak var item: UINavigationItem?
        private var originalTitleView: UIView?
        private var observation: NSKeyValueObservation?
        private var barObservation: NSKeyValueObservation?
        private var updateScheduled = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { restoreTitle() } else { scheduleUpdate() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            scheduleUpdate()
        }

        func scheduleUpdate() {
            guard !updateScheduled else { return }
            updateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.updateScheduled = false
                guard self.window != nil else { return }
                self.updateTitle()
            }
        }

        private func updateTitle() {
            var responder: UIResponder? = next
            while let current = responder {
                if var controller = current as? UIViewController {
                    while let parent = controller.parent, !(parent is UINavigationController) {
                        controller = parent
                    }
                    if let navigation = controller.navigationController {
                        let owner = controller.navigationItem
                        if item !== owner {
                            restoreTitle()
                            item = owner
                            originalTitleView = owner.titleView
                            observation = owner.observe(\.titleView) { [weak self] _, _ in
                                self?.scheduleUpdate()
                            }
                            leadingTitle.navigationBar = navigation.navigationBar
                            barObservation = navigation.navigationBar.observe(\.bounds) { [weak self] _, _ in
                                self?.leadingTitle.updateVisibility()
                            }
                        }
                        if leadingTitle.label.text != title {
                            leadingTitle.label.text = title
                            leadingTitle.invalidateIntrinsicContentSize()
                        }
                        if owner.titleView !== leadingTitle {
                            leadingTitle.frame.size = leadingTitle.intrinsicContentSize
                            owner.titleView = leadingTitle
                        }
                        leadingTitle.updateVisibility()
                        return
                    }
                }
                responder = current.next
            }
        }

        func restoreTitle() {
            observation = nil
            barObservation = nil
            leadingTitle.navigationBar = nil
            if item?.titleView === leadingTitle { item?.titleView = originalTitleView }
            item = nil
            originalTitleView = nil
        }
    }

    final class TitleView: UIView {
        let label = UILabel()
        weak var navigationBar: UINavigationBar?

        init() {
            super.init(frame: .zero)
            label.font = .preferredFont(forTextStyle: .headline)
            label.adjustsFontForContentSizeCategory = true
            label.textColor = .label
            label.lineBreakMode = .byTruncatingTail
            label.accessibilityTraits = .header
            label.accessibilityIdentifier = "legacyLeadingNavigationTitle"
            addSubview(label)
            setContentHuggingPriority(.defaultLow, for: .horizontal)
            setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override var intrinsicContentSize: CGSize {
            CGSize(width: UIView.layoutFittingExpandedSize.width, height: label.intrinsicContentSize.height)
        }

        override func sizeThatFits(_ size: CGSize) -> CGSize {
            CGSize(width: min(size.width, intrinsicContentSize.width), height: intrinsicContentSize.height)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            label.frame = bounds
            label.textAlignment = effectiveUserInterfaceLayoutDirection == .rightToLeft ? .right : .left
            updateVisibility()
        }

        func updateVisibility() {
            guard let navigationBar, window != nil else {
                label.isHidden = true
                return
            }
            // The large-title area expands below the inline row. Hide this label until
            // that area collapses, without assuming a fixed navigation-bar height.
            let titleFrame = convert(bounds, to: navigationBar)
            label.isHidden = titleFrame.midY < navigationBar.bounds.midY - 1
        }
    }
}

extension View {
    @ViewBuilder
    func legacyLeadingNavigationTitle(_ title: String) -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            background(LegacyLeadingNavigationTitle(title: title)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false))
        }
    }
}
