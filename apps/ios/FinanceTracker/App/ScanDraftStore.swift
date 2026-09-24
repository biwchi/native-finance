import Foundation
import PhotosUI
import SwiftUI
import UIKit

struct ScanDraftItem: Codable, Identifiable {
    enum State: String, Codable {
        case preparing
        case queued
        case running
        case ready
        case failed
        case interrupted
    }

    struct Source: Codable {
        enum Kind: String, Codable {
            case camera
            case photoLibrary
            case document
            case quickEntry
        }

        var kind: Kind
        var displayName: String
        var mediaType: String?
        var stagedFilename: String?
    }

    struct Failure: Codable {
        enum Code: String, Codable {
            case emptyExtraction
            case connection
            case sourceUnavailable
            case generic
        }

        let code: Code
        let message: String
    }

    let id: UUID
    let createdAt: Date
    let defaultAccountID: UUID
    let workspaceEpoch: Int
    let workspaceGeneration: Int
    var source: Source
    var state: State
    var review: QuickEntryReviewPresentation?
    var failure: Failure?
    var thumbnailData: Data?
    var hasBeenPresented: Bool

    var isCancelable: Bool {
        state == .preparing || state == .queued || state == .running
    }
}

@MainActor
final class ScanDraftStore: ObservableObject {
    static let metadataKey = "scanDraftQueue"
    static let migrationKey = "scanDraftQueueMigrated"
    static let legacyMetadataKey = "scanImportQueue"
    static let legacyMigrationKey = "scanImportQueueMigrated"

    @Published private(set) var items: [ScanDraftItem] = []
    @Published private(set) var revision = 0
    @Published private(set) var persistenceError: String?

    private weak var transactionStore: TransactionStore?
    private let repository: LocalFinanceRepository
    private let stagingDirectory: URL
    private let persistsChanges: Bool
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var activeDraftID: UUID?

    init(
        transactionStore: TransactionStore,
        repository: LocalFinanceRepository? = nil,
        stagingDirectory: URL? = nil
    ) {
        self.transactionStore = transactionStore
        self.repository = repository ?? .shared
        self.stagingDirectory = stagingDirectory ?? Self.defaultStagingDirectory
        persistsChanges = true
        restore()
    }

    #if DEBUG
    init(previewItems: [ScanDraftItem]) {
        transactionStore = nil
        repository = .shared
        stagingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScanDraftPreviews", isDirectory: true)
        persistsChanges = false
        items = previewItems
    }
    #endif

    deinit {
        for task in tasks.values { task.cancel() }
    }

    var oldestAutomaticReview: ScanDraftItem? {
        items.first { $0.state == .ready && !$0.hasBeenPresented && $0.review != nil }
    }

    var foregroundItem: ScanDraftItem? {
        items.first(where: { $0.state == .running })
            ?? items.first(where: { $0.state == .preparing || $0.state == .queued })
            ?? items.first(where: { $0.state == .ready })
            ?? items.first
    }

    func item(id: UUID) -> ScanDraftItem? {
        items.first { $0.id == id }
    }

    func appBecameActive() {
        do { try recoverSavedReview() }
        catch { persistenceError = error.localizedDescription }
        let previousIDs = items.map(\.id)
        discardItemsFromAnotherWorkspace()
        if previousIDs != items.map(\.id) { persistAndPublish() }
        pumpQueue()
    }

    @discardableResult
    func enqueueCameraPhoto(_ data: Data, defaultAccountID: UUID, replacing replacementID: UUID? = nil) -> UUID {
        prepare(
            kind: .camera,
            displayName: "Scanned photo",
            defaultAccountID: defaultAccountID,
            replacing: replacementID
        ) {
            try await Task.detached(priority: .userInitiated) {
                let photo = try ReceiptPhoto(data: data)
                return PreparedSource(
                    data: photo.jpegData,
                    displayName: "Scanned photo",
                    mediaType: "image/jpeg",
                    thumbnailData: Self.thumbnail(from: photo.jpegData)
                )
            }.value
        }
    }

