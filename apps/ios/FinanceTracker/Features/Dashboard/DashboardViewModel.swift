import Combine
import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case connected(service: String)
        case failed(message: String)
    }

    @Published private(set) var state: State = .idle

    private let apiClient: APIClient

    init(apiClient: APIClient = APIClient()) {
        self.apiClient = apiClient
    }

    func checkBackend() async {
        state = .loading

        do {
            let health = try await apiClient.health()
            state = .connected(service: health.service)
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }
}
