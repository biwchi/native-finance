struct HealthResponse: Decodable, Equatable, Sendable {
    let service: String
    let status: String
}