    @discardableResult
    func enqueuePhoto(
        _ pickerItem: PhotosPickerItem,
        defaultAccountID: UUID,
        replacing replacementID: UUID? = nil
    ) -> UUID {
        prepare(
            kind: .photoLibrary,
            displayName: "Photo",
            defaultAccountID: defaultAccountID,
            replacing: replacementID
        ) {
            guard let data = try await pickerItem.loadTransferable(type: Data.self) else {
                throw LocalDataError(message: "This photo couldn't be loaded. Choose another photo.")
            }
            return try await Task.detached(priority: .userInitiated) {
                let photo = try ReceiptPhoto(data: data)
                return PreparedSource(
                    data: photo.jpegData,
                    displayName: "Photo",
                    mediaType: "image/jpeg",
                    thumbnailData: Self.thumbnail(from: photo.jpegData)
                )
            }.value
        }
    }

    @discardableResult
    func enqueueDocument(
        _ url: URL,
        defaultAccountID: UUID,
        replacing replacementID: UUID? = nil
    ) -> UUID {
        prepare(
            kind: .document,
            displayName: url.lastPathComponent,
            defaultAccountID: defaultAccountID,
            replacing: replacementID
        ) {
            try await Task.detached(priority: .userInitiated) {
                let document = try ReceiptDocument.load(from: url)
                return PreparedSource(
                    data: document.data,
                    displayName: document.filename,
                    mediaType: document.mediaType,
                    thumbnailData: nil
                )
            }.value
        }
    }

    func cancel(_ id: UUID) {
        remove(id)
    }

    func remove(_ id: UUID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        if activeDraftID == id { activeDraftID = nil }
        if let item = item(id: id) { deleteStagedFile(for: item) }
        items.removeAll { $0.id == id }
        persistAndPublish()
        pumpQueue()
    }

    func retry(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard stagedURL(for: items[index]).map({ FileManager.default.fileExists(atPath: $0.path) }) == true else {
            items[index].state = .failed
            items[index].failure = ScanDraftItem.Failure(
                code: .sourceUnavailable,
                message: replacementMessage(for: items[index].source.kind)
            )
            persistAndPublish()
            return
        }
        items[index].state = .queued
        items[index].failure = nil
        items[index].review = nil
        persistAndPublish()
        pumpQueue()
    }

