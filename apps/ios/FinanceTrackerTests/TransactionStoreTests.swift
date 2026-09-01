import XCTest
@testable import FinanceTracker

@MainActor
final class TransactionStoreTests: XCTestCase {
    func testCategoryIconCatalogHasRichDistinctGroups() {
        XCTAssertEqual(CategoryIconCatalog.groups.count, 11)
        XCTAssertTrue(CategoryIconCatalog.groups.allSatisfy { $0.icons.count >= 16 })
        XCTAssertEqual(Set(CategoryIconCatalog.choices).count, CategoryIconCatalog.choices.count)
    }

    func testExtendedCategoryColorsUseStableAPINames() throws {
        let colors: [(CategoryColor, String)] = [
            (.coral, "coral"),
            (.amber, "amber"),
            (.lime, "lime"),
            (.turquoise, "turquoise"),
            (.sky, "sky"),
            (.navy, "navy"),
            (.violet, "violet"),
            (.lavender, "lavender"),
            (.rose, "rose"),
            (.slate, "slate"),
        ]
        let encoder = JSONEncoder()

        for (color, expectedName) in colors {
            let encoded = try encoder.encode(color)
            XCTAssertEqual(String(decoding: encoded, as: UTF8.self), "\"\(expectedName)\"")
        }
    }

