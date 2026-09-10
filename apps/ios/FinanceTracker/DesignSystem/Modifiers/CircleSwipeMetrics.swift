import SwiftUI

struct CircleSwipeMetrics {
    static let actionWidth: CGFloat = 64

    static func fullSwipeThreshold(width: CGFloat, actionCount: Int) -> CGFloat {
        min(width * 0.85, max(width * 0.65, CGFloat(actionCount) * actionWidth + 44))
    }

    static func accepts(velocity: CGPoint, isOpen: Bool) -> Bool {
        abs(velocity.x) > abs(velocity.y) * 1.5 && (isOpen || velocity.x < 0)
    }

    static func destination(reveal: CGFloat, velocity: CGFloat, width: CGFloat,
                            actionCount: Int, canCommit: Bool) -> Destination {
        if canCommit && reveal >= fullSwipeThreshold(width: width, actionCount: actionCount) {
            return .commit
        }
        let railWidth = CGFloat(actionCount) * actionWidth
        return reveal - velocity * 0.15 > railWidth * 0.5 ? .open : .closed
    }

    enum Destination { case closed, open, commit }
}
