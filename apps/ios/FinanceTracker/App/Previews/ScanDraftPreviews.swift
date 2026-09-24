#if DEBUG
import SwiftUI
import UIKit

// Run a preview, then use Xcode's Environment Overrides to toggle Reduce Motion
// or try additional Dynamic Type sizes without creating a real scan.

@MainActor
private struct ScanDraftPillPreview: View {
    @StateObject private var store: ScanDraftStore

    init(items: [ScanDraftItem]) {
        _store = StateObject(wrappedValue: ScanDraftStore(previewItems: items))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            AppColor.background.ignoresSafeArea()
            ScanDraftActivityPill(
                onReview: { _ in },
                onOpenDrafts: {},
                onReplace: { _ in },
                onManualEntry: { _ in }
            )
                .environmentObject(store)
                .padding(.bottom, AppSpacing.large)
        }
        .frame(width: 390, height: 180)
    }
}

@MainActor
private struct ScanDraftSheetPreview: View {
    @StateObject private var store = ScanDraftStore(previewItems: ScanDraftPreviewData.allStates)

    var body: some View {
        ScanDraftsView(onReview: { _ in }, onReplace: { _ in }, onManualEntry: { _ in })
            .environmentObject(store)
    }
}

private enum ScanDraftPreviewData {
    static let accountID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let date = Date(timeIntervalSince1970: 1_779_105_600)

    static let preparing = item(
        id: "10000000-0000-0000-0000-000000000001",
        state: .preparing,
        source: .camera,
        displayName: "Scanned receipt",
        thumbnailData: thumbnailData
    )
    static let queued = item(
        id: "10000000-0000-0000-0000-000000000002",
        state: .queued,
        source: .document,
        displayName: "September statement.pdf"
    )
    static let running = item(
        id: "10000000-0000-0000-0000-000000000003",
        state: .running,
        source: .photoLibrary,
        displayName: "Receipt photo",
        thumbnailData: thumbnailData
    )
    static let ready = item(
        id: "10000000-0000-0000-0000-000000000004",
        state: .ready,
        source: .camera,
        displayName: "Cafe receipt",
        review: review,
        thumbnailData: thumbnailData
    )
    static let emptyResult = item(
        id: "10000000-0000-0000-0000-000000000005",
        state: .failed,
        source: .camera,
        displayName: "Blurry receipt",
        failure: .init(
            code: .emptyExtraction,
            message: "No purchases could be read. Try a clearer photo with a visible total."
        ),
        thumbnailData: thumbnailData
    )
    static let connectionFailure = item(
        id: "10000000-0000-0000-0000-000000000006",
        state: .failed,
        source: .document,
        displayName: "Card statement.csv",
        failure: .init(code: .connection, message: "Check your connection and try again.")
    )
    static let interrupted = item(
        id: "10000000-0000-0000-0000-000000000007",
        state: .interrupted,
        source: .photoLibrary,
        displayName: "Receipt photo",
        failure: .init(code: .generic, message: "This draft was interrupted. Try it again.")
    )

    static let allStates = [preparing, queued, running, ready, emptyResult, connectionFailure, interrupted]
    static let multiple = [running, ready, connectionFailure]

    private static let review = QuickEntryReviewPresentation(
        id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
        prompt: "Cafe receipt",
        drafts: [
            draft(id: "30000000-0000-0000-0000-000000000001", counterparty: "Northstar Coffee", amount: "8.50"),
            draft(id: "30000000-0000-0000-0000-000000000002", counterparty: "Northstar Coffee", amount: "3.25"),
        ],
        source: .photo
    )

    private static func item(
        id: String,
        state: ScanDraftItem.State,
        source: ScanDraftItem.Source.Kind,
        displayName: String,
        review: QuickEntryReviewPresentation? = nil,
        failure: ScanDraftItem.Failure? = nil,
        thumbnailData: Data? = nil
    ) -> ScanDraftItem {
        ScanDraftItem(
            id: UUID(uuidString: id)!,
            createdAt: date,
            defaultAccountID: accountID,
            workspaceEpoch: 0,
            workspaceGeneration: 1,
            source: .init(
                kind: source,
                displayName: displayName,
                mediaType: source == .document ? "application/pdf" : "image/jpeg",
                stagedFilename: state == .ready ? nil : "preview.source"
            ),
            state: state,
            review: review,
            failure: failure,
            thumbnailData: thumbnailData,
            hasBeenPresented: false
        )
    }

    private static func draft(id: String, counterparty: String, amount: String) -> QuickEntryDraft {
        QuickEntryDraft(
            payload: QuickEntryDraftPayload(
                id: UUID(uuidString: id)!,
                kind: .expense,
                accountId: accountID,
                destinationAccountId: nil,
                amount: amount,
                currency: "USD",
                categoryId: nil,
                note: nil,
                occurredAt: date,
                recurrence: nil,
                conversion: nil,
                counterparty: counterparty
            ),
            category: nil
        )
    }

    private static var thumbnailData: Data? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96))
        return renderer.jpegData(withCompressionQuality: 0.8) { context in
            UIColor.systemIndigo.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
            UIColor.white.withAlphaComponent(0.85).setFill()
            context.cgContext.fill(CGRect(x: 22, y: 14, width: 52, height: 68))
        }
    }
}

#Preview("Draft pill: Preparing") {
    ScanDraftPillPreview(items: [ScanDraftPreviewData.preparing])
}

#Preview("Draft pill: Queued") {
    ScanDraftPillPreview(items: [ScanDraftPreviewData.queued])
}

#Preview("Draft pill: Running") {
    ScanDraftPillPreview(items: [ScanDraftPreviewData.running])
}

#Preview("Draft pill: Ready") {
    ScanDraftPillPreview(items: [ScanDraftPreviewData.ready])
}

#Preview("Draft pill: Empty result") {
    ScanDraftPillPreview(items: [ScanDraftPreviewData.emptyResult])
}

#Preview("Draft pill: Connection failure") {
    ScanDraftPillPreview(items: [ScanDraftPreviewData.connectionFailure])
}

#Preview("Draft pill: Interrupted") {
    ScanDraftPillPreview(items: [ScanDraftPreviewData.interrupted])
}

#Preview("Draft pill: Multiple") {
    ScanDraftPillPreview(items: ScanDraftPreviewData.multiple)
}

#Preview("Scan drafts: All states") {
    ScanDraftSheetPreview()
}

#Preview("Scan drafts: Dark, large text") {
    ScanDraftSheetPreview()
        .environment(\.colorScheme, .dark)
        .environment(\.dynamicTypeSize, .accessibility2)
}
#endif
