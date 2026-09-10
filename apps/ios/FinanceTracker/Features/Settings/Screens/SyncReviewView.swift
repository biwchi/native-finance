import SwiftUI

struct SyncReviewView: View {
    @ObservedObject private var repository = LocalFinanceRepository.shared
    @State private var errorMessage: String?
    var body: some View {
        AppList {
            if (try? repository.value(SyncSnapshot.self, key: "remoteReset")) != nil {
                AppSection {
                    Text("This workspace was reset on the server. Your work on this iPhone is still saved.")
                    Text("Keeping this device’s data restores it to the server. Accepting server data discards this device’s pending changes.").foregroundStyle(.secondary)
                    Button("Keep this device’s data") { resolveReset(keepLocal: true) }
                    Button("Accept server data", role: .destructive) { resolveReset(keepLocal: false) }
                }
            } else {
                ForEach(repository.snapshot.pending.filter { $0.issue != nil }) { item in
                    AppSection {
                        Text(item.issue ?? "Review this change")
                        ForEach(item.mutation.changes, id: \.identity) { change in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(title(change)).font(.headline)
                                Text("Your version: \(details(try? repository.localVersion(entity: change.entity, key: change.key)))")
                                Text("Server version: \(serverDetails(change))").foregroundStyle(.secondary)
                            }
                        }
                        Button("Keep local changes") { resolve(item.id, keepLocal: true) }
                        Button("Accept server version", role: .destructive) { resolve(item.id, keepLocal: false) }
                    } footer: {
                        Text("Accepting the server version also discards pending changes that depend on this operation.")
                    }
                }
                if !repository.snapshot.pending.contains(where: { $0.issue != nil }) {
                    Text("No changes need review.").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Review changes")
        .alert("Couldn’t save your decision", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }
    private func title(_ change: SyncChange) -> String {
        change.data?["name"]?.string ?? change.data?["note"]?.string ?? change.entity.capitalized
    }
    private func details(_ data: [String: JSONValue]?) -> String {
        guard let data else { return "Deleted" }
        var lines: [String] = []
        for (key, label) in [("name", "Name"), ("kind", "Type"), ("type", "Account type"), ("amount", "Amount"), ("currency", "Currency"), ("monthlyLimit", "Monthly limit"), ("merchant", "Merchant"), ("payee", "Payee"), ("note", "Note"), ("frequency", "Repeats"), ("month", "Month")] {
            if let value = data[key]?.string { lines.append("\(label): \(value)") }
        }
        for (key, label) in [("occurredAt", "Date"), ("startAt", "Starts"), ("endAt", "Ends"), ("nextOccurrenceAt", "Next payment")] {
            if let value = data[key]?.string { lines.append("\(label): \(value.prefix(10))") }
        }
        for (key, label) in [("accountId", "Account"), ("categoryId", "Category"), ("parentId", "Parent category"), ("debtId", "Recipient")] {
            guard let value = data[key]?.string, let id = UUID(uuidString: value) else { continue }
            let name = repository.snapshot.accounts[id]?.name ?? repository.snapshot.categories[id]?.name ?? repository.snapshot.debts[id]?.name ?? "Removed"
            lines.append("\(label): \(name)")
        }
        if case .array(let groups) = data["groups"] {
            for case .object(let group) in groups { lines.append("\(group["name"]?.string ?? "Group"): \(group["limit"]?.string ?? "No limit")") }
        }
        if case .array(let assignments) = data["categoryAssignments"] {
            for case .object(let assignment) in assignments {
                let category = assignment["categoryId"]?.string.flatMap(UUID.init(uuidString:)).flatMap { repository.snapshot.categories[$0]?.name } ?? "Category"
                lines.append("\(category): \(assignment["limit"]?.string ?? "Group limit")")
            }
        }
        return lines.isEmpty ? "Saved change" : lines.joined(separator: "\n")
    }

    private func serverDetails(_ change: SyncChange) -> String {
        details(try? repository.serverVersion(entity: change.entity, key: change.key))
    }
    private func resolve(_ id: UUID, keepLocal: Bool) {
        do { try repository.resolve(id, keepLocal: keepLocal) } catch { errorMessage = error.localizedDescription }
    }
    private func resolveReset(keepLocal: Bool) {
        do { try repository.resolveWorkspaceReset(keepLocal: keepLocal) } catch { errorMessage = error.localizedDescription }
    }
}
