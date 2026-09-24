import Foundation

struct SyncReviewItem: Identifiable {
    let id: UUID
    let rows: [SyncReviewRow]
    let hasMissingReference: Bool
    let hasKnownDifference: Bool
    let operationCount: Int

    var message: String {
        if hasMissingReference {
            return "Some saved changes refer to an account or item that is no longer available. Your changes are still on this iPhone."
        }
        if hasKnownDifference {
            return "These changes differ from the synced copy. Review the saved details before choosing which to use."
        }
        return "These changes haven’t finished syncing. Your saved details are still on this iPhone."
    }
}

struct SyncReviewRow: Identifiable, Codable {
    let entity: String
    let key: String
    let local: [String: JSONValue]?
    let synced: [String: JSONValue]?
    let syncedVersion: String?
    let checkedAbsence: Bool
    let submitted: [String: JSONValue]?
    let queuedDeletion: Bool
    var id: String { "\(entity):\(key)" }
    var savedData: [String: JSONValue]? { local ?? (queuedDeletion ? nil : submitted) }
    var title: String {
        let data = local ?? synced ?? submitted
        return data?["name"]?.string ?? data?["counterparty"]?.string
            ?? data?["note"]?.string ?? (entity == "schedule" ? "Recurring payment" : entity.capitalized)
    }
    var syncedAbsence: String {
        if syncedVersion != nil { return "Removed from the synced data" }
        return checkedAbsence ? "Not saved on other devices" : "No synced copy available yet"
    }
}

/// A decision must include every dependent operation, including shared descendants.
func syncReviewGroups(_ queue: [PendingMutation]) -> [[PendingMutation]] {
    var groups: [Set<UUID>] = []
    for root in queue where root.issue != nil {
        var members: Set<UUID> = [root.id]
        var previousCount = 0
        while members.count != previousCount {
            previousCount = members.count
            for item in queue where !members.isDisjoint(with: item.dependencies) { members.insert(item.id) }
        }
        var index = 0
        while index < groups.count {
            if !members.isDisjoint(with: groups[index]) { members.formUnion(groups.remove(at: index)); index = 0 }
            else { index += 1 }
        }
        groups.append(members)
    }
    return groups.map { ids in queue.filter { ids.contains($0.id) } }
        .sorted { left, right in
            (queue.firstIndex { $0.id == left[0].id } ?? 0) < (queue.firstIndex { $0.id == right[0].id } ?? 0)
        }
}

func latestSyncChanges(_ group: [PendingMutation]) -> [SyncChange] {
    var latest: [String: SyncChange] = [:]
    for item in group { for change in item.mutation.changes { latest[change.identity] = change } }
    return latest.values.sorted { $0.identity < $1.identity }
}
