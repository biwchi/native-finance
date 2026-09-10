import Foundation

struct AddTransactionPresentation: Identifiable {
    let id = UUID()
    let command: String?
    let accountID: UUID?
}
