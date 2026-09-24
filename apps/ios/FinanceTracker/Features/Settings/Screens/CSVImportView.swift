import SwiftUI
import UniformTypeIdentifiers

struct CSVImportView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore
    @State private var showsImporter = false
    @State private var showsHelp = false
    @State private var isReading = false
    @State private var review: QuickEntryReviewPresentation?
    @State private var problems: [String] = []
    @State private var didImport = false

    var body: some View {
        AppForm {
            AppSection {
                Text("Choose a CSV file, review every transaction, then press Submit to add them.")
                Text("Files are read on this device. No AI connection is needed.")
                    .foregroundStyle(.secondary)
                if accountStore.accounts.isEmpty {
                    Text("Create an account before importing transactions.")
                        .foregroundStyle(.secondary)
                }
            }
            if didImport {
                AppSection {
                    Label("Transactions imported", icon: "checkmark")
                    Text("Your transactions are saved on this device.").foregroundStyle(.secondary)
                }
            }
            if !problems.isEmpty {
                AppSection {
                    ForEach(Array(problems.enumerated()), id: \.offset) { _, problem in
                        Text(problem).textSelection(.enabled)
                    }
                } header: {
                    Text("Check your CSV")
                } footer: {
                    Text("Nothing was added. Fix the table and choose the file again.")
                }
            }
            AppSection {
                Button("View required columns and example") { showsHelp = true }
            } footer: {
                Text("UTF-8 CSV, up to 5 MB and 5,000 transactions per file. Accounts, categories, and debt recipients must already exist.")
            }
        }
        .navigationTitle("Import CSV")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsHelp = true } label: { AppIcon("information-circle", size: 22) }
                    .accessibilityLabel("Import help")
                    .legacyToolbarIcon()
            }
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryActionButton("Choose CSV file", isLoading: isReading) { showsImporter = true }
                .disabled(isReading || accountStore.accounts.isEmpty)
                .padding(.horizontal, AppSpacing.medium)
                .padding(.vertical, AppSpacing.small)
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            switch result {
            case .success(let url): read(url)
            case .failure(let error): problems = [error.localizedDescription]
            }
        }
        .appSheet(isPresented: $showsHelp) {
            CSVImportHelpView(exampleAccount: accountStore.accounts.first)
        }
        .appSheet(item: $review) { presentation in
            QuickEntryReviewView(presentation: presentation) { didImport = true }
                .presentationDetents([.large])
        }
    }

    private func read(_ url: URL) {
        let accounts = accountStore.accounts
        let categories = transactionStore.categories
        let debts = transactionStore.debts
        isReading = true
        problems = []
        didImport = false
        Task {
            defer { isReading = false }
            do {
                let drafts = try await Task.detached(priority: .userInitiated) {
                    try TransactionCSV.decode(TransactionCSV.readFile(url), accounts: accounts, categories: categories, debts: debts)
                }.value
                review = QuickEntryReviewPresentation(prompt: url.lastPathComponent, drafts: drafts, source: .csv)
            } catch let error as TransactionCSV.ImportError {
                problems = error.problems
            } catch {
                problems = [error.localizedDescription]
            }
        }
    }
}
