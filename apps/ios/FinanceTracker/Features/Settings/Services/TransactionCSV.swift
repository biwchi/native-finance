import Foundation

/// The CSV boundary is local and deterministic. Reading a table never writes records.
enum TransactionCSV {
    static let maximumBytes = 5 * 1_024 * 1_024
    static let maximumTransactions = 5_000
    static let columns = ["date", "type", "amount", "currency", "account", "category", "note", "recipient", "counterparty"]
    static let requiredColumns = ["date", "type", "amount", "account"]

    struct ImportError: LocalizedError {
        let problems: [String]
        var errorDescription: String? { problems.joined(separator: "\n") }
    }

    static func readFile(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw failure("Choose a CSV file smaller than 5 MB.") }
        return data
    }

    static func decode(_ data: Data, accounts: [Account], categories: [TransactionCategory], debts: [Debt], timeZone: TimeZone = .current) throws -> [QuickEntryDraft] {
        guard data.count <= maximumBytes else { throw failure("Choose a CSV file smaller than 5 MB.") }
        guard var text = String(data: data, encoding: .utf8) else { throw failure("Save the table as a UTF-8 CSV file.") }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        let rows = try parse(text)
        guard let first = rows.first else { throw failure("The file is empty. Include a header row and at least one transaction.") }
        let headers = first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard Set(headers).count == headers.count else { throw failure("Each column header must appear only once.") }
        let missing = requiredColumns.filter { !headers.contains($0) }
        guard missing.isEmpty else { throw failure("Missing columns: \(missing.joined(separator: ", ")). Use commas between columns.") }
        let unknown = headers.filter { !columns.contains($0) }
        guard unknown.isEmpty else { throw failure("Unknown columns: \(unknown.joined(separator: ", ")). See Import help for supported headers.") }
        guard rows.count > 1 else { throw failure("The file has headers but no transactions.") }
        guard rows.count - 1 <= maximumTransactions else { throw failure("Import up to 5,000 transactions at a time. Split this table into smaller files.") }
        var drafts: [QuickEntryDraft] = []
        var problems: [String] = []
        for (offset, row) in rows.dropFirst().enumerated() {
            do {
                guard row.count == headers.count else { throw failure("Expected \(headers.count) columns, found \(row.count). Quote text that contains commas.") }
                let values = Dictionary(uniqueKeysWithValues: zip(headers, row.map(unprotect)))
                func value(_ key: String) -> String { (values[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
                let account = try resolve(value("account"), in: accounts, name: { $0.name }, label: "account")
                guard let kind = TransactionKind(rawValue: value("type").lowercased()) else { throw failure("Type must be expense, income, or debt.") }
                let amount = value("amount")
                guard amount.range(of: "^-?(?:0|[1-9][0-9]{0,14})(?:\\.[0-9]{1,4})?$", options: .regularExpression) != nil,
                      let number = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")), number != 0 else {
                    throw failure("Amount must be non-zero, with a decimal point and up to four decimal places. Do not include currency symbols or thousands separators.")
                }
                let normalizedAmount = amount.hasPrefix("-") ? String(amount.dropFirst()) : amount
                guard let date = date(value("date"), timeZone: timeZone) else { throw failure("Date must be YYYY-MM-DD or an ISO 8601 date and time with a time zone.") }
                let currency = value("currency").isEmpty ? account.currency : value("currency").uppercased()
                guard currency.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil else { throw failure("Currency must be a three-letter code, such as USD.") }
                var category: TransactionCategory?
                if !value("category").isEmpty {
                    guard kind != .debt else { throw failure("Debt rows cannot have a category.") }
                    category = try resolve(value("category"), in: categories.filter { $0.kind == kind }, name: { categoryName($0, categories: categories) }, label: "category")
                }
                var debt: Debt?
                if kind == .debt { debt = try resolve(value("recipient"), in: debts, name: { $0.name }, label: "recipient") }
                else if !value("recipient").isEmpty { throw failure("Only debt rows can have a recipient.") }
                for (key, limit) in [("counterparty", 2000), ("note", 2000)] where value(key).count > limit {
                    throw failure("\(key.capitalized) must be \(limit) characters or fewer.")
                }
                func optional(_ key: String) -> String? { value(key).isEmpty ? nil : value(key) }
                drafts.append(QuickEntryDraft(record: TransactionRequest(
                    accountId: account.id, kind: kind, amount: normalizedAmount, categoryId: category?.id, note: optional("note"),
                    occurredAt: date, debtId: debt?.id, currency: currency,
                    counterparty: optional("counterparty")
                ), category: category, debt: debt))
            } catch {
                problems.append("Row \(offset + 2): \(error.localizedDescription)")
                if problems.count == 20 { problems.append("Fix these rows, then choose the file again to check the rest."); break }
            }
        }
        guard problems.isEmpty else { throw ImportError(problems: problems) }
        return drafts
    }

    static func filtered(_ transactions: [FinanceTransaction], accountID: UUID?, start: Date?, end: Date?, calendar: Calendar = .current) -> [FinanceTransaction] {
        let lower = start.map { calendar.startOfDay(for: $0) }
        let upper = end.flatMap { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) }
        return transactions.filter {
            (accountID == nil || $0.accountId == accountID) && (lower == nil || $0.occurredAt >= lower!) && (upper == nil || $0.occurredAt < upper!)
        }.sorted { ($0.occurredAt, $0.id.uuidString) < ($1.occurredAt, $1.id.uuidString) }
    }

    static func encode(_ transactions: [FinanceTransaction], accounts: [Account], categories: [TransactionCategory], debts: [Debt]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var rows = [columns]
        for transaction in transactions {
            let account = accounts.first { $0.id == transaction.accountId }
            let category = transaction.category
            let debt = transaction.debt
            rows.append([
                formatter.string(from: transaction.occurredAt), transaction.kind.rawValue, transaction.amount, transaction.currency,
                account.map { reference($0, in: accounts, name: { $0.name }) } ?? transaction.accountId.uuidString,
                category.map { reference($0, in: categories.filter { $0.kind == transaction.kind }, name: { categoryName($0, categories: categories) }) } ?? "",
                transaction.note ?? "",
                debt.map { reference($0, in: debts, name: { $0.name }) } ?? transaction.debtId?.uuidString ?? "",
                transaction.counterparty ?? ""
            ])
        }
        return rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    static func template(account: Account?) -> String {
        [columns, ["2026-01-15", "expense", "12.50", account?.currency ?? "USD", account?.id.uuidString ?? "Main", "", "Morning coffee", "", "Coffee shop"]]
            .map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    private static func resolve<T: Identifiable>(_ value: String, in items: [T], name: (T) -> String, label: String) throws -> T where T.ID == UUID {
        if let id = UUID(uuidString: value), let item = items.first(where: { $0.id == id }) { return item }
        let matches = items.filter { name($0).caseInsensitiveCompare(value) == .orderedSame }
        guard matches.count == 1 else {
            throw failure(matches.isEmpty ? "Unknown \(label) \"\(value)\". Use an existing name or ID." : "More than one \(label) is named \"\(value)\". Use its ID or rename it before importing.")
        }
        return matches[0]
    }

    private static func reference<T: Identifiable>(_ item: T, in items: [T], name: (T) -> String) -> String where T.ID == UUID {
        let value = name(item)
        return items.filter { name($0).caseInsensitiveCompare(value) == .orderedSame }.count == 1 && UUID(uuidString: value) == nil ? value : item.id.uuidString
    }

    private static func categoryName(_ category: TransactionCategory, categories: [TransactionCategory]) -> String {
        guard let parent = categories.first(where: { $0.id == category.parentId }) else { return category.name }
        return "\(parent.name) › \(category.name)"
    }

    private static func date(_ value: String, timeZone: TimeZone) -> Date? {
        if value.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.isLenient = false
            guard let result = formatter.date(from: value), formatter.string(from: result) == value else { return nil }
            return result
        }
        guard value.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}T(?:[01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](?:\\.[0-9]{1,9})?(?:Z|[+-](?:[01][0-9]|2[0-3]):[0-5][0-9])$", options: .regularExpression) != nil,
              date(String(value.prefix(10)), timeZone: TimeZone(secondsFromGMT: 0)!) != nil else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    /// Prefix spreadsheet formulas and literal apostrophes. Import reverses this convention.
    private static func needsProtection(_ value: String) -> Bool {
        guard let first = value.trimmingCharacters(in: .whitespacesAndNewlines).first else { return false }
        return "=+-@'".contains(first)
    }

    private static func escape(_ value: String) -> String {
        let safe = needsProtection(value) ? "'" + value : value
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func unprotect(_ value: String) -> String {
        guard value.first == "'", needsProtection(String(value.dropFirst())) else { return value }
        return String(value.dropFirst())
    }

    private static func failure(_ message: String) -> ImportError { ImportError(problems: [message]) }

    private static func parse(_ text: String) throws -> [[String]] {
        enum State { case plain, quoted, closed }
        var state = State.plain
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        func finishRow() throws {
            row.append(field)
            if row.count > 1 || !field.trimmingCharacters(in: .whitespaces).isEmpty { rows.append(row) }
            guard rows.count <= maximumTransactions + 1 else { throw failure("Import up to 5,000 transactions at a time. Split this table into smaller files.") }
            row = []; field = ""
        }
        for character in text {
            if state == .quoted {
                if character == "\"" { state = .closed } else { field.append(character) }
            } else if character == "\"" {
                if state == .closed { field.append(character); state = .quoted }
                else if field.isEmpty { state = .quoted }
                else { throw failure("Row \(rows.count + 1): A quote inside text must be doubled and the field enclosed in quotes.") }
            } else if character == "," {
                row.append(field); field = ""; state = .plain
            } else if character == "\n" || character == "\r" || character == "\r\n" {
                try finishRow(); state = .plain
            } else {
                guard state != .closed else { throw failure("Row \(rows.count + 1): Unexpected text after a closing quote.") }
                field.append(character)
            }
        }
        guard state != .quoted else { throw failure("Row \(rows.count + 1): A quoted field is missing its closing quote.") }
        if !row.isEmpty || !field.isEmpty || state == .closed { try finishRow() }
        return rows
    }
}
