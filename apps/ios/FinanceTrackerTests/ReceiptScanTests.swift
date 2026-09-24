import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import FinanceTracker

@MainActor
final class ReceiptScanTests: XCTestCase {
    func testCanonicalQuickEntryPayloadPreservesCounterpartyAndNoteThroughOfflineReviewAndSave() async throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository, currency: "KZT")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScanProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); ScanProtocol.responseData = Data() }
        ScanProtocol.responseData = try JSONSerialization.data(withJSONObject: [
            "referenceNow": "2026-09-21T10:00:00Z",
            "transactions": [["id": UUID().uuidString, "kind": "expense", "accountId": account.id.uuidString,
                              "amount": "1500", "currency": "KZT", "counterparty": "Starbucks",
                              "note": "Кофе", "occurredAt": "2026-09-21T10:00:00Z"]],
        ])
        let store = TransactionStore(apiClient: APIClient(baseURL: URL(string: "https://scan.test")!, session: session), repository: repository)
        let review = try await store.interpretQuickEntry(text: "Кофе в Starbucks 1500", defaultAccountID: account.id)
        XCTAssertEqual(review.drafts.first?.counterparty, "Starbucks")
        XCTAssertEqual(review.drafts.first?.note, "Кофе")
        let recovered = try XCTUnwrap(store.savedQuickEntryReview())
        _ = try await store.commitQuickEntryDrafts(recovered.drafts)
        XCTAssertEqual(store.allTransactions.first?.counterparty, "Starbucks")
        XCTAssertEqual(store.allTransactions.first?.note, "Кофе")
    }

    func testDocumentTypesEncodingSizeAndCoordinatedFileRead() throws {
        for (extensionName, mediaType) in [
            "PDF": "application/pdf", "csv": "text/csv", "tsv": "text/tsv",
            "xls": "application/vnd.ms-excel", "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        ] {
            let data = Data("local fixture".utf8)
            let document = try ReceiptDocument(data: data, filename: "Statement.\(extensionName)")
            let request = QuickEntryRequest(text: "", defaultAccountId: UUID(), locale: "en_US", timeZone: "UTC", document: document)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
            let encoded = try XCTUnwrap(object["document"] as? [String: Any])
            XCTAssertEqual(encoded["filename"] as? String, document.filename)
            XCTAssertEqual(encoded["mediaType"] as? String, mediaType)
            XCTAssertEqual(encoded["data"] as? String, data.base64EncodedString())
            XCTAssertNil(object["photo"])
            XCTAssertTrue(ReceiptDocument.supportedTypes.contains { $0 == UTType(filenameExtension: extensionName.lowercased()) })
        }
        XCTAssertThrowsError(try ReceiptDocument(data: Data(), filename: "empty.pdf"))
        XCTAssertThrowsError(try ReceiptDocument(data: Data([1]), filename: "script.exe"))
        XCTAssertThrowsError(try ReceiptDocument(data: Data([1]), filename: "../statement.pdf"))
        XCTAssertThrowsError(try ReceiptDocument(data: Data(repeating: 0, count: ReceiptDocument.maximumBytes + 1), filename: "large.pdf"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).csv")
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = Data("Date,Amount\n2026-09-20,12.50".utf8)
        try bytes.write(to: url)
        XCTAssertEqual(try ReceiptDocument.load(from: url).data, bytes)
        XCTAssertEqual(try ReceiptDocument.load(from: url).filename, url.lastPathComponent)
    }

    func testDocumentInterpretationOnlySavesDraftsThenAllowsEditingRemovingAndSubmittingOffline() async throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScanProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); ScanProtocol.responseData = Data() }
        ScanProtocol.responseData = try JSONSerialization.data(withJSONObject: [
            "referenceNow": "2026-09-11T10:00:00Z",
            "transactions": ["Cafe", "Market"].map { merchant in [
                "id": UUID().uuidString, "kind": "expense", "accountId": account.id.uuidString,
                "amount": "12.5", "currency": "USD", "counterparty": merchant, "occurredAt": "2026-09-11T10:00:00Z",
            ] },
        ])
        let store = TransactionStore(apiClient: APIClient(baseURL: URL(string: "https://scan.test")!, session: session), repository: repository)
        store.quickEntryText = "Unfinished typed entry"
        let document = try ReceiptDocument(data: Data("%PDF-1.7 fixture".utf8), filename: "Bank statement.pdf")
        let review = try await store.interpretQuickEntry(text: "", defaultAccountID: account.id, document: document)
        XCTAssertEqual(review.source, .document)
        XCTAssertEqual(review.prompt, document.filename)
        XCTAssertEqual(review.drafts.count, 2)
        XCTAssertTrue(store.allTransactions.isEmpty)
        XCTAssertEqual(store.quickEntryText, "Unfinished typed entry")
        let savedJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(review)) as? [String: Any])
        XCTAssertNil(savedJSON["document"])
        XCTAssertNil(savedJSON["data"])

        let offlineStore = TransactionStore(repository: repository)
        var recovered = try XCTUnwrap(offlineStore.savedQuickEntryReview())
        XCTAssertEqual(recovered.source, .document)
        recovered.drafts.removeLast()
        recovered.drafts[0].amount = "15"
        recovered.drafts[0].counterparty = "Edited cafe"
        try offlineStore.saveQuickEntryReview(recovered)
        _ = try await offlineStore.commitQuickEntryDrafts(recovered.drafts)
        XCTAssertEqual(offlineStore.allTransactions.count, 1)
        XCTAssertEqual(offlineStore.allTransactions.first?.amount, "15")
        XCTAssertEqual(offlineStore.allTransactions.first?.counterparty, "Edited cafe")
        XCTAssertNil(offlineStore.savedQuickEntryReview())
    }

    func testFailedOrCanceledDocumentDoesNotOverwriteSavedReviewAndDiscardDoesNotWriteTransactions() async throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScanProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); ScanProtocol.responseData = Data(); ScanProtocol.statusCode = 200 }
        let store = TransactionStore(apiClient: APIClient(baseURL: URL(string: "https://scan.test")!, session: session), repository: repository)
        let saved = QuickEntryReviewPresentation(prompt: "Earlier statement.pdf", drafts: [], source: .document)
        try store.saveQuickEntryReview(saved)
        store.quickEntryText = "Coffee tomorrow"
        let document = try ReceiptDocument(data: Data("Date,Amount".utf8), filename: "statement.csv")
        ScanProtocol.statusCode = 503
        ScanProtocol.responseData = Data("{\"message\":\"Could not read document\"}".utf8)
        do {
            _ = try await store.interpretQuickEntry(text: "", defaultAccountID: account.id, document: document)
            XCTFail("The failed request should not create a review")
        } catch {}
        XCTAssertEqual(store.savedQuickEntryReview()?.id, saved.id)
        let task = Task { try await store.interpretQuickEntry(text: "", defaultAccountID: account.id, document: document) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Canceled requests must not save a review") } catch {}
        XCTAssertEqual(store.savedQuickEntryReview()?.id, saved.id)
        try store.saveQuickEntryReview(nil)
        XCTAssertNil(store.savedQuickEntryReview())
        XCTAssertTrue(store.allTransactions.isEmpty)
        XCTAssertEqual(store.quickEntryText, "Coffee tomorrow")
    }

    func testDraftWithMissingAmountCannotBeSaved() async throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository)
        let store = TransactionStore(repository: repository)
        var draft = QuickEntryDraft(payload: QuickEntryDraftPayload(id: UUID(), kind: .expense, accountId: account.id,
            destinationAccountId: nil, amount: "", currency: "USD", categoryId: nil, note: nil, occurredAt: LocalTestData.now, recurrence: nil,
            conversion: nil, counterparty: "Cafe"), category: nil)
        try store.saveQuickEntryReview(QuickEntryReviewPresentation(prompt: "Scanned photo", drafts: [draft], source: .photo))
        do {
            _ = try await store.commitQuickEntryDrafts([draft])
            XCTFail("A draft with no amount must not be saved")
        } catch {
            XCTAssertTrue(store.allTransactions.isEmpty)
        }
        draft.amount = "12.50"
        _ = try await store.commitQuickEntryDrafts([draft])
        XCTAssertEqual(store.allTransactions.count, 1)
    }

    func testDraftCurrencySurvivesAnAccountCurrencyChangeBeforeSaving() async throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository)
        let draft = QuickEntryDraft(payload: QuickEntryDraftPayload(id: UUID(), kind: .expense, accountId: account.id,
            destinationAccountId: nil, amount: "12.50", currency: "USD", categoryId: nil, note: nil, occurredAt: LocalTestData.now, recurrence: nil,
            conversion: nil, counterparty: nil), category: nil)
        _ = try repository.edit { try $0.saveAccount(id: account.id, name: account.name, currency: "EUR", icon: "bank", color: .blue) }
        let store = TransactionStore(repository: repository)
        _ = try await store.commitQuickEntryDrafts([draft])
        XCTAssertEqual(store.allTransactions.first?.currency, "USD")
        XCTAssertEqual(store.allTransactions.first?.amount, "12.5")
    }

    func testPhotoInterpretationPersistsOnlyDraftsUntilUserSaves() async throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScanProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); ScanProtocol.responseData = Data() }
        ScanProtocol.responseData = try JSONSerialization.data(withJSONObject: [
            "referenceNow": "2026-09-11T10:00:00Z",
            "transactions": [["id": UUID().uuidString, "kind": "expense", "accountId": account.id.uuidString,
                "amount": "12.5", "currency": "USD", "counterparty": "Cafe", "occurredAt": "2026-09-11T10:00:00Z",
                "note": "Lunch"]],
        ])
        let store = TransactionStore(apiClient: APIClient(baseURL: URL(string: "https://scan.test")!, session: session), repository: repository)
        store.quickEntryText = "Coffee tomorrow"
        let review = try await store.interpretQuickEntry(text: "Recognize purchases", defaultAccountID: account.id,
            photo: "data:image/jpeg;base64,/9j/2Q==")
        XCTAssertEqual(review.source, .photo)
        XCTAssertEqual(review.prompt, "Scanned photo")
        XCTAssertEqual(review.drafts.first?.counterparty, "Cafe")
        XCTAssertEqual(store.savedQuickEntryReview()?.id, review.id)
        XCTAssertEqual(store.quickEntryText, "Coffee tomorrow")
        XCTAssertTrue(store.allTransactions.isEmpty)
    }

    func testPhotoNormalizesOrientationBoundsSizeAndRemovesLocation() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let original = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 1500), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3000, height: 1500))
        }
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(original.cgImage), [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 43.2, kCGImagePropertyGPSLongitude: 76.9],
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let photo = try ReceiptPhoto(data: data as Data)
        let decoded = try XCTUnwrap(UIImage(data: photo.jpegData))
        XCTAssertEqual(decoded.size.width, 1024)
        XCTAssertEqual(decoded.size.height, 2048)
        XCTAssertEqual(decoded.imageOrientation, .up)
        XCTAssertLessThanOrEqual(photo.jpegData.count, 4 * 1024 * 1024)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(photo.jpegData as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary as String])
        XCTAssertEqual(Data(base64Encoded: String(photo.dataURL.dropFirst("data:image/jpeg;base64,".count))), photo.jpegData)
        XCTAssertThrowsError(try ReceiptPhoto(data: Data("not a photo".utf8)))
    }

    func testScannedDraftCanBeEditedSavedOfflineAndDiscardedWithoutLosingTypedEntry() async throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository)
        let store = TransactionStore(repository: repository)
        store.quickEntryText = "Unfinished typed entry"
        var draft = QuickEntryDraft(payload: QuickEntryDraftPayload(id: UUID(), kind: .expense, accountId: account.id,
            destinationAccountId: nil, amount: "12.50", currency: "USD", categoryId: nil, note: nil, occurredAt: LocalTestData.now, recurrence: nil,
            conversion: nil, counterparty: "Cafe"), category: nil)
        let review = QuickEntryReviewPresentation(prompt: "Scanned photo", drafts: [draft], source: .photo)
        try store.saveQuickEntryReview(review)
        let reopened = TransactionStore(repository: try LocalFinanceRepository(path: repository.requireDatabase().pool.path))
        XCTAssertEqual(reopened.savedQuickEntryReview()?.source, .photo)
        XCTAssertEqual(reopened.quickEntryText, "", "Only reviewed drafts survive a new app session")
        XCTAssertTrue(reopened.allTransactions.isEmpty)
        draft.amount = "13.50"
        draft.note = "Lunch with Sam"
        _ = try await store.commitQuickEntryDrafts([draft])
        XCTAssertEqual(store.allTransactions.first?.amount, "13.5")
        XCTAssertEqual(store.allTransactions.first?.note, "Lunch with Sam")
        XCTAssertNil(store.savedQuickEntryReview())
        XCTAssertEqual(store.quickEntryText, "Unfinished typed entry")
        try store.saveQuickEntryReview(review)
        try store.saveQuickEntryReview(nil)
        XCTAssertEqual(store.allTransactions.count, 1)
        XCTAssertEqual(store.quickEntryText, "Unfinished typed entry")
    }

    func testPhotoRequestEncodingAndLegacyDraftRecovery() throws {
        let request = QuickEntryRequest(text: "Recognize purchases", defaultAccountId: UUID(), locale: "en_US",
            timeZone: "UTC", photo: "data:image/jpeg;base64,/9j/2Q==")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(object["photo"] as? String, request.photo)
        let oldReview = Data("{\"id\":\"\(UUID())\",\"prompt\":\"Coffee\",\"drafts\":[],\"unparsedText\":[]}".utf8)
        XCTAssertNil(try JSONDecoder().decode(QuickEntryReviewPresentation.self, from: oldReview).source)
    }

    func testSavedDraftDropsObsoleteReviewFieldsWithoutLosingNote() async throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository)
        let legacy: [String: Any] = [
            "id": UUID().uuidString, "mode": "expense", "accountId": account.id.uuidString,
            "amount": "12.5", "currency": "USD", "occurredAt": 0,
            "isRecurring": false, "recurrenceFrequency": "monthly", "note": "Lunch with Sam",
            "sourceText": "Original receipt", "evidence": ["Paid total 12.50 USD"],
            "warnings": ["Confirm the payment status."], "requiresReview": true,
        ]
        let draft = try JSONDecoder().decode(QuickEntryDraft.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(draft.note, "Lunch with Sam")
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
        XCTAssertNil(saved["sourceText"])
        XCTAssertNil(saved["evidence"])
        XCTAssertNil(saved["warnings"])
        XCTAssertNil(saved["requiresReview"])
        let oldReview: [String: Any] = ["id": UUID().uuidString, "prompt": "Scanned photo",
            "source": "photo", "drafts": [legacy], "unparsedText": ["Old review message"]]
        let review = try JSONDecoder().decode(QuickEntryReviewPresentation.self,
            from: JSONSerialization.data(withJSONObject: oldReview))
        XCTAssertEqual(review.prompt, "Scanned photo")
        let store = TransactionStore(repository: repository)
        try store.saveQuickEntryReview(review)
        let recovered = try XCTUnwrap(store.savedQuickEntryReview())
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(recovered)) as? [String: Any])
        XCTAssertNil(encoded["unparsedText"])
        _ = try await store.commitQuickEntryDrafts(recovered.drafts)
        XCTAssertEqual(store.allTransactions.first?.note, "Lunch with Sam")
    }

    func testDraftQueueKeepsBatchesIndependentAndContinuesAfterFailure() async throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScanProtocol.self]
        let session = URLSession(configuration: configuration)
        let transactionStore = TransactionStore(
            apiClient: APIClient(baseURL: URL(string: "https://scan.test")!, session: session),
            repository: repository
        )
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("scan-queue-\(UUID())", isDirectory: true)
        let firstURL = FileManager.default.temporaryDirectory.appendingPathComponent("first-\(UUID()).csv")
        let secondURL = FileManager.default.temporaryDirectory.appendingPathComponent("second-\(UUID()).csv")
        try Data("Date,Amount\n2026-09-20,4".utf8).write(to: firstURL)
        try Data("Date,Amount\n2026-09-20,8".utf8).write(to: secondURL)
        defer {
            session.invalidateAndCancel()
            ScanProtocol.handler = nil
            ScanProtocol.responseSequence = []
            try? FileManager.default.removeItem(at: staging)
            try? FileManager.default.removeItem(at: firstURL)
            try? FileManager.default.removeItem(at: secondURL)
        }

        ScanProtocol.responseSequence = [
            (503, Data("{\"message\":\"Temporarily offline\",\"code\":\"quick_entry_unavailable\"}".utf8)),
            (200, try JSONSerialization.data(withJSONObject: [
                "referenceNow": "2026-09-20T10:00:00Z",
                "transactions": [[
                    "id": UUID().uuidString, "kind": "expense", "accountId": account.id.uuidString,
                    "amount": "8", "currency": "USD", "counterparty": "Second", "occurredAt": "2026-09-20T10:00:00Z",
                ]],
            ])),
        ]

        let queue = ScanDraftStore(transactionStore: transactionStore, repository: repository, stagingDirectory: staging)
        let firstID = queue.enqueueDocument(firstURL, defaultAccountID: account.id)
        let secondID = queue.enqueueDocument(secondURL, defaultAccountID: account.id)
        try await waitForDrafts {
            queue.item(id: firstID)?.state == .failed && queue.item(id: secondID)?.state == .ready
        }

        XCTAssertEqual(queue.items.map(\.id), [firstID, secondID])
        XCTAssertEqual(queue.item(id: firstID)?.failure?.code, .connection)
        XCTAssertEqual(queue.item(id: secondID)?.review?.drafts.first?.counterparty, "Second")
        XCTAssertTrue(transactionStore.allTransactions.isEmpty)
        XCTAssertEqual(queue.oldestAutomaticReview?.id, secondID)
        queue.markPresented(secondID)
        XCTAssertNil(queue.oldestAutomaticReview)

        ScanProtocol.responseSequence = [
            (200, try JSONSerialization.data(withJSONObject: [
                "referenceNow": "2026-09-20T10:00:00Z",
                "transactions": [[
                    "id": UUID().uuidString, "kind": "expense", "accountId": account.id.uuidString,
                    "amount": "4", "currency": "USD", "counterparty": "First", "occurredAt": "2026-09-20T10:00:00Z",
                ]],
            ])),
        ]
        queue.retry(firstID)
        XCTAssertEqual(queue.items.map(\.id), [firstID, secondID])
        try await waitForDrafts { queue.item(id: firstID)?.state == .ready }
        XCTAssertEqual(queue.item(id: firstID)?.review?.drafts.first?.counterparty, "First")
        XCTAssertEqual(queue.item(id: secondID)?.state, .ready)

        let secondDrafts = try XCTUnwrap(queue.item(id: secondID)?.review?.drafts)
        _ = try await queue.commit(secondDrafts, for: secondID)
        XCTAssertEqual(queue.items.map(\.id), [firstID])
        XCTAssertEqual(transactionStore.allTransactions.map(\.counterparty), ["Second"])

        let reopenedTransactions = TransactionStore(repository: try LocalFinanceRepository(path: repository.requireDatabase().pool.path))
        let reopenedQueue = ScanDraftStore(
            transactionStore: reopenedTransactions,
            repository: try LocalFinanceRepository(path: repository.requireDatabase().pool.path),
            stagingDirectory: staging
        )
        XCTAssertEqual(reopenedQueue.items.map(\.id), [firstID])
        XCTAssertEqual(reopenedQueue.item(id: firstID)?.state, .ready)
    }

    func testCancelDuringPreparationCannotRestoreRemovedDraft() async throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository)
        let store = TransactionStore(repository: repository)
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("scan-cancel-\(UUID())", isDirectory: true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cancel-\(UUID()).csv")
        try Data(repeating: 65, count: 2 * 1024 * 1024).write(to: url)
        defer {
            try? FileManager.default.removeItem(at: staging)
            try? FileManager.default.removeItem(at: url)
        }
        let queue = ScanDraftStore(transactionStore: store, repository: repository, stagingDirectory: staging)
        let id = queue.enqueueDocument(url, defaultAccountID: account.id)
        queue.cancel(id)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNil(queue.item(id: id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.appendingPathComponent(id.uuidString.lowercased() + ".source").path))
    }

    func testCancellationDuringRecognitionIgnoresLateResponse() async throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScanProtocol.self]
        let session = URLSession(configuration: configuration)
        let transactionStore = TransactionStore(
            apiClient: APIClient(baseURL: URL(string: "https://scan.test")!, session: session),
            repository: repository
        )
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("scan-late-\(UUID())", isDirectory: true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("late-\(UUID()).csv")
        try Data("Date,Amount\n2026-09-20,12".utf8).write(to: url)
        ScanProtocol.responseData = try JSONSerialization.data(withJSONObject: [
            "referenceNow": "2026-09-20T10:00:00Z",
            "transactions": [[
                "id": UUID().uuidString, "kind": "expense", "accountId": account.id.uuidString,
                "amount": "12", "currency": "USD", "counterparty": "Late", "occurredAt": "2026-09-20T10:00:00Z",
            ]],
        ])
        ScanProtocol.statusCode = 200
        ScanProtocol.responseDelay = 0.2
        ScanProtocol.handler = nil
        ScanProtocol.responseSequence = []
        defer {
            session.invalidateAndCancel()
            ScanProtocol.responseDelay = 0
            ScanProtocol.responseData = Data()
            ScanProtocol.handler = nil
            ScanProtocol.responseSequence = []
            try? FileManager.default.removeItem(at: staging)
            try? FileManager.default.removeItem(at: url)
        }

        let queue = ScanDraftStore(transactionStore: transactionStore, repository: repository, stagingDirectory: staging)
        let id = queue.enqueueDocument(url, defaultAccountID: account.id)
        try await waitForDrafts { queue.item(id: id)?.state == .running }
        queue.cancel(id)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertNil(queue.item(id: id))
        XCTAssertTrue(transactionStore.allTransactions.isEmpty)
    }

    func testWorkspaceResetCancelsDraftsAndRemovesStagedSources() async throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScanProtocol.self]
        let session = URLSession(configuration: configuration)
        let transactionStore = TransactionStore(
            apiClient: APIClient(baseURL: URL(string: "https://scan.test")!, session: session),
            repository: repository
        )
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("scan-reset-\(UUID())", isDirectory: true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("reset-\(UUID()).csv")
        try Data("Date,Amount\n2026-09-20,12".utf8).write(to: url)
        ScanProtocol.responseData = try JSONSerialization.data(withJSONObject: [
            "referenceNow": "2026-09-20T10:00:00Z",
            "transactions": [[
                "id": UUID().uuidString, "kind": "expense", "accountId": account.id.uuidString,
                "amount": "12", "currency": "USD", "counterparty": "Reset", "occurredAt": "2026-09-20T10:00:00Z",
            ]],
        ])
        ScanProtocol.statusCode = 200
        ScanProtocol.responseDelay = 0.2
        ScanProtocol.handler = nil
        ScanProtocol.responseSequence = []
        defer {
            session.invalidateAndCancel()
            ScanProtocol.responseDelay = 0
            ScanProtocol.responseData = Data()
            ScanProtocol.handler = nil
            ScanProtocol.responseSequence = []
            try? FileManager.default.removeItem(at: staging)
            try? FileManager.default.removeItem(at: url)
        }

        let queue = ScanDraftStore(transactionStore: transactionStore, repository: repository, stagingDirectory: staging)
        let id = queue.enqueueDocument(url, defaultAccountID: account.id)
        try await waitForDrafts { queue.item(id: id)?.state == .running }
        XCTAssertTrue(FileManager.default.fileExists(atPath: staging.path))

        queue.clearForWorkspaceReset()
        XCTAssertTrue(queue.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(queue.item(id: id))
        XCTAssertTrue(transactionStore.allTransactions.isEmpty)
    }

    func testLegacyScanReviewMigratesOnceIntoTheQueue() throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository)
        let draft = QuickEntryDraft(payload: QuickEntryDraftPayload(
            id: UUID(), kind: .expense, accountId: account.id, destinationAccountId: nil,
            amount: "4.50", currency: "USD", categoryId: nil, note: nil, occurredAt: LocalTestData.now, recurrence: nil, conversion: nil,
            counterparty: "Cafe"), category: nil
        )
        let review = QuickEntryReviewPresentation(prompt: "Scanned photo", drafts: [draft], source: .photo)
        let transactionStore = TransactionStore(repository: repository)
        try transactionStore.saveQuickEntryReview(review)
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("scan-migrate-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        let queue = ScanDraftStore(transactionStore: transactionStore, repository: repository, stagingDirectory: staging)
        XCTAssertEqual(queue.items.map(\.id), [review.id])
        XCTAssertEqual(queue.items.first?.state, .ready)
        XCTAssertNil(transactionStore.savedQuickEntryReview())

        let reopened = ScanDraftStore(transactionStore: transactionStore, repository: repository, stagingDirectory: staging)
        XCTAssertEqual(reopened.items.map(\.id), [review.id])
    }

    func testQuickEntryJoinsDraftListAfterScanMigrationAndKeepsEditsAcrossRelaunch() async throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository)
        let store = TransactionStore(repository: repository)
        let queue = ScanDraftStore(transactionStore: store, repository: repository)
        XCTAssertEqual(try repository.value(Bool.self, key: ScanDraftStore.migrationKey), true)
        let scan = draftReview(accountID: account.id, source: .photo)
        try store.saveQuickEntryReview(scan)
        try queue.recoverSavedReview()
        let typed = draftReview(accountID: account.id, source: nil)
        try store.saveQuickEntryReview(typed)
        try queue.recoverSavedReview()
        XCTAssertEqual(queue.items.map(\.id), [scan.id, typed.id])
        XCTAssertEqual(queue.item(id: typed.id)?.source.kind, .quickEntry)
        XCTAssertEqual(queue.oldestAutomaticReview?.id, scan.id)
        XCTAssertNil(store.savedQuickEntryReview())
        var edited = typed.drafts
        edited[0].amount = "18"
        queue.updateDrafts(edited, for: typed.id)

        let reopenedRepository = try LocalFinanceRepository(path: repository.requireDatabase().pool.path)
        let reopenedStore = TransactionStore(repository: reopenedRepository)
        let reopened = ScanDraftStore(transactionStore: reopenedStore, repository: reopenedRepository)
        XCTAssertEqual(reopened.items.map(\.id), [scan.id, typed.id])
        XCTAssertEqual(reopened.item(id: typed.id)?.review?.drafts.first?.amount, "18")
        XCTAssertTrue(reopenedStore.allTransactions.isEmpty)
        let count = try await reopened.commit(edited, for: typed.id)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(reopenedStore.allTransactions.first?.amount, "18")
        XCTAssertEqual(reopened.items.map(\.id), [scan.id])
        reopened.updateDrafts([], for: scan.id)
        XCTAssertTrue(reopened.items.isEmpty)
        XCTAssertEqual(try reopenedRepository.value([ScanDraftItem].self, key: ScanDraftStore.metadataKey)?.count, 0)
        XCTAssertEqual(reopenedStore.allTransactions.count, 1)
    }

    func testScanCommitPersistsTransactionsAndPreventsRepeatSubmission() async throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository)
        let store = TransactionStore(repository: repository)
        let review = draftReview(accountID: account.id, source: .photo)
        try store.saveQuickEntryReview(review)
        let queue = ScanDraftStore(transactionStore: store, repository: repository)
        let count = try await queue.commit(review.drafts, for: review.id)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(store.transactions.map(\.amount), ["4.5"])
        XCTAssertTrue(queue.items.isEmpty)
        await Task.yield()
        let reopened = try LocalFinanceRepository(path: repository.requireDatabase().pool.path)
        XCTAssertEqual(reopened.snapshot.detailedTransactions.map(\.amount), ["4.5"])
        XCTAssertEqual(reopened.snapshot.pending.last?.mutation.changes.filter { $0.entity == "transaction" }.count, 1)
        XCTAssertEqual(try reopened.value([ScanDraftItem].self, key: ScanDraftStore.metadataKey)?.count, 0)
        do {
            _ = try await queue.commit(review.drafts, for: review.id)
            XCTFail("A completed review must not submit twice")
        } catch {}
        XCTAssertEqual(store.allTransactions.count, 1)
    }

    func testScanCommitStorageFailureKeepsDraftsAndRollsBackTransactions() async throws {
        let repository = try LocalTestData.repository()
        let account = try LocalTestData.account(repository)
        let store = TransactionStore(repository: repository)
        let review = draftReview(accountID: account.id, source: .photo)
        try store.saveQuickEntryReview(review)
        let queue = ScanDraftStore(transactionStore: store, repository: repository)
        let pendingCount = repository.snapshot.pending.count
        try repository.requireDatabase().write { db in
            try db.execute(sql: """
                CREATE TRIGGER fail_draft_removal BEFORE UPDATE ON metadata
                WHEN NEW.key = 'scanDraftQueue'
                BEGIN SELECT RAISE(ABORT, 'Simulated storage failure'); END
                """)
        }
        do {
            _ = try await queue.commit(review.drafts, for: review.id)
            XCTFail("A failed write must keep the review open")
        } catch {}
        XCTAssertEqual(queue.items.map(\.id), [review.id])
        let reopened = try LocalFinanceRepository(path: repository.requireDatabase().pool.path)
        XCTAssertTrue(reopened.snapshot.transactions.isEmpty)
        XCTAssertEqual(reopened.snapshot.pending.count, pendingCount)
        XCTAssertEqual(try reopened.value([ScanDraftItem].self, key: ScanDraftStore.metadataKey)?.map(\.id), [review.id])
        try repository.requireDatabase().write { try $0.execute(sql: "DROP TRIGGER fail_draft_removal") }
        _ = try await queue.commit(review.drafts, for: review.id)
        XCTAssertEqual(store.allTransactions.count, 1)
    }

    func testDraftListAndReviewRenderInBothAppearances() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for scheme in [ColorScheme.light, .dark] {
            let repository = try LocalTestData.repository()
            let account = try LocalTestData.account(repository)
            let transactions = TransactionStore(repository: repository)
            let queue = ScanDraftStore(transactionStore: transactions, repository: repository)
            let photo = draftReview(accountID: account.id, source: .photo)
            let typed = draftReview(accountID: account.id, source: nil)
            for review in [photo, typed] {
                try transactions.saveQuickEntryReview(review)
                try queue.recoverSavedReview()
            }
            let accounts = AccountStore(repository: repository)
            let content = DraftReviewFixture(queue: queue)
                .environmentObject(queue)
                .environmentObject(transactions)
                .environmentObject(accounts)
                .preferredColorScheme(scheme)
            let controller = UIHostingController(rootView: content)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            try await Task.sleep(for: .milliseconds(400))
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Shared-drafts-\(scheme)"
            attachment.lifetime = .keepAlways
            add(attachment)
            // iOS 18 exposes hosted SwiftUI buttons for in-process activation.
            if #unavailable(iOS 26.0) {
                try activate("Review", in: window)
                try await Task.sleep(for: .milliseconds(500))
                XCTAssertNotNil(controller.presentedViewController)
                try activate("Add 1 transaction", in: window)
                try await Task.sleep(for: .seconds(1))
                XCTAssertNil(controller.presentedViewController)
                XCTAssertEqual(transactions.allTransactions.count, 1)
                XCTAssertEqual(queue.items.map(\.id), [typed.id])
            }
        }
    }

    private struct DraftReviewFixture: View {
        let queue: ScanDraftStore
        @State private var review: QuickEntryReviewPresentation?
        var body: some View {
            ScanDraftsView(onReview: { review = queue.item(id: $0)?.review }, onReplace: { _ in }, onManualEntry: { _ in })
                .safeAreaInset(edge: .bottom) {
                    ScanDraftActivityPill(onReview: { review = queue.item(id: $0)?.review }, onOpenDrafts: {}, onReplace: { _ in }, onManualEntry: { _ in })
                }
                .appSheet(item: $review) { presentation in
                    QuickEntryReviewView(presentation: presentation,
                        onDraftsChange: { queue.updateDrafts($0, for: presentation.id) },
                        onCommit: { try await queue.commit($0, for: presentation.id) })
                }
        }
    }

    private func activate(_ title: String, in window: UIWindow) throws {
        var visited = Set<ObjectIdentifier>()
        func elements(_ object: NSObject, depth: Int = 0) -> [NSObject] {
            guard depth < 30, visited.insert(ObjectIdentifier(object)).inserted else { return [] }
            var children = ((object.automationElements ?? []) + (object.accessibilityElements ?? [])).compactMap { $0 as? NSObject }
            let count = object.accessibilityElementCount()
            if count > 0 && count < 200 {
                children += (0..<count).compactMap { object.accessibilityElement(at: $0) as? NSObject }
            }
            children += (object as? UIView)?.subviews ?? []
            return [object] + children.flatMap { elements($0, depth: depth + 1) }
        }
        let button = try XCTUnwrap(elements(window).first { $0.accessibilityLabel == title && $0.accessibilityTraits.contains(.button) })
        XCTAssertTrue(button.accessibilityActivate())
    }

    private func draftReview(accountID: UUID, source: QuickEntryReviewPresentation.Source?) -> QuickEntryReviewPresentation {
        let draft = QuickEntryDraft(payload: QuickEntryDraftPayload(
            id: UUID(), kind: .expense, accountId: accountID, destinationAccountId: nil,
            amount: "4.50", currency: "USD", categoryId: nil, note: nil, occurredAt: .now, recurrence: nil, conversion: nil,
            counterparty: "Cafe"), category: nil
        )
        return QuickEntryReviewPresentation(prompt: source == nil ? "Coffee 4.50" : "Scanned photo", drafts: [draft], source: source)
    }

    private func waitForDrafts(
        timeout: Duration = .seconds(3),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline { XCTFail("Timed out waiting for draft queue"); return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func testTransactionRowsHideNotesAndKeepOriginalAmountsInBothAppearances() throws {
        func transaction(note: String?) -> FinanceTransaction {
            FinanceTransaction(id: UUID(), accountId: UUID(), kind: .expense,
                amount: "2100", currency: "KZT", category: nil, note: note,
                occurredAt: LocalTestData.now, createdAt: LocalTestData.now, updatedAt: LocalTestData.now)
        }
        for scheme in [ColorScheme.light, .dark] {
            for typeSize in [DynamicTypeSize.large, .accessibility1] {
                func render(note: String?) throws -> UIImage {
                    let content = TransactionRow(transaction: transaction(note: note), account: nil,
                        secondaryAmountText: "-$5.00")
                        .padding(20)
                        .frame(width: 390)
                        .background(AppColor.elevatedSurface)
                        .environment(\.colorScheme, scheme)
                        .environment(\.dynamicTypeSize, typeSize)
                    return try XCTUnwrap(ImageRenderer(content: content).uiImage)
                }
                let image = try render(note: "This note must not appear below the row.")
                XCTAssertEqual(image.pngData(), try render(note: nil).pngData())
                let attachment = XCTAttachment(image: image)
                attachment.name = "Transaction conversion row \(scheme) \(typeSize)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    func testCameraControlsRenderInLightAndDarkIncludingSelectedDisabledAndLoading() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for scheme in [ColorScheme.light, .dark] {
            let content = VStack(spacing: 24) {
                HStack(spacing: 12) {
                    PrimaryIconButton("Scan", iconName: "camera", iconSize: 22, appearance: .glass, diameter: 48) {}
                    PrimaryIconButton("Add", iconName: "plus", appearance: .glass) {}
                }
                ForEach(0..<3) { state in
                    ReceiptCaptureControls(isTorchOn: state == 1, canUseTorch: state != 2,
                        canCapture: state != 2, isCapturing: state == 2, canChoosePhoto: state != 2,
                        canAttachDocument: state != 2,
                        onToggleTorch: {}, onCapture: {}, onChoosePhoto: {}, onAttachDocument: {})
                        .padding(.vertical, 24)
                        .background {
                            LinearGradient(colors: [.gray, .brown, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                        }
                }
            }
            .padding(24)
            .frame(width: 390)
            .background(AppColor.background)
            .preferredColorScheme(scheme)
            let controller = UIHostingController(rootView: content)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 760)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.frame = window.bounds
            try await Task.sleep(for: .milliseconds(300))
            controller.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Scan-controls-\(scheme)"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
        }
    }

    private final class ScanProtocol: URLProtocol {
        static var responseData = Data()
        static var statusCode = 200
        static var handler: ((URLRequest) -> (Int, Data))?
        static var responseSequence: [(Int, Data)] = []
        static var responseDelay: TimeInterval = 0
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let result: (Int, Data)
            if let handled = Self.handler?(request) {
                result = handled
            } else if !Self.responseSequence.isEmpty {
                result = Self.responseSequence.removeFirst()
            } else {
                result = (Self.statusCode, Self.responseData)
            }
            let respond = DispatchWorkItem {
                let response = HTTPURLResponse(url: self.request.url!, statusCode: result.0, httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"])!
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: result.1)
                self.client?.urlProtocolDidFinishLoading(self)
            }
            if Self.responseDelay > 0 {
                DispatchQueue.global().asyncAfter(deadline: .now() + Self.responseDelay, execute: respond)
            } else {
                respond.perform()
            }
        }
        override func stopLoading() {}
    }
}
