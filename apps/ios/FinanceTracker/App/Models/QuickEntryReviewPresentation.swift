import Foundation

struct QuickEntryReviewPresentation: Codable, Identifiable {
    enum Source: String, Codable {
        case photo
        case document
        case csv
    }

    var id = UUID()
    let prompt: String
    var drafts: [QuickEntryDraft]
    var source: Source? = nil
}
