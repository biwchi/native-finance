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
        _monthlyLimit = State(initialValue: BudgetAmountParser.editable(budget?.monthlyLimit))
        _groups = State(
            initialValue: (budget?.groups ?? []).map { group in
                BudgetGroupDraft(
                    id: group.id,
                    name: group.name,
                    limit: BudgetAmountParser.editable(group.limit),
                    categories: assignments
                        .filter { $0.groupId == group.id }
                        .map {
                            BudgetCategoryDraft(
                                categoryID: $0.categoryId,
                                limit: BudgetAmountParser.editable($0.limit)
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
                        limit: BudgetAmountParser.editable($0.limit)
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
                Label("Monthly limit", icon: "calendar")
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
                Label("Add pool", icon: "plus")
            }
        }
    }

    private func groupRow(_ group: BudgetGroupDraft, index: Int) -> some View {
        let categoryIDs = Set(group.categories.map(\.categoryID))
        let limit = BudgetAmountParser.parse(group.limit) ?? 0
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
            BudgetGroupRow(name: group.name, formattedLimit: money(limit), tint: tint)
        }
        .swipeActions {
            Button(role: .destructive) {
                removeGroup(group)
            } label: {
                Label("Delete", icon: "trash")
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
                    Label("Add category limit", icon: "plus")
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
            BudgetCategoryLimitRow(
                category: category(reference.categoryID),
                categoryName: categoryName(reference.categoryID),
                groupName: reference.groupID.flatMap(groupName),
                formattedLimit: money(BudgetAmountParser.parse(reference.limit) ?? 0)
            )
        }
        .swipeActions {
            Button(role: .destructive) {
                removeLimit(reference)
            } label: {
                Label("Delete", icon: "trash")
            }
        }
    }

    private var saveBar: some View {
        PrimaryActionButton("Save budget", isLoading: isSaving) {
            Task { await save() }
        }
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
                guard BudgetAmountParser.parse(assignment.limit) != nil else { return nil }
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
            group.categories.filter { BudgetAmountParser.parse($0.limit) == nil }.map(\.categoryID)
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
        standaloneAssignments.append(contentsOf: group.categories.filter { BudgetAmountParser.parse($0.limit) != nil })
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
        BudgetGroupPalette.color(at: index)
    }

    private func money(_ value: Decimal) -> String {
        MoneyFormatter.format(value, currency: currency)
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
            guard let amount = BudgetAmountParser.normalized(monthlyLimit) else {
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
            guard let limit = BudgetAmountParser.normalized(group.limit) else {
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
                let limit = assignment.limit.isEmpty ? nil : BudgetAmountParser.normalized(assignment.limit)
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
            guard let limit = BudgetAmountParser.normalized(assignment.limit) else {
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
