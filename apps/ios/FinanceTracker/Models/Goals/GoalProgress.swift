import Foundation

struct GoalProgress: Equatable {
    let balance: Decimal
    let target: Decimal
    var remaining: Decimal { max(0, target - balance) }
    var isComplete: Bool { target > 0 && balance >= target }
    var fraction: Double {
        guard target > 0 else { return 0 }
        return min(1, max(0, NSDecimalNumber(decimal: balance / target).doubleValue))
    }
}
