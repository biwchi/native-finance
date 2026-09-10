import Foundation

struct LocalEditor {
    var snapshot: LocalSnapshot
    let now: Date
    var changes: [String: SyncChange] = [:]
    var recurrenceActions: [SyncRecurrenceAction] = []
    var metadataChanges: [String: JSONValue] = [:]

    mutating func put<T: Encodable>(_ entity: String, key: String, _ value: T) throws {
        let data = try LocalJSON.object(value)
        let key = key.lowercased()
        changes["\(entity):\(key)"] = SyncChange(entity: entity, key: key, data: data)
        switch entity {
        case "account": let v = try LocalJSON.decode(Account.self, data); snapshot.accounts[v.id] = v
        case "category": let v = try LocalJSON.decode(TransactionCategory.self, data); snapshot.categories[v.id] = v
        case "debt": let v = try LocalJSON.decode(Debt.self, data); snapshot.debts[v.id] = v
        case "transaction": let v = try LocalJSON.decode(StoredTransaction.self, data); snapshot.transactions[v.id] = v
        case "schedule": let v = try LocalJSON.decode(StoredSchedule.self, data); snapshot.schedules[v.id] = v
        case "exclusion": let v = try LocalJSON.decode(StoredExclusion.self, data); snapshot.exclusions[v.id] = v
        case "budget": snapshot.budgets[key] = try LocalJSON.decode(MonthlyBudget.self, data)
        default: break
        }
    }
    mutating func erase(_ entity: String, key: String) {
        let key = key.lowercased()
        changes["\(entity):\(key)"] = SyncChange(entity: entity, key: key, data: nil)
        if entity == "budget" { snapshot.budgets.removeValue(forKey: key); return }
        guard let id = UUID(uuidString: key) else { return }
        switch entity {
        case "account": snapshot.accounts.removeValue(forKey: id)
        case "category": snapshot.categories.removeValue(forKey: id)
        case "debt": snapshot.debts.removeValue(forKey: id)
        case "transaction": snapshot.transactions.removeValue(forKey: id)
        case "schedule": snapshot.schedules.removeValue(forKey: id)
        case "exclusion": snapshot.exclusions.removeValue(forKey: id)
        default: break
        }
    }
    func name(_ value: String, limit: Int) throws -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= limit else { throw LocalDataError(message: "Enter a name of 1–\(limit) characters.") }
        return value
    }
    func amount(_ value: String) throws -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")
        guard value.range(of: "^(?:0|[1-9][0-9]{0,14})(?:\\.[0-9]{1,4})?$", options: .regularExpression) != nil,
              let parsed = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")), parsed > 0 else {
            throw LocalDataError(message: "Enter a positive amount with at most four decimal places.")
        }
        return NSDecimalNumber(decimal: parsed).stringValue
    }
    func optionalText(_ value: String?, limit: Int) throws -> String? {
        guard let value else { return nil }
        guard value.count <= limit else { throw LocalDataError(message: "Text is too long.") }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
    func account(_ id: UUID) throws -> Account {
        guard let account = snapshot.accounts[id] else { throw LocalDataError(message: "Choose an existing account.") }; return account
    }
    mutating func saveAccount(id: UUID? = nil, name: String, type: AccountType, currency: String, icon: String, color: AccountIconColor) throws -> Account {
        let existing = id.flatMap { snapshot.accounts[$0] }
        let currency = currency.uppercased()
        guard currency.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil else { throw LocalDataError(message: "Choose a currency.") }
        let account = Account(id: id ?? UUID(), name: try self.name(name, limit: 120), type: type, currency: currency,
            icon: try self.name(icon, limit: 80), iconColor: color, createdAt: existing?.createdAt ?? LocalJSON.timestamp(now), updatedAt: LocalJSON.timestamp(now), sortOrder: existing?.sortOrder ?? ((snapshot.accounts.values.compactMap(\.sortOrder).max() ?? -1) + 1))
        try put("account", key: account.id.uuidString, account); return account
    }
    mutating func reorderAccounts(_ accounts: [Account]) throws {
        guard Set(accounts.map(\.id)) == Set(snapshot.accounts.keys), accounts.count == snapshot.accounts.count else { throw LocalDataError(message: "Account order must contain every account.") }
        for (index, value) in accounts.enumerated() {
            let reordered = Account(id: value.id, name: value.name, type: value.type, currency: value.currency, icon: value.icon, iconColor: value.iconColor,
                createdAt: value.createdAt, updatedAt: LocalJSON.timestamp(now), sortOrder: index)
            try put("account", key: value.id.uuidString, reordered)
        }
    }
    mutating func deleteAccount(_ id: UUID) {
        let schedules = Set(snapshot.schedules.values.filter { $0.accountId == id }.map(\.id))
        for t in snapshot.transactions.values where t.accountId == id { erase("transaction", key: t.id.uuidString) }
        for s in schedules { erase("schedule", key: s.uuidString) }
        for e in snapshot.exclusions.values where schedules.contains(e.scheduleId) { erase("exclusion", key: e.id.uuidString) }
        for (key,budget) in snapshot.budgets where budget.accountId == id { erase("budget", key: key) }
        erase("account", key: id.uuidString)
    }
    mutating func saveDebt(id: UUID? = nil, name: String, icon: String, color: CategoryColor) throws -> Debt {
        let debt = Debt(id: id ?? UUID(), name: try self.name(name, limit: 200), icon: try self.name(icon, limit: 80), color: color)
        try put("debt", key: debt.id.uuidString, debt); return debt
    }
    mutating func saveCategory(id: UUID? = nil, name: String, kind: TransactionKind, parentID: UUID?, icon: String, color: CategoryColor) throws -> TransactionCategory {
        let existing = id.flatMap { snapshot.categories[$0] }
        let id = id ?? UUID(); let name = try self.name(name, limit: 80)
        guard kind != .debt else { throw LocalDataError(message: "Debt transactions cannot have categories.") }
        if let parentID {
            guard parentID != id, let parent = snapshot.categories[parentID], parent.parentId == nil, parent.kind == kind,
                  !snapshot.categories.values.contains(where: { $0.parentId == id }) else { throw LocalDataError(message: "Choose a parent category of the same type. Subcategories can only be one level deep.") }
        }
        guard !snapshot.categories.values.contains(where: { $0.id != id && $0.kind == kind && $0.parentId == parentID && $0.name.lowercased() == name.lowercased() }) else { throw LocalDataError(message: "A category with this name already exists.") }
        let category = TransactionCategory(id: id, systemKey: existing?.systemKey, name: name, kind: existing?.kind ?? kind, parentId: parentID,
            icon: try self.name(icon, limit: 80), color: color, isSystem: existing?.isSystem ?? false, examples: existing?.examples ?? [], sortOrder: existing?.sortOrder ?? 1000, createdAt: existing?.createdAt ?? now, updatedAt: now)
        try put("category", key: id.uuidString, category); return category
    }
    mutating func deleteCategory(_ category: TransactionCategory) throws {
        guard !category.isSystem else { throw LocalDataError(message: "Built-in categories cannot be deleted.") }
        let removed = Set([category.id] + snapshot.categories.values.filter { $0.parentId == category.id }.map(\.id))
        for id in removed { erase("category", key: id.uuidString) }
        for var t in snapshot.transactions.values where t.categoryId.map(removed.contains) == true { t.categoryId = nil; t.updatedAt = now; try put("transaction", key: t.id.uuidString, t) }
        for var s in snapshot.schedules.values where s.categoryId.map(removed.contains) == true { s.categoryId = nil; s.updatedAt = now; try put("schedule", key: s.id.uuidString, s) }
        for (key,b) in snapshot.budgets where b.categoryAssignments.contains(where: { removed.contains($0.categoryId) }) {
            let updated = MonthlyBudget(id: b.id, accountId: b.accountId, currency: b.currency, monthlyLimit: b.monthlyLimit, groups: b.groups,
                categoryAssignments: b.categoryAssignments.filter { !removed.contains($0.categoryId) }, createdAt: b.createdAt, updatedAt: now)
            try put("budget", key: key, updated)
        }
    }
    func preparedTransaction(id: UUID, request r: TransactionRequest, existing: StoredTransaction? = nil) throws -> StoredTransaction {
        let account = try account(r.accountId)
        if let categoryID = r.categoryId { guard snapshot.categories[categoryID]?.kind == r.kind else { throw LocalDataError(message: "Choose a category matching the transaction type.") } }
        if r.kind == .debt {
            guard r.categoryId == nil, r.recurrence == nil, let debtID = r.debtId, snapshot.debts[debtID] != nil else { throw LocalDataError(message: "Choose a debt recipient. Debt transactions cannot repeat or have categories.") }
        } else if r.debtId != nil { throw LocalDataError(message: "Only debt transactions can have a recipient.") }
        if let end = r.recurrence?.endAt, end < r.occurredAt { throw LocalDataError(message: "The recurrence end must be on or after the first transaction.") }
        return StoredTransaction(id: id, accountId: account.id, kind: r.kind, amount: try amount(r.amount), currency: existing?.accountId == account.id ? existing!.currency : account.currency,
            categoryId: r.categoryId, debtId: r.debtId, recurringScheduleId: existing?.recurringScheduleId, scheduledFor: existing?.scheduledFor,
            merchant: try optionalText(r.merchant, limit: 500), payee: try optionalText(r.payee, limit: 500), note: try optionalText(r.note, limit: 2000),
            occurredAt: r.occurredAt, createdAt: existing?.createdAt ?? now, updatedAt: now)
    }
    mutating func saveTransaction(id: UUID? = nil, request: TransactionRequest) throws -> FinanceTransaction {
        let existing = id.flatMap { snapshot.transactions[$0] }
        if id != nil && existing == nil { throw LocalDataError(message: "This transaction no longer exists.") }
        var t = try preparedTransaction(id: id ?? UUID(), request: request, existing: existing)
        if let recurrence = request.recurrence {
            let existingSchedule = t.recurringScheduleId.flatMap { snapshot.schedules[$0] }
            let scheduleID = existingSchedule?.id ?? UUID()
            var schedule = StoredSchedule(id: scheduleID, accountId: t.accountId, kind: t.kind, amount: t.amount, currency: t.currency, categoryId: t.categoryId,
                merchant: t.merchant, payee: t.payee, note: t.note, frequency: recurrence.frequency, startAt: existingSchedule?.startAt ?? t.occurredAt,
                lastOccurrenceAt: existingSchedule?.lastOccurrenceAt ?? t.occurredAt, nextOccurrenceAt: existingSchedule?.nextOccurrenceAt,
                endAt: recurrence.endAt, createdAt: existingSchedule?.createdAt ?? now, updatedAt: now, nextScheduledFor: existingSchedule?.nextScheduledFor)
            if existingSchedule == nil || existingSchedule?.frequency != recurrence.frequency || schedule.nextOccurrenceAt == nil { schedule.nextOccurrenceAt = schedule.next(after: schedule.lastOccurrenceAt); if existingSchedule?.frequency != recurrence.frequency { schedule.nextScheduledFor = nil } }
            if let end = schedule.endAt, let next = schedule.nextOccurrenceAt, next > end { schedule.nextOccurrenceAt = nil }
            t.recurringScheduleId = scheduleID; t.scheduledFor = t.scheduledFor ?? t.occurredAt
            if id == nil { t.id = occurrenceID(scheduleID: scheduleID, scheduledFor: t.scheduledFor!) }
            try put("schedule", key: scheduleID.uuidString, schedule)
        } else if let scheduleID = t.recurringScheduleId {
            try removeSchedule(scheduleID); t.recurringScheduleId = nil; t.scheduledFor = nil
        }
        try put("transaction", key: t.id.uuidString, t)
        try materialize(limit: 200)
        return t.presentation(in: snapshot)
    }
    mutating func transfer(_ request: TransferRequest) throws -> TransferResponse {
        let source = try account(request.fromAccountId); let destination = try account(request.toAccountId)
        guard source.id != destination.id, source.currency == destination.currency else { throw LocalDataError(message: "Transfers require different accounts using the same currency.") }
        func input(_ accountID: UUID, _ kind: TransactionKind) -> TransactionRequest {
            TransactionRequest(accountId: accountID, kind: kind, amount: request.amount, categoryId: nil, merchant: request.merchant, payee: request.payee, note: request.note, occurredAt: request.occurredAt)
        }
        let from = try saveTransaction(request: input(source.id, .expense)); let to = try saveTransaction(request: input(destination.id, .income))
        return TransferResponse(source: from, destination: to)
    }
    mutating func materialize(limit: Int = 200) throws {
        var remaining = limit
        for var schedule in snapshot.schedules.values.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            var changed = false
            while remaining > 0, let next = schedule.nextOccurrenceAt, next <= now {
                if let end = schedule.endAt, next > end { schedule.nextOccurrenceAt = nil; changed = true; break }
                let slot = schedule.nextScheduledFor ?? next
                let id = occurrenceID(scheduleID: schedule.id, scheduledFor: slot)
                if snapshot.exclusions[id] == nil, !snapshot.transactions.values.contains(where: { $0.recurringScheduleId == schedule.id && ($0.scheduledFor ?? $0.occurredAt) == slot }) {
                    let t = StoredTransaction(id: id, accountId: schedule.accountId, kind: schedule.kind, amount: schedule.amount, currency: schedule.currency, categoryId: schedule.categoryId,
                        debtId: nil, recurringScheduleId: schedule.id, scheduledFor: slot, merchant: schedule.merchant, payee: schedule.payee, note: schedule.note, occurredAt: next, createdAt: now, updatedAt: now)
                    try put("transaction", key: id.uuidString, t)
                    changes["transaction:\(id.uuidString.lowercased())"]?.origin = "generated"
                }
                schedule.lastOccurrenceAt = next; schedule.nextOccurrenceAt = schedule.next(after: next); schedule.nextScheduledFor = nil; changed = true; remaining -= 1
            }
            if changed { schedule.updatedAt = now; try put("schedule", key: schedule.id.uuidString, schedule) }
        }
    }
    mutating func exclude(scheduleID: UUID, date: Date) throws {
        let id = occurrenceID(scheduleID: scheduleID, scheduledFor: date)
        try put("exclusion", key: id.uuidString, StoredExclusion(id: id, scheduleId: scheduleID, scheduledFor: date))
    }
    mutating func removeSchedule(_ id: UUID) throws {
        for var t in snapshot.transactions.values where t.recurringScheduleId == id { t.recurringScheduleId = nil; t.scheduledFor = nil; t.updatedAt = now; try put("transaction", key: t.id.uuidString, t) }
        erase("schedule", key: id.uuidString)
    }
    mutating func deleteTransaction(_ transaction: FinanceTransaction, action: RecurringDeletionAction) throws {
        guard let stored = snapshot.transactions[transaction.id] else { return }
        if let scheduleID = stored.recurringScheduleId { try deleteOccurrence(scheduleID: scheduleID, date: stored.scheduledFor ?? stored.occurredAt, action: action, recordedID: stored.id) }
        else { erase("transaction", key: stored.id.uuidString) }
    }
    mutating func deleteOccurrence(scheduleID: UUID, date: Date, action: RecurringDeletionAction, recordedID: UUID? = nil) throws {
        guard var schedule = snapshot.schedules[scheduleID] else { throw LocalDataError(message: "This recurring transaction no longer exists.") }
        let recorded = recordedID.flatMap { snapshot.transactions[$0] } ?? snapshot.transactions.values.first { $0.recurringScheduleId == scheduleID && ($0.occurredAt == date || ($0.scheduledFor ?? $0.occurredAt) == date) }
        let slot = recorded?.scheduledFor ?? (schedule.nextOccurrenceAt == date ? schedule.nextScheduledFor : nil) ?? date
        let retainedID = action == .stopRepeating ? (recorded?.id ?? occurrenceID(scheduleID: scheduleID, scheduledFor: slot)) : nil
        recurrenceActions.append(SyncRecurrenceAction(scheduleId: scheduleID, action: action.rawValue, targetScheduledFor: slot, retainedTransactionId: retainedID, effectiveAt: now))
        if action == .occurrence {
            if let recorded { erase("transaction", key: recorded.id.uuidString) }
            try exclude(scheduleID: scheduleID, date: slot)
            if schedule.nextOccurrenceAt == date { schedule.nextScheduledFor = nil; schedule.lastOccurrenceAt = date; schedule.nextOccurrenceAt = schedule.next(after: date); schedule.updatedAt = now; try put("schedule", key: scheduleID.uuidString, schedule) }
            return
        }
        for t in snapshot.transactions.values where t.recurringScheduleId == scheduleID && t.occurredAt > now && !(action == .stopRepeating && t.id == recorded?.id) {
            erase("transaction", key: t.id.uuidString); try exclude(scheduleID: scheduleID, date: t.scheduledFor ?? t.occurredAt)
        }
        if action == .occurrenceAndFuture, let recorded { erase("transaction", key: recorded.id.uuidString); try exclude(scheduleID: scheduleID, date: recorded.scheduledFor ?? date) }
        if action == .stopRepeating && recorded == nil {
            let t = StoredTransaction(id: retainedID!, accountId: schedule.accountId, kind: schedule.kind, amount: schedule.amount, currency: schedule.currency, categoryId: schedule.categoryId, debtId: nil,
                recurringScheduleId: nil, scheduledFor: nil, merchant: schedule.merchant, payee: schedule.payee, note: schedule.note, occurredAt: date, createdAt: now, updatedAt: now)
            try put("transaction", key: t.id.uuidString, t)
        }
        try removeSchedule(scheduleID)
    }
    mutating func updateUpcoming(_ upcoming: UpcomingTransaction, request: TransactionRequest) throws {
        guard var schedule = snapshot.schedules[upcoming.id] else { throw LocalDataError(message: "This recurring transaction no longer exists.") }
        guard request.occurredAt > now else { throw LocalDataError(message: "Choose a future date for the next occurrence.") }
        let recorded = snapshot.transactions.values.first { $0.recurringScheduleId == schedule.id && $0.occurredAt == upcoming.occurredAt }
        let slot = recorded?.scheduledFor ?? schedule.nextScheduledFor ?? upcoming.occurredAt
        let values = try preparedTransaction(id: recorded?.id ?? occurrenceID(scheduleID: schedule.id, scheduledFor: slot), request: request, existing: recorded)
        recurrenceActions.append(SyncRecurrenceAction(scheduleId: schedule.id, action: "editUpcoming", targetScheduledFor: slot, retainedTransactionId: recorded?.id, effectiveAt: now))
        for t in snapshot.transactions.values where t.recurringScheduleId == schedule.id && t.occurredAt > now && t.id != recorded?.id { erase("transaction", key: t.id.uuidString) }
        if let recurrence = request.recurrence {
            let anchorChanged = request.occurredAt != upcoming.occurredAt || recurrence.frequency != schedule.frequency
            schedule.accountId = values.accountId; schedule.kind = values.kind; schedule.amount = values.amount; schedule.currency = values.currency
            schedule.categoryId = values.categoryId; schedule.merchant = values.merchant; schedule.payee = values.payee; schedule.note = values.note
            schedule.frequency = recurrence.frequency; schedule.endAt = recurrence.endAt; schedule.updatedAt = now
            if anchorChanged { schedule.startAt = request.occurredAt }
            if recorded != nil {
                var t = values; t.recurringScheduleId = schedule.id; t.scheduledFor = recorded?.scheduledFor ?? upcoming.occurredAt
                try put("transaction", key: t.id.uuidString, t)
                schedule.nextScheduledFor = nil; schedule.lastOccurrenceAt = request.occurredAt; schedule.nextOccurrenceAt = schedule.next(after: request.occurredAt)
            } else { schedule.nextOccurrenceAt = request.occurredAt; schedule.nextScheduledFor = slot }
            try put("schedule", key: schedule.id.uuidString, schedule)
        } else {
            var t = values; t.recurringScheduleId = nil; t.scheduledFor = nil
            try put("transaction", key: t.id.uuidString, t); try removeSchedule(schedule.id)
        }
    }
    mutating func saveBudget(_ r: MonthlyBudgetRequest) throws -> MonthlyBudget? {
        guard r.currency.uppercased().range(of: "^[A-Z]{3}$", options: .regularExpression) != nil else { throw LocalDataError(message: "Choose a currency.") }
        if let id = r.accountId { guard try account(id).currency == r.currency.uppercased() else { throw LocalDataError(message: "Budget currency must match the account.") } }
        let key = budgetKey(accountID: r.accountId)
        let foreignGroups = Set(snapshot.budgets.filter { $0.key != key }.values.flatMap { $0.groups.map(\.id) })
        guard foreignGroups.isDisjoint(with: r.groups.map(\.id)) else { throw LocalDataError(message: "Create new groups for this account’s budget.") }

        let limit = try r.monthlyLimit.map(amount)
        guard r.groups.count <= 100, r.categoryAssignments.count <= 500, Set(r.groups.map(\.id)).count == r.groups.count,
              Set(r.groups.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }).count == r.groups.count,
              Set(r.categoryAssignments.map(\.categoryId)).count == r.categoryAssignments.count else { throw LocalDataError(message: "Budget groups and category assignments must be unique.") }
        let groups = try r.groups.enumerated().map { BudgetGroup(id: $0.element.id, name: try name($0.element.name, limit: 80), limit: try amount($0.element.limit), sortOrder: $0.offset) }
        let assignments = try r.categoryAssignments.map { a in
            guard snapshot.categories[a.categoryId]?.kind == .expense, a.groupId.map({ id in groups.contains { $0.id == id } }) ?? (a.limit != nil) else { throw LocalDataError(message: "Choose an expense category and a valid budget group or limit.") }
            return BudgetCategoryAssignment(categoryId: a.categoryId, groupId: a.groupId, limit: try a.limit.map(amount))
        }
        if limit == nil && groups.isEmpty && assignments.isEmpty { erase("budget", key: key); return nil }
        let old = snapshot.budgets[key]
        let budget = MonthlyBudget(id: old?.id ?? UUID(), accountId: r.accountId, currency: r.currency.uppercased(), monthlyLimit: limit, groups: groups, categoryAssignments: assignments, createdAt: old?.createdAt ?? now, updatedAt: now)
        try put("budget", key: key, budget); return budget
    }
}
