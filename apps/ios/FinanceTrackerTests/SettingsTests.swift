import SwiftUI
import XCTest
@testable import FinanceTracker

@MainActor
final class SettingsTests: XCTestCase {
    func testDeleteRequestIncludesExactConfirmationAndWaitsForSuccess() async throws {
        let session = makeSession { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            XCTAssertEqual(request.url?.path, "/api/v1/settings/data")
            let body = try XCTUnwrap(Self.requestBody(request))
            let json = try JSONDecoder().decode([String: String].self, from: body)
            XCTAssertEqual(json, ["confirmation": "confirm"])
            return (200, Data(#"{"deleted":true}"#.utf8))
        }
        defer { session.invalidateAndCancel() }
        try await APIClient(baseURL: URL(string: "https://test.invalid")!, session: session)
            .deleteAllData(confirmation: "confirm")
    }

    func testDeleteFailuresAreNotTreatedAsSuccess() async throws {
        for (status, body) in [(500, #"{"message":"Try again"}"#), (200, #"{"deleted":false}"#), (200, "{}"), (200, "")] {
            let session = makeSession { _ in (status, Data(body.utf8)) }
            defer { session.invalidateAndCancel() }
            do {
                try await APIClient(baseURL: URL(string: "https://test.invalid")!, session: session)
                    .deleteAllData(confirmation: "confirm")
                XCTFail("Expected deletion to fail")
            } catch {
                XCTAssertFalse(error.localizedDescription.isEmpty)
            }
        }
    }

    func testSettingsAndDeletionRenderInLightAndDark() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        for scheme in [ColorScheme.light, .dark] {
            let suite = "SettingsRendering-\(UUID())"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set((scheme == .dark ? AppTheme.dark : .light).rawValue, forKey: AppPreferences.themeKey)
            for selected in [false, true] {
                defaults.set(selected, forKey: AppPreferences.roundTotalsKey)
                if selected { defaults.set(false, forKey: AppPreferences.useAllocatedBudgetForSummaryKey) }
                defaults.set(selected ? 2 : 0, forKey: AppPreferences.firstWeekdayKey)
                if selected { defaults.set(7, forKey: AppPreferences.recurringReminderDaysKey) }
                try await capture(NavigationStack { SettingsView() }.environmentObject(TransactionStore()).defaultAppStorage(defaults),
                                  name: "Settings-\(scheme)-\(selected ? "selected" : "default")",
                                  scheme: scheme, scene: scene, height: 1600)
            }
            try await capture(DeleteDataConfirmationView(
                title: "Delete all data",
                explanation: "Permanently delete all accounts, transactions, recurring payments, debts, categories, and budgets in this workspace.",
                delete: { _ in XCTFail("Rendering must never delete data") }
            ), name: "Deletion-disabled-\(scheme)", scheme: scheme, scene: scene, height: 844)
        }
    }

    private func capture<Content: View>(_ content: Content, name: String, scheme: ColorScheme,
                                       scene: UIWindowScene, height: CGFloat) async throws {
        let controller = UIHostingController(rootView: content.tint(AppColor.accent).preferredColorScheme(scheme))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: height)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        controller.view.frame = window.bounds
        try await Task.sleep(for: .milliseconds(300))
        controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(size: window.bounds.size).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func makeSession(handler: @escaping (URLRequest) throws -> (Int, Data)) -> URLSession {
        SettingsTestProtocol.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SettingsTestProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func requestBody(_ request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class SettingsTestProtocol: URLProtocol {
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
