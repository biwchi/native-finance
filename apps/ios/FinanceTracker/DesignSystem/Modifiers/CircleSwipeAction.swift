import SwiftUI

struct CircleSwipeAction {
    let title: String
    let icon: String
    var tint: Color = AppColor.destructive
    var isEnabled = true
    var deletion: (() async -> Bool)? = nil
    let action: () -> Void

    /// Return false if deletion fails so the row can slide back into place.
    static func delete(_ title: String = "Delete", action: @escaping () async -> Bool) -> Self {
        Self(title: title, icon: "trash", deletion: action, action: {})
    }
}