    func markPresented(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }), !items[index].hasBeenPresented else { return }
        items[index].hasBeenPresented = true
        persistAndPublish()
    }

    func updateDrafts(_ drafts: [QuickEntryDraft], for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }), var review = items[index].review else { return }
        guard !drafts.isEmpty else {
            remove(id)
            return
        }
        review.drafts = drafts
        items[index].review = review
        persistAndPublish()
    }

    @discardableResult
    func commit(_ drafts: [QuickEntryDraft], for id: UUID) async throws -> Int {
        guard validMutableIndex(for: id, expected: .ready) != nil, let transactionStore else {
            throw LocalDataError(message: "These drafts are no longer available.")
        }
        let remaining = items.filter { $0.id != id }
        let count = try transactionStore.commitScanDraftBatch(drafts, remainingBatches: remaining)
        if let completed = item(id: id) { deleteStagedFile(for: completed) }
        items = remaining
        publish()
        pumpQueue()
        return count
    }

    func clearForWorkspaceReset() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        activeDraftID = nil
        items.removeAll()
        try? FileManager.default.removeItem(at: stagingDirectory)
        if stagingDirectory.standardizedFileURL == Self.defaultStagingDirectory.standardizedFileURL {
            try? FileManager.default.removeItem(at: Self.legacyStagingDirectory)
        }
        publish()
    }

    private func prepare(
        kind: ScanDraftItem.Source.Kind,
        displayName: String,
        defaultAccountID: UUID,
        replacing replacementID: UUID?,
        operation: @escaping () async throws -> PreparedSource
    ) -> UUID {
        let id: UUID
        if let replacementID, let index = items.firstIndex(where: { $0.id == replacementID }) {
            id = replacementID
            tasks[id]?.cancel()
            deleteStagedFile(for: items[index])
            items[index].source = ScanDraftItem.Source(
                kind: kind,
                displayName: displayName,
                mediaType: nil,
                stagedFilename: nil
            )
            items[index].state = .preparing
            items[index].review = nil
            items[index].failure = nil
            items[index].thumbnailData = nil
            items[index].hasBeenPresented = false
        } else {
            id = UUID()
            items.append(ScanDraftItem(
                id: id,
                createdAt: .now,
                defaultAccountID: defaultAccountID,
                workspaceEpoch: currentWorkspaceEpoch,
                workspaceGeneration: currentWorkspaceGeneration,
                source: ScanDraftItem.Source(
                    kind: kind,
                    displayName: displayName,
                    mediaType: nil,
                    stagedFilename: nil
                ),
                state: .preparing,
                review: nil,
                failure: nil,
                thumbnailData: nil,
                hasBeenPresented: false
            ))
        }
        persistAndPublish()

        tasks[id] = Task { [weak self] in
            do {
                let prepared = try await operation()
                try Task.checkCancellation()
                await self?.finishPreparation(prepared, id: id)
            } catch {
                guard !Task.isCancelled else { return }
                self?.failPreparation(error, id: id)
            }
        }
        return id
    }

    private func finishPreparation(_ prepared: PreparedSource, id: UUID) async {
        guard let index = validMutableIndex(for: id, expected: .preparing) else { return }
        do {
            try FileManager.default.createDirectory(
                at: stagingDirectory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
            let filename = id.uuidString.lowercased() + ".source"
            let url = stagingDirectory.appendingPathComponent(filename)
            try await Task.detached(priority: .utility) {
                try prepared.data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }.value
            guard let currentIndex = validMutableIndex(for: id, expected: .preparing) else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            items[currentIndex].source.displayName = prepared.displayName
            items[currentIndex].source.mediaType = prepared.mediaType
            items[currentIndex].source.stagedFilename = filename
            items[currentIndex].thumbnailData = prepared.thumbnailData
            items[currentIndex].state = .queued
            tasks[id] = nil
            persistAndPublish()
            pumpQueue()
        } catch {
            guard items.indices.contains(index) else { return }
            failPreparation(error, id: id)
        }
    }

    private func failPreparation(_ error: Error, id: UUID) {
        guard let index = validMutableIndex(for: id, expected: .preparing) else { return }
        items[index].state = .failed
        items[index].failure = failure(for: error)
        tasks[id] = nil
        persistAndPublish()
        pumpQueue()
    }

    private func pumpQueue() {
        guard activeDraftID == nil, let transactionStore else { return }
        // Preparation can finish out of order. Do not let a later source pass an
        // earlier accepted source while that earlier item is still preparing.
        guard let index = items.firstIndex(where: {
            $0.state == .preparing || $0.state == .queued || $0.state == .running
        }), items[index].state == .queued else { return }
        let id = items[index].id
        let source = items[index].source
        let accountID = items[index].defaultAccountID
        items[index].state = .running
        activeDraftID = id
        persistAndPublish()

        tasks[id] = Task { [weak self, weak transactionStore] in
            guard let self, let transactionStore else { return }
            do {
                guard let url = self.stagedURL(forID: id) else {
                    throw LocalDataError(message: self.replacementMessage(for: source.kind))
                }
                let data = try await Task.detached(priority: .utility) { try Data(contentsOf: url) }.value
                try Task.checkCancellation()
                let review: QuickEntryReviewPresentation
                if source.kind == .document {
                    let document = try ReceiptDocument(data: data, filename: source.displayName)
                    review = try await transactionStore.interpretQuickEntry(
                        text: "",
                        defaultAccountID: accountID,
                        document: document,
                        persistReview: false
                    )
                } else {
                    review = try await transactionStore.interpretQuickEntry(
                        text: "",
                        defaultAccountID: accountID,
                        photo: "data:image/jpeg;base64," + data.base64EncodedString(),
                        persistReview: false
                    )
                }
                try Task.checkCancellation()
                self.complete(review, id: id)
            } catch {
                guard !Task.isCancelled else { return }
                self.failRecognition(error, id: id)
            }
        }
    }

    private func complete(_ review: QuickEntryReviewPresentation, id: UUID) {
        guard let index = validMutableIndex(for: id, expected: .running) else { return }
        let item = items[index]
        guard item.workspaceEpoch == currentWorkspaceEpoch,
              item.workspaceGeneration == currentWorkspaceGeneration else {
            remove(id)
            return
        }
        deleteStagedFile(for: item)
        items[index].source.stagedFilename = nil
        items[index].state = .ready
        items[index].review = QuickEntryReviewPresentation(
            id: id,
            prompt: review.prompt,
            drafts: review.drafts,
            source: review.source
        )
        items[index].failure = nil
        tasks[id] = nil
        if activeDraftID == id { activeDraftID = nil }
        persistAndPublish()
        pumpQueue()
    }

    private func failRecognition(_ error: Error, id: UUID) {
        guard let index = validMutableIndex(for: id, expected: .running) else { return }
        items[index].state = .failed
        items[index].failure = failure(for: error)
        tasks[id] = nil
        if activeDraftID == id { activeDraftID = nil }
        persistAndPublish()
        pumpQueue()
    }

    private func restore() {
        do {
            try migrateLegacyStagingDirectoryIfNeeded()
            try FileManager.default.createDirectory(
                at: stagingDirectory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
            if let saved = try repository.value([ScanDraftItem].self, key: Self.metadataKey) {
                items = saved
            } else if let legacy = try repository.value([ScanDraftItem].self, key: Self.legacyMetadataKey) {
                items = legacy
                try repository.saveValue(items, key: Self.metadataKey)
                try repository.saveValue(Optional<[ScanDraftItem]>.none, key: Self.legacyMetadataKey)
            }
            try migrateLegacyReviewIfNeeded()
            for index in items.indices where items[index].state == .preparing || items[index].state == .running {
                items[index].state = .interrupted
                items[index].failure = ScanDraftItem.Failure(
                    code: .generic,
                    message: "This draft was interrupted. Try it again."
                )
            }
            discardItemsFromAnotherWorkspace()
            persistAndPublish()
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    private func migrateLegacyReviewIfNeeded() throws {
        // Recover the old single-review slot even when scan migration already ran.
        // New typed reviews also pass through this slot until the collection saves.
        try recoverSavedReview()
        try repository.saveValue(true, key: Self.migrationKey)
    }

    @discardableResult
    func recoverSavedReview() throws -> UUID? {
        guard let review = try repository.value(QuickEntryReviewPresentation.self, key: "quickEntryReview"),
              review.source != .csv else { return nil }
        var updated = items
        if !updated.contains(where: { $0.id == review.id }) {
            let kind: ScanDraftItem.Source.Kind = review.source == .document ? .document
                : review.source == .photo ? .photoLibrary : .quickEntry
            updated.append(ScanDraftItem(
                id: review.id,
                createdAt: .now,
                defaultAccountID: review.drafts.first?.accountId ?? UUID(),
                workspaceEpoch: currentWorkspaceEpoch,
                workspaceGeneration: currentWorkspaceGeneration,
                source: ScanDraftItem.Source(
                    kind: kind,
                    displayName: review.prompt,
                    mediaType: nil,
                    stagedFilename: nil
                ),
                state: .ready,
                review: review,
                failure: nil,
                thumbnailData: nil,
                hasBeenPresented: kind == .quickEntry
            ))
        }
        // Move the review in one write so a failed save leaves the original intact.
        try repository.saveValues([
            Self.metadataKey: try LocalJSON.value(updated),
            "quickEntryReview": .null,
        ])
        items = updated
        persistenceError = nil
        publish()
        return review.id
    }

    private func discardItemsFromAnotherWorkspace() {
        let epoch = currentWorkspaceEpoch
        let generation = currentWorkspaceGeneration
        let stale = items.filter { $0.workspaceEpoch != epoch || $0.workspaceGeneration != generation }
        guard !stale.isEmpty else { return }
        for item in stale {
            tasks[item.id]?.cancel()
            tasks[item.id] = nil
            deleteStagedFile(for: item)
        }
        items.removeAll { $0.workspaceEpoch != epoch || $0.workspaceGeneration != generation }
        if activeDraftID.map({ id in stale.contains { $0.id == id } }) == true { activeDraftID = nil }
    }

    private func validMutableIndex(for id: UUID, expected state: ScanDraftItem.State) -> Int? {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].state == state else { return nil }
        guard items[index].workspaceEpoch == currentWorkspaceEpoch,
              items[index].workspaceGeneration == currentWorkspaceGeneration else {
            discardItemsFromAnotherWorkspace()
            persistAndPublish()
            pumpQueue()
            return nil
        }
        return index
    }

    private func stagedURL(for item: ScanDraftItem) -> URL? {
        item.source.stagedFilename.map(stagingDirectory.appendingPathComponent)
    }

    private func stagedURL(forID id: UUID) -> URL? {
        item(id: id).flatMap(stagedURL)
    }

    private func deleteStagedFile(for item: ScanDraftItem) {
        guard let url = stagedURL(for: item) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func persistAndPublish() {
        guard persistsChanges else {
            publish()
            return
        }
        do {
            try repository.saveValue(items, key: Self.metadataKey)
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
        }
        publish()
    }

    private func publish() {
        revision &+= 1
    }

    private var currentWorkspaceEpoch: Int {
        (try? repository.value(Int.self, key: "localEpoch")) ?? 0
    }

    private var currentWorkspaceGeneration: Int {
        (try? repository.value(Int.self, key: "generation")) ?? 1
    }

    private func failure(for error: Error) -> ScanDraftItem.Failure {
        if let apiError = error as? APIClientError,
           case let .requestFailed(status, message, code) = apiError {
            if code == "empty_extraction" {
                return ScanDraftItem.Failure(code: .emptyExtraction, message: message ?? "No transactions were found.")
            }
            if status >= 500 {
                return ScanDraftItem.Failure(code: .connection, message: message ?? "The scan service is unavailable. Try again.")
            }
            return ScanDraftItem.Failure(code: .generic, message: message ?? apiError.localizedDescription)
        }
        if (error as NSError).domain == NSURLErrorDomain {
            return ScanDraftItem.Failure(code: .connection, message: "Check your connection and try again.")
        }
        return ScanDraftItem.Failure(code: .generic, message: error.localizedDescription)
    }

    private func replacementMessage(for kind: ScanDraftItem.Source.Kind) -> String {
        kind == .document ? "Choose the document again to retry." : "Choose or take another photo."
    }

    static var defaultStagingDirectory: URL {
        let root = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("FinanceTracker", isDirectory: true)
            .appendingPathComponent("ScanDrafts", isDirectory: true)
    }

    private static var legacyStagingDirectory: URL {
        defaultStagingDirectory.deletingLastPathComponent()
            .appendingPathComponent("ScanImports", isDirectory: true)
    }

    static func removeAllStagedFiles() {
        try? FileManager.default.removeItem(at: defaultStagingDirectory)
        try? FileManager.default.removeItem(at: legacyStagingDirectory)
    }

    private func migrateLegacyStagingDirectoryIfNeeded() throws {
        let fileManager = FileManager.default
        let legacy = Self.legacyStagingDirectory
        guard fileManager.fileExists(atPath: legacy.path) else { return }
        try fileManager.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        for source in try fileManager.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil) {
            let destination = stagingDirectory.appendingPathComponent(source.lastPathComponent)
            guard !fileManager.fileExists(atPath: destination.path) else { continue }
            try fileManager.moveItem(at: source, to: destination)
        }
        try? fileManager.removeItem(at: legacy)
    }

    nonisolated private static func thumbnail(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maximum: CGFloat = 96
        let scale = min(maximum / image.size.width, maximum / image.size.height, 1)
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: 0.72) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

private struct PreparedSource: Sendable {
    let data: Data
    let displayName: String
    let mediaType: String
    let thumbnailData: Data?
}