    func testCategoryAppearanceIsSentWhenCreatingAndEditing() async throws {
        let parentID = UUID()
        let createdCategory = category(
            parentID: parentID,
            icon: "cup.and.saucer.fill",
            color: .orange
        )
        let editedCategory = category(
            id: createdCategory.id,
            name: "Coffee runs",
            icon: "mug.fill",
            color: .brown
        )
        let session = makeSession { request in
            let body = try XCTUnwrap(requestBody(request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

            switch request.httpMethod {
            case "POST":
                XCTAssertEqual(json["name"] as? String, "Coffee")
                XCTAssertEqual(json["kind"] as? String, "expense")
                XCTAssertEqual(json["parentId"] as? String, parentID.uuidString)
                XCTAssertEqual(json["icon"] as? String, "cup.and.saucer.fill")
                XCTAssertEqual(json["color"] as? String, "orange")
                return (201, try self.encode(createdCategory))
            case "PATCH":
                XCTAssertEqual(request.url?.lastPathComponent, createdCategory.id.uuidString)
                XCTAssertEqual(json["name"] as? String, "Coffee runs")
                XCTAssertTrue(json["parentId"] is NSNull)
                XCTAssertEqual(json["icon"] as? String, "mug.fill")
                XCTAssertEqual(json["color"] as? String, "brown")
                return (200, try self.encode(editedCategory))
            default:
                XCTFail("Unexpected request method")
                return (405, Data())
            }
        }
        defer { session.invalidateAndCancel() }

        let store = TransactionStore(
            apiClient: APIClient(baseURL: URL(string: "https://test.invalid")!, session: session)
        )
        let created = try await store.createCategory(
            name: "Coffee",
            kind: .expense,
            parentID: parentID,
            icon: "cup.and.saucer.fill",
            color: .orange
        )
        let edited = try await store.updateCategory(
            created,
            name: "Coffee runs",
            parentID: nil,
            icon: "mug.fill",
            color: .brown
        )

        XCTAssertEqual(edited, editedCategory)
        XCTAssertEqual(store.categories, [editedCategory])
    }

    func testUpdateReplacesAndReordersTheExistingTransactionWithoutDuplicates() async throws {
        let accountID = UUID()
        let original = transaction(accountID: accountID, occurredAt: Date(timeIntervalSince1970: 1_700_000_000))
        let newer = transaction(accountID: accountID, occurredAt: Date(timeIntervalSince1970: 1_700_001_000))
        let edited = transaction(id: original.id, accountID: accountID, occurredAt: Date(timeIntervalSince1970: 1_700_002_000.123))
        let session = makeSession { request in
            if request.httpMethod == "GET" {
                return (200, try self.encode([newer, original]))
            }
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.url?.lastPathComponent, original.id.uuidString)
            let body = try XCTUnwrap(requestBody(request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["occurredAt"] as? String, "2023-11-14T22:46:40.123Z")
            XCTAssertNil(json["categoryId"])
            XCTAssertNil(json["description"])
            XCTAssertNil(json["note"])
            return (200, try self.encode(edited))
        }
        defer { session.invalidateAndCancel() }
        let store = TransactionStore(apiClient: APIClient(baseURL: URL(string: "https://test.invalid")!, session: session))
        await store.loadTransactions(accountID: nil)
        try await store.updateTransaction(id: original.id, with: draft(edited))

        XCTAssertEqual(store.transactions, [edited, newer])
        XCTAssertEqual(store.state, .loaded)
    }

    func testMovingTransactionOutOfSelectedAccountRemovesItsRow() async throws {
        let accountID = UUID()
        let original = transaction(accountID: accountID)
        let moved = transaction(id: original.id, accountID: UUID())
        let session = makeSession { request in
            if request.httpMethod == "GET" {
                XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, accountID.uuidString)
                return (200, try self.encode([original]))
            }
            return (200, try self.encode(moved))
        }
        defer { session.invalidateAndCancel() }
        let store = TransactionStore(apiClient: APIClient(baseURL: URL(string: "https://test.invalid")!, session: session))
        await store.loadTransactions(accountID: accountID)
        try await store.updateTransaction(id: original.id, with: draft(moved))

        XCTAssertTrue(store.transactions.isEmpty)
        XCTAssertEqual(store.state, .loaded)
    }

    func testFailedSaveLeavesOriginalTransactionUntouched() async throws {
        let original = transaction(accountID: UUID())
        let session = makeSession { request in
            if request.httpMethod == "GET" {
                return (200, try self.encode([original]))
            }
            return (500, Data(#"{"message":"Could not save changes"}"#.utf8))
        }
        defer { session.invalidateAndCancel() }
        let store = TransactionStore(apiClient: APIClient(baseURL: URL(string: "https://test.invalid")!, session: session))
        await store.loadTransactions(accountID: nil)

        do {
            try await store.updateTransaction(id: original.id, with: draft(original))
            XCTFail("Expected the update to fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Could not save changes")
        }
        XCTAssertEqual(store.transactions, [original])
    }

    private func transaction(
        id: UUID = UUID(), accountID: UUID, occurredAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> FinanceTransaction {
        FinanceTransaction(
            id: id, accountId: accountID, kind: .expense, amount: "12.5000", currency: "USD",
            category: nil, description: nil, note: nil, occurredAt: occurredAt,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000), updatedAt: Date(timeIntervalSince1970: 1_700_002_000)
        )
    }

    private func category(
        id: UUID = UUID(),
        name: String = "Coffee",
        parentID: UUID? = nil,
        icon: String,
        color: CategoryColor
    ) -> TransactionCategory {
        TransactionCategory(
            id: id,
            systemKey: nil,
            name: name,
            kind: .expense,
            parentId: parentID,
            icon: icon,
            color: color,
            isSystem: false,
            examples: [],
            sortOrder: 1_000,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func draft(_ transaction: FinanceTransaction) -> TransactionRequest {
        TransactionRequest(
            accountId: transaction.accountId, kind: transaction.kind, amount: transaction.amount,
            categoryId: nil, description: nil, note: nil, occurredAt: transaction.occurredAt
        )
    }

    nonisolated private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return try encoder.encode(value)
    }

    private func makeSession(
        handler: @escaping (URLRequest) throws -> (Int, Data)
    ) -> URLSession {
        TransactionTestProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TransactionTestProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class TransactionTestProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func requestBody(_ request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count > 0 else { break }
        data.append(buffer, count: count)
    }
    return data
}
