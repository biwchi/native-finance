import Foundation
import Combine
import Network
import BackgroundTasks
import UIKit

protocol SyncTransport: Sendable {
    func syncBootstrap() async throws -> SyncSnapshot
    func syncPush(_ mutation: SyncMutation) async throws -> SyncResult
    func syncChanges(cursor: String, generation: Int) async throws -> SyncSnapshot
}

/// The only upload/download worker. Stores never await this worker to complete a save.
