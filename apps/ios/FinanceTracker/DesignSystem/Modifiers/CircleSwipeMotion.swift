import SwiftUI
import UIKit

/// List row backgrounds live in a separate host and don't consistently inherit
/// SwiftUI animation transactions. Drive both hosts with the same displayed offset.
@MainActor
final class CircleSwipeMotion: ObservableObject {
    @Published private(set) var reveal: CGFloat = 0
    private(set) var isAnimating = false
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var start: CGFloat = 0
    private var target: CGFloat = 0
    private var initialVelocity: CGFloat = 0
    private var completion: (() -> Void)?

    @MainActor
    private final class FrameTarget: NSObject {
        weak var motion: CircleSwipeMotion?
        init(_ motion: CircleSwipeMotion) { self.motion = motion }
        @objc func tick(_ link: CADisplayLink) { motion?.tick(link) }
    }

    deinit { displayLink?.invalidate() }

    func beginDrag() {
        stop()
    }

    func drag(to value: CGFloat) {
        stop()
        display(max(0, value))
    }

    func settle(to value: CGFloat, velocity: CGFloat = 0, reduceMotion: Bool,
                completion: (() -> Void)? = nil) {
        stop()
        target = max(0, value)
        guard !reduceMotion, abs(target - reveal) > 0.25 else {
            display(target)
            completion?()
            return
        }
        start = reveal
        initialVelocity = min(2000, max(-2000, velocity))
        startTime = CACurrentMediaTime()
        self.completion = completion
        isAnimating = true
        let link = CADisplayLink(target: FrameTarget(self), selector: #selector(FrameTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func reset() {
        stop()
        display(0)
    }

    private func stop() {
        displayLink?.invalidate()
        displayLink = nil
        isAnimating = false
        completion = nil
    }

    private func display(_ value: CGFloat) {
        // Clear implicit offset animations without disabling a simultaneous,
        // explicitly keyed List deletion animation in an ancestor.
        withTransaction(Transaction(animation: nil)) { reveal = value }
    }

    private func tick(_ link: CADisplayLink) {
        // An analytic critically damped spring remains stable across 60/120 Hz
        // screens and dropped frames, and preserves the finger's release velocity.
        let elapsed = CGFloat(max(0, link.targetTimestamp - startTime))
        let frequency: CGFloat = 24
        let displacement = start - target
        let coefficient = initialVelocity + frequency * displacement
        let decay = exp(-frequency * elapsed)
        let offset = (displacement + coefficient * elapsed) * decay
        let velocity = (initialVelocity - frequency * coefficient * elapsed) * decay
        if (abs(offset) < 0.25 && abs(velocity) < 4) || elapsed > 0.75 {
            let finished = completion
            stop()
            display(target)
            finished?()
        } else {
            display(max(0, target + offset))
        }
    }
}
