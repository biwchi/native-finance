import Foundation

enum GoalEditorDestination: Identifiable {
    case add
    case edit(SavingsGoal)
    var id: String {
        switch self {
        case .add: "add"
        case .edit(let goal): goal.id.uuidString
        }
    }
    var goal: SavingsGoal? { if case .edit(let goal) = self { goal } else { nil } }
}
