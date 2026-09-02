import XCTest
@testable import FinanceTracker

@MainActor
final class AccountStoreTests: XCTestCase {
    func testReorderSendsEveryAccountIDAndKeepsServerOrder() async throws {
        let first = account(name: "First")
        let second = account(name: "Second")
        let third = account(name: "Third")
        let reordered = [third, first, second]
        let session = makeSession { request in
            if request.httpMethod == "GET" {
                return (200, try self.encode([first, second, third]))
            }

            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/v1/accounts/order")
            let body = try XCTUnwrap(requestBody(request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(
                json["accountIds"] as? [String],
                reordered.map { $0.id.uuidString }
            )
            return (200, try self.encode(reordered))
        }
        defer { session.invalidateAndCancel() }

        let store = makeStore(session: session)
        await store.loadAccounts()
        try await store.reorderAccounts(reordered)

        XCTAssertEqual(store.accounts, reordered)
    }

    func testFailedReorderRestoresThePreviousOrder() async throws {
        let first = account(name: "First")
        let second = account(name: "Second")
        let session = makeSession { request in
            if request.httpMethod == "GET" {
                return (200, try self.encode([first, second]))
            }
            return (500, Data(#"{"message":"Could not reorder accounts"}"#.utf8))
        }
        defer { session.invalidateAndCancel() }

        let store = makeStore(session: session)
        await store.loadAccounts()

        do {
            try await store.reorderAccounts([second, first])
            XCTFail("Expected reordering to fail")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Could not reorder accounts")
        }
        XCTAssertEqual(store.accounts, [first, second])
    }

    func testDeletingSelectedAccountClearsTheSelection() async throws {
        let first = account(name: "First")
        let second = account(name: "Second")
        let session = makeSession { request in
            if request.httpMethod == "GET" {
                return (200, try self.encode([first, second]))
            }

            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.lastPathComponent, first.id.uuidString)
            return (200, Data(#"{"deleted":true}"#.utf8))
        }
        defer { session.invalidateAndCancel() }

        let store = makeStore(session: session)
        await store.loadAccounts()
        store.selectedAccountID = first.id
        try await store.deleteAccount(first)

        XCTAssertEqual(store.accounts, [second])
        XCTAssertNil(store.selectedAccountID)
    }

    private func makeStore(session: URLSession) -> AccountStore {
        AccountStore(
            apiClient: APIClient(
                baseURL: URL(string: "https://test.invalid")!,
                session: session
            )
        )
    }

    private func account(name: String) -> Account {
        Account(
            id: UUID(),
            name: name,
            type: .checking,
            currency: "USD",
            icon: "creditcard.fill",
            iconColor: .blue,
            createdAt: "2026-09-02T00:00:00Z",
            updatedAt: "2026-09-02T00:00:00Z"
        )
    }

    nonisolated private func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    private func makeSession(
        handler: @escaping (URLRequest) throws -> (Int, Data)
    ) -> URLSession {
        AccountTestProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AccountTestProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class AccountTestProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil
            )!
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
