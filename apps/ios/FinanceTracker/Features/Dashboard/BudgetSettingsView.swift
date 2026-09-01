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
        _monthlyLimit = State(initialValue: budget?.monthlyLimit ?? "")
        _groups = State(
            initialValue: (budget?.groups ?? []).map { group in
                BudgetGroupDraft(
                    id: group.id,
                    name: group.name,
                    limit: group.limit,
                    categories: assignments
                        .filter { $0.groupId == group.id }
                        .map {
                            BudgetCategoryDraft(
                                categoryID: $0.categoryId,
                                limit: $0.limit ?? ""
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
                        limit: $0.limit ?? ""
                    )
                }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    introCard
                    monthlyLimitCard
                    groupsCard
                    categoryLimitsCard

                    if budget != nil {
                        Button("Clear \(monthName) budget", role: .destructive) {
                            hasMonthlyLimit = false
                            monthlyLimit = ""
                            groups = []
                            standaloneAssignments = []
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 4)
                    }
                }
                .padding(16)
                .padding(.bottom, 90)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Budget · \(monthName)")
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

    private var introCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.75), Color.accentColor.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 62, height: 62)

                Image(systemName: "target")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Build it your way")
                    .font(.title3.bold())
                Text("Start with one monthly number, then add pools and category guardrails whenever they help.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    budgetLevel("1", title: "Month", active: hasMonthlyLimit)
                    budgetLevel("2", title: "Pools", active: !groups.isEmpty)
                    budgetLevel("3", title: "Details", active: limitedAssignmentsCount > 0)
                }
            }
        }
        .padding(18)
        .budgetCardBackground()
    }

    private var monthlyLimitCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            Toggle(isOn: $hasMonthlyLimit.animation(.snappy)) {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Monthly spending cap")
                            .font(.headline)
                        Text("Your simple, top-level limit")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "circle.dashed.inset.filled")
                        .foregroundStyle(Color.accentColor)
                }
            }

            if hasMonthlyLimit {
                BudgetAmountField(
                    title: "I can spend",
                    text: $monthlyLimit,
                    currency: currency
                )
                .transition(.move(edge: .top).combined(with: .opacity))

                if let limit = parsedAmount(monthlyLimit) {
                    let spent = spentForMonth
                    VStack(spacing: 7) {
                        ProgressView(value: progress(spent: spent, limit: limit))
                            .tint(spent > limit ? .orange : .accentColor)
                        HStack {
                            Text("\(money(spent)) spent")
                            Spacer()
                            Text("\(money(max(limit - spent, 0))) left")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(18)
        .budgetCardBackground()
    }

    private var groupsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "Spending pools",
                subtitle: "Bundle categories into a shared limit",
                systemImage: "square.3.layers.3d"
            )

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
                Label("Add a spending pool", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .budgetCardBackground()
    }

    private func groupRow(_ group: BudgetGroupDraft, index: Int) -> some View {
        let categoryIDs = Set(group.categories.map(\.categoryID))
        let spent = spent(in: categoryIDs)
        let limit = parsedAmount(group.limit) ?? 0
        let tint = groupTint(index)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(group.name.isEmpty ? "New pool" : group.name)
                        .font(.headline)
                    Text("\(group.categories.count) \(group.categories.count == 1 ? "category" : "categories") · \(money(limit))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    Button("Remove pool", systemImage: "trash", role: .destructive) {
                        removeGroup(group)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 30, height: 30)
                }
            }

            ProgressView(value: progress(spent: spent, limit: limit))
                .tint(spent > limit ? .orange : tint)

            if !group.categories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(group.categories) { assignment in
                            Text(categoryName(assignment.categoryID))
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(tint.opacity(0.12), in: Capsule())
                        }
                    }
                }
            }

            NavigationLink {
                BudgetGroupEditorView(
                    group: group,
                    categories: expenseCategories,
                    currency: currency,
                    unavailableCategoryIDs: assignedCategoryIDs.subtracting(categoryIDs)
                ) { updated in
                    replaceGroup(updated)
                }
            } label: {
                HStack {
                    Text("Tune this pool")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 17))
        .overlay {
            RoundedRectangle(cornerRadius: 17)
                .stroke(tint.opacity(0.14), lineWidth: 1)
        }
    }

    private var categoryLimitsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(
                title: "Category guardrails",
                subtitle: "Optional limits for the places you watch closely",
                systemImage: "tag.circle.fill"
            )

            ForEach(limitedAssignments) { reference in
                categoryLimitRow(reference)
            }

            if availableLimitCategoryIDs.isEmpty {
                Text("Every available category already has a guardrail.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
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
                    Label("Add a category limit", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.purple)
            }
        }
        .padding(18)
        .budgetCardBackground()
    }

    private func categoryLimitRow(_ reference: BudgetAssignmentReference) -> some View {
        HStack(spacing: 8) {
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

                    VStack(alignment: .leading, spacing: 3) {
                        Text(categoryName(reference.categoryID))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(reference.groupID.flatMap(groupName) ?? "Standalone")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(money(parsedAmount(reference.limit) ?? 0))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
            }
            .buttonStyle(.plain)

            Menu {
                Button("Remove limit", systemImage: "trash", role: .destructive) {
                    removeLimit(reference)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 36)
            }
        }
    }

    private var saveBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                Task { await save() }
            } label: {
                HStack {
                    if isSaving { ProgressView().tint(.white) }
                    Text(hasAnyBudget ? "Save my plan" : "Save without a budget")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSaving)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(.ultraThinMaterial)
    }

    private func sectionHeader(title: String, subtitle: String, systemImage: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
        }
    }

    private func budgetLevel(_ number: String, title: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Text(number)
                .font(.caption2.bold())
                .frame(width: 17, height: 17)
                .background(active ? Color.accentColor : Color.secondary.opacity(0.18), in: Circle())
                .foregroundStyle(active ? .white : .secondary)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(active ? .primary : .secondary)
        }
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

    private var limitedAssignmentsCount: Int {
        limitedAssignments.count
    }

    private var hasAnyBudget: Bool {
        hasMonthlyLimit || !groups.isEmpty || !standaloneAssignments.isEmpty
    }

    private var spentForMonth: Decimal {
        let start = BudgetMonth.start(of: month)
        let end = Calendar.current.date(byAdding: .month, value: 1, to: start) ?? start
        return transactionStore.transactions.reduce(into: Decimal.zero) { total, transaction in
            guard transaction.kind == .expense,
                  transaction.occurredAt >= start,
                  transaction.occurredAt < end,
                  let amount = Decimal(string: transaction.amount) else { return }
            total += amount
        }
    }

    private func spent(in categoryIDs: Set<UUID>) -> Decimal {
        let start = BudgetMonth.start(of: month)
        let end = Calendar.current.date(byAdding: .month, value: 1, to: start) ?? start
        return transactionStore.transactions.reduce(into: Decimal.zero) { total, transaction in
            guard transaction.kind == .expense,
                  transaction.occurredAt >= start,
                  transaction.occurredAt < end,
                  let categoryID = transaction.category?.id,
                  categoryIDs.contains(categoryID),
                  let amount = Decimal(string: transaction.amount) else { return }
            total += amount
        }
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

    private func progress(spent: Decimal, limit: Decimal) -> Double {
        guard limit > 0 else { return 0 }
        return min(max(NSDecimalNumber(decimal: spent / limit).doubleValue, 0), 1)
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
            Section {
                VStack(alignment: .leading, spacing: 9) {
                    Label("One limit, a few teammates", systemImage: "person.3.fill")
                        .font(.headline)
                        .foregroundStyle(.purple)
                    Text("Pick the categories that should share this pool. You can still add a tighter category limit later.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("Pool details") {
                TextField("Name, e.g. Needs", text: $group.name)
                BudgetAmountField(title: "Pool limit", text: $group.limit, currency: currency)
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
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("A friendly guardrail", systemImage: "shield.lefthalf.filled")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text("This limit can stand alone or sit inside one of your spending pools.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("Category") {
                Picker("Category", selection: $categoryID) {
                    ForEach(categories) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
            }

            Section("Limit") {
                BudgetAmountField(title: "Category limit", text: $limit, currency: currency)
            }

            Section("Lives in") {
                Picker("Pool", selection: $groupID) {
                    Text("Standalone").tag(Optional<UUID>.none)
                    ForEach(groups) { group in
                        Text(group.name).tag(Optional(group.id))
                    }
                }
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
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("0", text: $text)
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .keyboardType(.decimalPad)
            }

            if !currency.isEmpty {
                Text(currency)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.secondary.opacity(0.10), in: Capsule())
            }
        }
        .padding(13)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
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

private extension View {
    func budgetCardBackground() -> some View {
        background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(.white.opacity(0.07), lineWidth: 1)
            }
    }
}
