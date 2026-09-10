import SwiftUI

@resultBuilder
enum CircleSwipeActionBuilder {
    static func buildExpression(_ action: CircleSwipeAction) -> [CircleSwipeAction] { [action] }
    static func buildBlock(_ actions: [CircleSwipeAction]...) -> [CircleSwipeAction] { actions.flatMap { $0 } }
    static func buildOptional(_ actions: [CircleSwipeAction]?) -> [CircleSwipeAction] { actions ?? [] }
}
