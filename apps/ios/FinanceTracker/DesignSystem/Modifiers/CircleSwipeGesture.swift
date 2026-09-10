import SwiftUI
import UIKit

/// A directional UIKit recognizer lets vertical drags go straight to List's scroll
/// recognizer, without a SwiftUI DragGesture swallowing scrolling on older systems.
struct CircleSwipeGesture: UIViewRepresentable {
    var isEnabled: Bool
    var revealedWidth: CGFloat
    var onBegin: () -> Void
    var onChange: (CGFloat, CGFloat) -> Void
    var onEnd: (CGFloat, CGFloat, Bool) -> Void
    var onClose: () -> Void

    func makeUIView(context: Context) -> ObserverView { ObserverView(configuration: self) }
    func updateUIView(_ view: ObserverView, context: Context) {
        view.configuration = self
        view.pan.isEnabled = isEnabled
    }
    static func dismantleUIView(_ view: ObserverView, coordinator: ()) { view.detach() }

    final class ObserverView: UIView, UIGestureRecognizerDelegate {
        var configuration: CircleSwipeGesture
        private weak var host: UIView?
        private weak var scrollView: UIScrollView?
        lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(didPan))
        private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(didTap))

        init(configuration: CircleSwipeGesture) {
            self.configuration = configuration
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            pan.delegate = self
            pan.maximumNumberOfTouches = 1
            tap.delegate = self
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { detach() } else { attach() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            if host == nil, window != nil { attach() }
        }

        private func attach() {
            var ancestor = superview
            while let view = ancestor {
                if view is UICollectionViewCell || view is UITableViewCell {
                    if host !== view {
                        detach()
                        host = view
                        view.addGestureRecognizer(pan)
                        view.addGestureRecognizer(tap)
                        var parent = view.superview
                        while let current = parent {
                            if let scroll = current as? UIScrollView {
                                scrollView = scroll
                                scroll.panGestureRecognizer.addTarget(self, action: #selector(didScroll))
                                break
                            }
                            parent = current.superview
                        }
                    }
                    return
                }
                ancestor = view.superview
            }
        }

        func detach() {
            host?.removeGestureRecognizer(pan)
            host?.removeGestureRecognizer(tap)
            scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(didScroll))
            host = nil
            scrollView = nil
        }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard configuration.isEnabled else { return false }
            if gestureRecognizer === tap {
                // Tapping the exposed actions must reach their own buttons.
                return configuration.revealedWidth > 0
                    && tap.location(in: self).x < bounds.width - configuration.revealedWidth
            }
            return CircleSwipeMetrics.accepts(velocity: pan.velocity(in: host), isOpen: configuration.revealedWidth > 0)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            gestureRecognizer === pan && otherGestureRecognizer === scrollView?.panGestureRecognizer
        }

        @objc private func didPan() {
            let width = bounds.width
            switch pan.state {
            case .began:
                // Recognition starts after the touch has moved. Start from the current
                // displayed position instead of jumping by that recognition distance.
                pan.setTranslation(.zero, in: host)
                configuration.onBegin()
                configuration.onChange(pan.translation(in: host).x, width)
            case .changed: configuration.onChange(pan.translation(in: host).x, width)
            case .ended: configuration.onEnd(pan.velocity(in: host).x, width, false)
            case .cancelled, .failed: configuration.onEnd(0, width, true)
            default: break
            }
        }
        @objc private func didTap() { configuration.onClose() }
        @objc private func didScroll() {
            if scrollView?.panGestureRecognizer.state == .began { configuration.onClose() }
        }
    }
}
