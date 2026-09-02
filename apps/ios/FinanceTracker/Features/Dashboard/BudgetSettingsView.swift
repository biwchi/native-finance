import SwiftUI

struct BudgetSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var budgetStore: BudgetStore
    @EnvironmentObject private var transactionStore: TransactionStore

    let month: Date
    let accountID: UUID?
    let currency: String
    let budget: MonthlyBudget?

    @State private var hasMonthlyLimit: Bool
    @State private var monthlyLimit: String
    @State private var groups: [BudgetGroupDraft]
    @State private var standaloneAssignments: [BudgetCategoryDraft]
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        month: Date,
        accountID: UUID?,
        currency: String,
        budget: MonthlyBudget?
    ) {
        self.month = month
        self.accountID = accountID
        self.currency = currency
        self.budget = budget

        let assignments = budget?.categoryAssignments ?? []
        _hasMonthlyLimit = State(initialValue: budget?.monthlyLimit != nil)
        _monthlyLimit = State(initialValue: editableAmount(budget?.monthlyLimit))
        _groups = State(
            initialValue: (budget?.groups ?? []).map { group in
                BudgetGroupDraft(
                    id: group.id,
                    name: group.name,
                    limit: editableAmount(group.limit),
                    categories: assignments
                        .filter { $0.groupId == group.id }
                        .map {
                            BudgetCategoryDraft(
                                categoryID: $0.categoryId,
                                limit: editableAmount($0.limit)
                            )
                        }
                )
            }
        )
        _standaloneAssignments = State(
            initialValue: assignments
                .filter { $0.groupId == nil }
                .map {
                    BudgetCategoryDraft(
                        categoryID: $0.categoryId,
                        limit: editableAmount($0.limit)
                    )
                }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                monthlyLimitSection
                groupsSection
                categoryLimitsSection

                if budget != nil {
                    Section {
                        Button("Clear budget", role: .destructive) {
                            hasMonthlyLimit = false
                            monthlyLimit = ""
                            groups = []
                            standaloneAssignments = []
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("\(monthName) budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
            }
            .safeAreaInset(edge: .bottom) {
                saveBar
            }
        }
        .task {
            await transactionStore.loadCategories()
        }
        .alert("Couldn’t save budget", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Check the budget amounts and try again.")
        }
        .interactiveDismissDisabled(isSaving)
    }

    private var monthlyLimitSection: some View {
        Section("Monthly budget") {
            Toggle(isOn: $hasMonthlyLimit.animation(.snappy)) {
                Label("Monthly limit", systemImage: "calendar")
            }

            if hasMonthlyLimit {
                BudgetAmountField(
                    title: "Limit",
                    text: $monthlyLimit,
                    currency: currency
                )
                .transition(.opacity)
            }
        }
    }

    private var groupsSection: some View {
        Section("Spending pools") {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                groupRow(group, index: index)
            }

            NavigationLink {
                BudgetGroupEditorView(
                    group: BudgetGroupDraft(),
                    categories: expenseCategories,
                    currency: currency,
                    unavailableCategoryIDs: assignedCategoryIDs
                ) { group in
                    groups.append(group)
                }
            } label: {
                Label("Add pool", systemImage: "plus")
            }
        }
    }

    private func groupRow(_ group: BudgetGroupDraft, index: Int) -> some View {
        let categoryIDs = Set(group.categories.map(\.categoryID))
        let limit = parsedAmount(group.limit) ?? 0
        let tint = groupTint(index)

        return NavigationLink {
            BudgetGroupEditorView(
                group: group,
                categories: expenseCategories,
                currency: currency,
                unavailableCategoryIDs: assignedCategoryIDs.subtracting(categoryIDs)
            ) { updated in
                replaceGroup(updated)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.3.layers.3d")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                Text(group.name.isEmpty ? "Untitled pool" : group.name)
                    .foregroundStyle(.primary)

                Spacer()

                Text(money(limit))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) {
                removeGroup(group)
            }
        }
    }

    private var categoryLimitsSection: some View {
        Section("Category limits") {
            ForEach(limitedAssignments) { reference in
                categoryLimitRow(reference)
            }

            if !availableLimitCategoryIDs.isEmpty {
                NavigationLink {
                    BudgetCategoryLimitEditor(
                        assignment: nil,
                        categories: expenseCategories.filter {
                            availableLimitCategoryIDs.contains($0.id)
                        },
                        groups: groups,
                        currency: currency,
                        groupIDByCategory: groupIDByCategory
                    ) { assignment, groupID in
                        moveAssignment(assignment, to: groupID)
                    }
                } label: {
                    Label("Add category limit", systemImage: "plus")
                }
            }
        }
    }

    private func categoryLimitRow(_ reference: BudgetAssignmentReference) -> some View {
        NavigationLink {
            BudgetCategoryLimitEditor(
                assignment: reference,
                categories: expenseCategories.filter {
                    $0.id == reference.categoryID || !assignedCategoryIDs.contains($0.id)
                },
                groups: groups,
                currency: currency,
                groupIDByCategory: groupIDByCategory
            ) { assignment, groupID in
                moveAssignment(assignment, to: groupID)
            }
        } label: {
            HStack(spacing: 12) {
                if let category = category(reference.categoryID) {
                    CategoryIcon(category: category, size: 38)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(categoryName(reference.categoryID))
                        .foregroundStyle(.primary)
                    if let groupName = reference.groupID.flatMap(groupName) {
                        Text(groupName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(money(parsedAmount(reference.limit) ?? 0))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) {
                removeLimit(reference)
            }
        }
    }

    private var saveBar: some View {
        Button {
            Task { await save() }
        } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView()
                        .tint(Color(uiColor: .systemBackground))
                }
                Text("Save budget")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(Color(uiColor: .systemBackground))
        }
        .modifier(QuickSubmitButtonStyle())
        .disabled(isSaving)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .padding(.horizontal, 10)
    }

    private var expenseCategories: [TransactionCategory] {
        transactionStore.categories(for: .expense)
    }

    private var assignedCategoryIDs: Set<UUID> {
        Set(groups.flatMap { $0.categories.map(\.categoryID) } + standaloneAssignments.map(\.categoryID))
    }

    private var groupIDByCategory: [UUID: UUID] {
        Dictionary(
            uniqueKeysWithValues: groups.flatMap { group in
                group.categories.map { ($0.categoryID, group.id) }
            }
        )
    }

    private var limitedAssignments: [BudgetAssignmentReference] {
        let grouped = groups.flatMap { group in
            group.categories.compactMap { assignment -> BudgetAssignmentReference? in
                guard parsedAmount(assignment.limit) != nil else { return nil }
                return BudgetAssignmentReference(
                    categoryID: assignment.categoryID,
                    groupID: group.id,
                    limit: assignment.limit
                )
            }
        }
        return (grouped + standaloneAssignments.map {
            BudgetAssignmentReference(categoryID: $0.categoryID, groupID: nil, limit: $0.limit)
        })
        .sorted { categoryName($0.categoryID) < categoryName($1.categoryID) }
    }

    private var availableLimitCategoryIDs: Set<UUID> {
        let categoriesWithoutLimits = groups.flatMap { group in
            group.categories.filter { parsedAmount($0.limit) == nil }.map(\.categoryID)
        }
        let unassigned = expenseCategories.map(\.id).filter { !assignedCategoryIDs.contains($0) }
        return Set(categoriesWithoutLimits + unassigned)
    }

    private func category(_ id: UUID) -> TransactionCategory? {
        expenseCategories.first { $0.id == id }
    }

    private func categoryName(_ id: UUID) -> String {
        category(id).map(transactionStore.categoryPath) ?? "Unknown category"
    }

    private func groupName(_ id: UUID) -> String? {
        groups.first { $0.id == id }?.name
    }

    private func replaceGroup(_ group: BudgetGroupDraft) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else {
            groups.append(group)
            return
        }
        groups[index] = group
    }

    private func removeGroup(_ group: BudgetGroupDraft) {
        standaloneAssignments.append(contentsOf: group.categories.filter { parsedAmount($0.limit) != nil })
        groups.removeAll { $0.id == group.id }
    }

    private func moveAssignment(_ assignment: BudgetCategoryDraft, to groupID: UUID?) {
        standaloneAssignments.removeAll { $0.categoryID == assignment.categoryID }
        for index in groups.indices {
            groups[index].categories.removeAll { $0.categoryID == assignment.categoryID }
        }

        if let groupID, let index = groups.firstIndex(where: { $0.id == groupID }) {
            groups[index].categories.append(assignment)
        } else {
            standaloneAssignments.append(assignment)
        }
    }

    private func removeLimit(_ reference: BudgetAssignmentReference) {
        if let groupID = reference.groupID,
           let groupIndex = groups.firstIndex(where: { $0.id == groupID }),
           let categoryIndex = groups[groupIndex].categories.firstIndex(where: {
               $0.categoryID == reference.categoryID
           }) {
            groups[groupIndex].categories[categoryIndex].limit = ""
        } else {
            standaloneAssignments.removeAll { $0.categoryID == reference.categoryID }
        }
    }

    private func groupTint(_ index: Int) -> Color {
        let colors: [Color] = [.blue, .purple, .orange, .teal, .pink, .indigo]
        return colors[index % colors.count]
    }

    private func money(_ value: Decimal) -> String {
        value.formatted(.currency(code: currency).precision(.fractionLength(0...2)))
    }

    private var monthName: String {
        month.formatted(.dateTime.month(.wide))
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func save() async {
        do {
            let request = try makeRequest()
            isSaving = true
            defer { isSaving = false }
            try await budgetStore.saveBudget(request)
            dismiss()
        } catch let error as BudgetDraftError {
            errorMessage = error.message
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func makeRequest() throws -> MonthlyBudgetRequest {
        let totalLimit: String?
        if hasMonthlyLimit {
            guard let amount = normalizedAmount(monthlyLimit) else {
                throw BudgetDraftError("Enter a monthly limit greater than zero.")
            }
            totalLimit = amount
        } else {
            totalLimit = nil
        }

        var groupNames = Set<String>()
        let groupRequests = try groups.map { group in
            let name = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                throw BudgetDraftError("Give every spending pool a name.")
            }
            guard groupNames.insert(name.lowercased()).inserted else {
                throw BudgetDraftError("Spending pool names must be unique.")
            }
            guard let limit = normalizedAmount(group.limit) else {
                throw BudgetDraftError("Enter a limit greater than zero for \(name).")
            }
            return BudgetGroupRequest(id: group.id, name: name, limit: limit)
        }

        var seenCategories = Set<UUID>()
        var assignments: [BudgetCategoryAssignmentRequest] = []
        for group in groups {
            for assignment in group.categories {
                guard seenCategories.insert(assignment.categoryID).inserted else {
                    throw BudgetDraftError("A category can only live in one pool.")
                }
                let limit = assignment.limit.isEmpty ? nil : normalizedAmount(assignment.limit)
                if !assignment.limit.isEmpty, limit == nil {
                    throw BudgetDraftError("Check the limit for \(categoryName(assignment.categoryID)).")
                }
                assignments.append(
                    BudgetCategoryAssignmentRequest(
                        categoryId: assignment.categoryID,
                        groupId: group.id,
                        limit: limit
                    )
                )
            }
        }
        for assignment in standaloneAssignments {
            guard seenCategories.insert(assignment.categoryID).inserted else {
                throw BudgetDraftError("A category can only have one budget.")
            }
            guard let limit = normalizedAmount(assignment.limit) else {
                throw BudgetDraftError("Check the limit for \(categoryName(assignment.categoryID)).")
            }
            assignments.append(
                BudgetCategoryAssignmentRequest(
                    categoryId: assignment.categoryID,
                    groupId: nil,
                    limit: limit
                )
            )
        }

        return MonthlyBudgetRequest(
            month: BudgetMonth.key(for: month),
            accountId: accountID,
            currency: currency,
            monthlyLimit: totalLimit,
            groups: groupRequests,
            categoryAssignments: assignments
        )
    }
}

private struct BudgetGroupEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var group: BudgetGroupDraft
    let categories: [TransactionCategory]
    let currency: String
    let unavailableCategoryIDs: Set<UUID>
    let onSave: (BudgetGroupDraft) -> Void

    @State private var searchText = ""

    init(
        group: BudgetGroupDraft,
        categories: [TransactionCategory],
        currency: String,
        unavailableCategoryIDs: Set<UUID>,
        onSave: @escaping (BudgetGroupDraft) -> Void
    ) {
        _group = State(initialValue: group)
        self.categories = categories
        self.currency = currency
        self.unavailableCategoryIDs = unavailableCategoryIDs
        self.onSave = onSave
    }

    var body: some View {
        List {
            Section("Pool details") {
                TextField("Name", text: $group.name)
                BudgetAmountField(title: "Limit", text: $group.limit, currency: currency)
            }

            Section("Categories") {
                ForEach(filteredCategories) { category in
                    let isUnavailable = unavailableCategoryIDs.contains(category.id)
                    let isSelected = group.categories.contains { $0.categoryID == category.id }

                    Button {
                        guard !isUnavailable else { return }
                        if isSelected {
                            group.categories.removeAll { $0.categoryID == category.id }
                        } else {
                            group.categories.append(BudgetCategoryDraft(categoryID: category.id))
                        }
                    } label: {
                        HStack(spacing: 12) {
                            CategoryIcon(category: category, size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.name).foregroundStyle(.primary)
                                if isUnavailable {
                                    Text("Already assigned elsewhere")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isUnavailable)
                }
            }
        }
        .navigationTitle(group.name.isEmpty ? "New pool" : group.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Find a category")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    onSave(group)
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
    }

    private var filteredCategories: [TransactionCategory] {
        guard !searchText.isEmpty else { return categories }
        return categories.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var canSave: Bool {
        !group.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            parsedAmount(group.limit) != nil
    }
}

private struct BudgetCategoryLimitEditor: View {
    @Environment(\.dismiss) private var dismiss

    let categories: [TransactionCategory]
    let groups: [BudgetGroupDraft]
    let currency: String
    let groupIDByCategory: [UUID: UUID]
    let onSave: (BudgetCategoryDraft, UUID?) -> Void

    @State private var categoryID: UUID?
    @State private var groupID: UUID?
    @State private var limit: String

    init(
        assignment: BudgetAssignmentReference?,
        categories: [TransactionCategory],
        groups: [BudgetGroupDraft],
        currency: String,
        groupIDByCategory: [UUID: UUID],
        onSave: @escaping (BudgetCategoryDraft, UUID?) -> Void
    ) {
        self.categories = categories
        self.groups = groups
        self.currency = currency
        self.groupIDByCategory = groupIDByCategory
        self.onSave = onSave
        let initialCategoryID = assignment?.categoryID ?? categories.first?.id
        _categoryID = State(initialValue: initialCategoryID)
        _groupID = State(
            initialValue: assignment?.groupID ?? initialCategoryID.flatMap { groupIDByCategory[$0] }
        )
        _limit = State(initialValue: assignment?.limit ?? "")
    }

    var body: some View {
        Form {
            Section("Category") {
                Picker("Category", selection: $categoryID) {
                    ForEach(categories) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
                .pickerStyle(.navigationLink)
            }

            Section("Limit") {
                BudgetAmountField(title: "Amount", text: $limit, currency: currency)
            }

            Section("Lives in") {
                Picker("Pool", selection: $groupID) {
                    Text("Standalone").tag(Optional<UUID>.none)
                    ForEach(groups) { group in
                        Text(group.name).tag(Optional(group.id))
                    }
                }
                .pickerStyle(.navigationLink)
            }
        }
        .navigationTitle("Category limit")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: categoryID) { _, newCategoryID in
            groupID = newCategoryID.flatMap { groupIDByCategory[$0] }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    guard let categoryID else { return }
                    onSave(
                        BudgetCategoryDraft(categoryID: categoryID, limit: limit),
                        groupID
                    )
                    dismiss()
                }
                .disabled(categoryID == nil || parsedAmount(limit) == nil)
            }
        }
    }
}

private struct BudgetAmountField: View {
    let title: String
    @Binding var text: String
    let currency: String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField("0", text: $text)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .keyboardType(.decimalPad)

                if !currency.isEmpty {
                    Text(currency)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct BudgetGroupDraft: Identifiable, Equatable {
    let id: UUID
    var name: String
    var limit: String
    var categories: [BudgetCategoryDraft]

    init(
        id: UUID = UUID(),
        name: String = "",
        limit: String = "",
        categories: [BudgetCategoryDraft] = []
    ) {
        self.id = id
        self.name = name
        self.limit = limit
        self.categories = categories
    }
}

private struct BudgetCategoryDraft: Identifiable, Equatable {
    var id: UUID { categoryID }
    let categoryID: UUID
    var limit: String = ""
}

private struct BudgetAssignmentReference: Identifiable {
    var id: UUID { categoryID }
    let categoryID: UUID
    let groupID: UUID?
    let limit: String
}

private struct BudgetDraftError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

private func parsedAmount(_ value: String) -> Decimal? {
    guard let amount = Decimal(string: value.replacingOccurrences(of: ",", with: ".")), amount > 0 else {
        return nil
    }
    return amount
}

private func normalizedAmount(_ value: String) -> String? {
    parsedAmount(value).map { NSDecimalNumber(decimal: $0).stringValue }
}

private func editableAmount(_ value: String?) -> String {
    guard let value,
          let amount = Decimal(string: value.replacingOccurrences(of: ",", with: ".")) else {
        return value ?? ""
    }
    return NSDecimalNumber(decimal: amount).stringValue
}
