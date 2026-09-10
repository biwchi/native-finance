import Foundation

struct QuickEntryReviewPresentation: Codable, Identifiable {
    var id = UUID()
    let prompt: String
    var drafts: [QuickEntryDraft]
    let unparsedText: [String]
}
