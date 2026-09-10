import SwiftUI
import UIKit

struct ScrollEdgeBlurView: UIViewRepresentable {
    let transitionHeight: CGFloat
    var edge: VerticalEdge = .top

    func makeUIView(context: Context) -> BlurView {
        BlurView(effect: nil)
    }

    func updateUIView(_ view: BlurView, context: Context) {
        view.transitionHeight = transitionHeight
        view.edge = edge
        view.setNeedsLayout()
    }

    static func dismantleUIView(_ view: BlurView, coordinator: ()) {
        view.stopBlur()
    }

    final class BlurView: UIVisualEffectView {
        var transitionHeight: CGFloat = 56
        var edge: VerticalEdge = .top
        private var animator: UIViewPropertyAnimator?
        private var refreshTask: Task<Void, Never>?
        private let fadeMask = UIView()
        private let gradient = CAGradientLayer()
        private var maskSize = CGSize.zero
        private var maskedTransitionHeight: CGFloat = 0
        private var maskedEdge: VerticalEdge?

        override init(effect: UIVisualEffect?) {
            super.init(effect: effect)
            isUserInteractionEnabled = false
            fadeMask.layer.addSublayer(gradient)
            gradient.colors = [1.0, 1, 0.3, 0.08, 0, 0].map {
                UIColor.black.withAlphaComponent($0).cgColor
            }
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
                (view: BlurView, _: UITraitCollection) in
                view.scheduleBlurRefresh()
            }
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            stopBlur()
            maskSize = .zero
            if window != nil { setNeedsLayout() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.height > 0,
                  maskSize != bounds.size || maskedTransitionHeight != transitionHeight
                    || maskedEdge != edge else { return }
            maskSize = bounds.size
            maskedTransitionHeight = transitionHeight
            maskedEdge = edge
            let start = max(0, bounds.height - transitionHeight)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fadeMask.frame = bounds
            gradient.frame = fadeMask.bounds
            gradient.startPoint = CGPoint(x: 0.5, y: edge == .top ? 0 : 1)
            gradient.endPoint = CGPoint(x: 0.5, y: edge == .top ? 1 : 0)
            gradient.locations = [0, start, start + transitionHeight * 0.5,
                                  start + transitionHeight * 0.7,
                                  start + transitionHeight * 0.85, bounds.height]
                .map { NSNumber(value: Double($0 / bounds.height)) }
            CATransaction.commit()
            // Reassigning a UIVisualEffectView mask rebuilds its effect. Only do
            // this after geometry or window attachment changes, then restore blur.
            mask = fadeMask
            scheduleBlurRefresh()
        }

        func stopBlur() {
            refreshTask?.cancel()
            refreshTask = nil
            animator?.stopAnimation(true)
            animator = nil
            effect = nil
        }

        private func scheduleBlurRefresh() {
            refreshTask?.cancel()
            // Leave the layout/tab-attachment transaction before creating the
            // paused effect; UIKit may otherwise finish it at full strength.
            refreshTask = Task { @MainActor [weak self] in
                guard !Task.isCancelled else { return }
                self?.configureBlur()
            }
        }

        private func configureBlur() {
            stopBlur()
            guard window != nil else { return }
            // Interpolate the effect itself: lowering view alpha would crossfade
            // sharp content with a full-strength blur and wash out fine detail.
            let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) { [weak self] in
                self?.effect = UIBlurEffect(style: .systemUltraThinMaterial)
            }
            animator.pausesOnCompletion = true
            animator.fractionComplete = 0.08
            self.animator = animator
        }
    }
}
