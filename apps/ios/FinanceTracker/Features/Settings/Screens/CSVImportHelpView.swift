import SwiftUI
import UniformTypeIdentifiers

struct CSVImportHelpView: View {
    @Environment(\.dismiss) private var dismiss
    var exampleAccount: Account?
    @State private var showsExporter = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            AppForm {
                AppSection {
                    Text("Save your spreadsheet as CSV with UTF-8 encoding and commas between columns. The first row must contain these column names. Columns can be in any order.")
                }
                AppSection("Required columns") {
                    help("date", "Use YYYY-MM-DD, such as 2026-01-15, for a date in your device’s time zone. For an exact time, use 2026-01-15T14:30:00+05:00 or 2026-01-15T09:30:00Z.")
                    help("type", "expense, income, or debt.")
                    help("amount", "A non-zero number, such as 12.50 or -12.50. Use a decimal point, up to four decimal places, and no currency symbols or thousands separators. The type determines whether it is an expense or income; a leading minus is ignored.")
                    help("account", "An existing account name or ID. Names ignore letter case. If accounts share a name, use the ID from an export or rename the accounts.")
                }
                AppSection("Optional columns") {
                    help("currency", "A three-letter code, such as USD or KZT. If empty, use the account currency. Amounts are saved as entered without conversion.")
                    help("category", "An existing category matching the transaction type, or its ID. For subcategories, use Parent › Child. Leave empty for uncategorized transactions. Debt rows must leave this empty.")
                    help("counterparty", "A person or business, up to 2,000 characters.")
                    help("note", "Additional details, up to 2,000 characters.")
                    help("recipient", "Required for debt rows. Use an existing debt recipient’s name or ID. Leave empty for expenses and income.")
                }
                AppSection("Example table") {
                    ScrollView(.horizontal) {
                        Text(TransactionCSV.template(account: exampleAccount))
                            .font(.system(.footnote, design: .monospaced))
                            .fixedSize(horizontal: true, vertical: false)
                            .textSelection(.enabled)
                    }
                    Button("Save example CSV") { showsExporter = true }
                }
                AppSection("Before you submit") {
                    Text("Create accounts, categories, and recipients before importing. Unknown or ambiguous names show a row error. Nothing is added until the file is valid and you press Submit in the review.")
                    Text("Each row adds one transaction. Existing transactions are never replaced. Importing a file again creates duplicates, so remove any rows you have already added.")
                    Text("Exports use this same format. Recurring payments import as individual transactions without schedules. Transfers use two rows, an expense from one account and an income into the other.")
                    Text("Put text containing commas, quotes, or line breaks inside double quotes. Double any quote inside the text. Exports add an apostrophe before text that a spreadsheet could read as a formula; importing removes that protection.")
                }
            }
            .navigationTitle("Import help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.legacyToolbarControl()
                }
            }
            .fileExporter(isPresented: $showsExporter, document: CSVDocument(text: TransactionCSV.template(account: exampleAccount)), contentType: .commaSeparatedText, defaultFilename: "transactions-example") { result in
                if case .failure(let error) = result { errorMessage = error.localizedDescription }
            }
            .alert("Couldn’t save example", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func help(_ column: String, _ description: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.extraSmall) {
            Text(column).font(.system(.body, design: .monospaced).weight(.semibold))
            Text(description).foregroundStyle(.secondary)
        }
    }
}
