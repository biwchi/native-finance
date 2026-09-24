import SwiftUI
import UniformTypeIdentifiers

struct SyncReviewView: View {
    @ObservedObject var repository: LocalFinanceRepository = .shared
    @State private var items: [SyncReviewItem] = []
    @State private var errorMessage: String?
    @State private var discardItem: SyncReviewItem?
    @State private var decisionRevision: Int = 0
    @State private var exportDocument = SyncReviewExportDocument(data: Data())
    @State private var showsExport = false
    @State private var remoteReset = false

    var body: some View {
        AppList {
            if remoteReset {
                AppSection {
                    Text("The data on your other devices was reset. Your work on this iPhone is still saved.")
                    Text("Keeping this device’s data restores it to your other devices. Using the reset data removes this device’s pending changes.").foregroundStyle(.secondary)
                    Button("Keep this device’s data") { resolveReset(keepLocal: true) }
                    Button("Use the reset data", role: .destructive) { resolveReset(keepLocal: false) }
                }
            } else {
                ForEach(items) { item in
                    AppSection {
                        Text(item.message)
                        ForEach(item.rows) { row in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(row.title).font(.headline)
                                Text("On this iPhone").font(.subheadline).foregroundStyle(.secondary)
                                Text(details(row.savedData))
                                if row.synced != nil {
                                    Text("Synced copy").font(.subheadline).foregroundStyle(.secondary)
                                    Text(details(row.synced))
                                } else {
                                    Text(row.syncedAbsence).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Button("Export saved changes") { export(item.id) }
                        if !item.hasMissingReference {
                            Button(item.hasKnownDifference ? "Use changes from this iPhone" : "Try syncing again") { resolve(item.id, keepLocal: true) }
                        }
                        Button(role: .destructive) {
                            decisionRevision = repository.snapshot.revision
                            discardItem = item
                        } label: {
                            Text("Discard these changes…").foregroundStyle(AppColor.destructiveText)
                        }
                    }
                }
                if items.isEmpty && errorMessage == nil {
                    Text("No changes need review.").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Review changes")
        .task { load(); SyncCoordinator.shared.requestSync() }
        .onChange(of: repository.snapshot.revision) { _, _ in load() }
        .appSheet(item: $discardItem) { item in
            NavigationStack {
                AppList {
                    AppSection {
                        Text("Discard the saved changes below?")
                        Text("Their synced copies will be used where available. Entries that have never synced will be removed from this iPhone.").foregroundStyle(.secondary)
                    }
                    ForEach(item.rows) { row in
                        AppSection {
                            Text(row.title).font(.headline)
                            Text(details(row.savedData))
                            Text(row.synced == nil ? row.syncedAbsence : "Will use: \(details(row.synced))").foregroundStyle(.secondary)
                        }
                    }
                    AppSection {
                        Button(role: .destructive) {
                            discardItem = nil
                            guard repository.snapshot.revision == decisionRevision else {
                                errorMessage = "Your saved changes have updated. Review them again before discarding."
                                return
                            }
                            resolve(item.id, keepLocal: false)
                        } label: {
                            Text("Discard these changes").foregroundStyle(AppColor.destructiveText)
                        }
                    }
                }
                .navigationTitle("Discard changes")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { discardItem = nil }
                            .legacyToolbarControl()
                    }
                }
            }
        }
        .fileExporter(isPresented: $showsExport, document: exportDocument, contentType: .json, defaultFilename: "Saved finance changes") { result in
            if case .failure(let error) = result { errorMessage = error.localizedDescription }
        }
        .alert("Couldn’t complete this action", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    private func load() {
        do {
            remoteReset = try repository.value(SyncSnapshot.self, key: "remoteReset") != nil
            items = try repository.syncReviewItems()
        } catch { errorMessage = error.localizedDescription }
    }
    private func export(_ id: UUID) {
        do {
            exportDocument = SyncReviewExportDocument(data: try repository.exportSyncReview(id))
            showsExport = true
        } catch { errorMessage = error.localizedDescription }
    }
    private func details(_ data: [String: JSONValue]?) -> String {
        guard let data else { return "Removed on this iPhone" }
        var lines: [String] = []
        if let name = data["counterparty"]?.string, !name.isEmpty {
            lines.append("Person or business: \(name)")
        }
        for (key, label) in [("name", "Name"), ("kind", "Type"), ("initialBalance", "Initial balance"), ("amount", "Amount"), ("currency", "Currency"), ("monthlyLimit", "Monthly limit"), ("note", "Note"), ("frequency", "Repeats"), ("month", "Month")] {
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

    private func resolve(_ id: UUID, keepLocal: Bool) {
        do { try repository.resolve(id, keepLocal: keepLocal) } catch { errorMessage = error.localizedDescription }
    }
    private func resolveReset(keepLocal: Bool) {
        do { try repository.resolveWorkspaceReset(keepLocal: keepLocal) } catch { errorMessage = error.localizedDescription }
    }
}

private struct SyncReviewExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
