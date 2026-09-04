import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var budgetStore: BudgetStore
    @EnvironmentObject private var exchangeRateStore: ExchangeRateStore
    @EnvironmentObject private var transactionStore: TransactionStore
    @AppStorage(AppPreferences.preferSimpleTransactionEntryKey)
    private var preferSimpleTransactionEntry = false
    @AppStorage("lastTransactionAccountID") private var lastTransactionAccountID = ""

    @State private var addPresentation: AddTransactionPresentation?
    @State private var isPresentingQuickEntry = false
    @State private var quickEntryText = ""
    @State private var quickEntryAccountID: UUID?
    @State private var quickEntryReview: QuickEntryReviewPresentation?
    @State private var quickEntryErrorMessage: String?
    @State private var isInterpretingQuickEntry = false
    @FocusState private var isQuickEntryFocused: Bool

    var body: some View {
        ZStack {
            MainTabController(
                accountStore: accountStore,
                budgetStore: budgetStore,
                exchangeRateStore: exchangeRateStore,
                transactionStore: transactionStore
            ) {
                presentAddTransaction()
            }
            .ignoresSafeArea()

            if isPresentingQuickEntry {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture(perform: handleQuickEntryBackgroundTap)
                    .accessibilityHidden(true)

                quickEntryOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: isPresentingQuickEntry)
        .onChange(of: isQuickEntryFocused) { _, isFocused in
            if !isFocused, isPresentingQuickEntry {
                dismissQuickEntry()
            }
        }
        .onChange(of: accountStore.accounts) { _, _ in
            if isPresentingQuickEntry {
                configureQuickEntryAccount()
            }
        }
        .sheet(item: $addPresentation) { presentation in
            AddTransactionView(
                initialCommand: presentation.command,
                initialAccountID: presentation.accountID
            )
                .environmentObject(accountStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $quickEntryReview) { presentation in
            QuickEntryReviewView(presentation: presentation)
                .environmentObject(accountStore)
                .environmentObject(transactionStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $accountStore.isManagingAccounts) {
            AccountManagementView()
                .environmentObject(accountStore)
                .environmentObject(transactionStore)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert(
            "Couldn’t load accounts",
            isPresented: Binding(
                get: { accountStore.alertMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        accountStore.alertMessage = nil
                    }
                }
            ),
            actions: {
                Button("Try Again") {
                    Task {
                        await accountStore.loadAccounts(force: true)
                    }
                }
                Button("Cancel", role: .cancel) {}
            },
            message: {
                Text(accountStore.alertMessage ?? "Unknown error")
            }
        )
        .alert(
            "Couldn’t prepare transactions",
            isPresented: Binding(
                get: { quickEntryErrorMessage != nil },
                set: { if !$0 { quickEntryErrorMessage = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) {}
            },
            message: {
                Text(quickEntryErrorMessage ?? "Unknown error")
            }
        )
        .task {
            await accountStore.loadAccounts()
        }
        .task(id: accountStore.selectedAccountID) {
            await transactionStore.loadTransactions(accountID: accountStore.selectedAccountID)
        }
    }

    @ViewBuilder
    private var quickEntryOverlay: some View {
        if #available(iOS 26.0, *) {
            VStack(spacing: 0) {
                Spacer()
                quickEntryComposerContent
                    .background {
                        Color.clear
                            .glassEffect(
                                .regular,
                                in: RoundedRectangle(cornerRadius: 32, style: .continuous)
                            )
                            .ignoresSafeArea(.keyboard, edges: .bottom)
                    }
            }
        } else {
            VStack(spacing: 0) {
                Spacer()
                quickEntryComposerContent
                    .background(.bar)
                    .overlay(alignment: .top) {
                        Divider()
                    }
            }
        }
    }

    private var quickEntryComposerContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            QuickAccountMenu(
                accounts: accountStore.accounts,
                selectedAccountID: quickEntryAccountID
            ) { accountID in
                quickEntryAccountID = accountID
            }

            HStack(alignment: .top, spacing: AppSpacing.small) {
                TextField(
                    "Coffee 4.50 this morning",
                    text: $quickEntryText,
                    axis: .vertical
                )
                .lineLimit(2...7)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.sentences)
                .focused($isQuickEntryFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    AppColor.controlFill,
                    in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous)
                )

                if isInterpretingQuickEntry {
                    ProgressView()
                        .frame(
                            width: AppControlSize.minimumTapTarget,
                            height: AppControlSize.minimumTapTarget
                        )
                } else if !trimmedQuickEntryText.isEmpty {
                    PrimaryIconButton(
                        "Review transactions",
                        iconName: "arrow-up",
                        action: { Task { await submitQuickEntry() } }
                    )
                    .disabled(quickEntryAccountID == nil)
                    .transition(
                        .scale(scale: 0.72, anchor: .trailing)
                            .combined(with: .opacity)
                    )
                }
            }
            .animation(.snappy(duration: 0.22), value: trimmedQuickEntryText.isEmpty)
        }
        .padding(.horizontal, AppSpacing.small)
        .padding(.vertical, AppSpacing.small)
        .accessibilityAction(.escape) {
            dismissQuickEntry()
        }
        .task {
            await Task.yield()
            guard isPresentingQuickEntry else { return }
            isQuickEntryFocused = true
        }
    }

    private func presentAddTransaction() {
        if preferSimpleTransactionEntry {
            configureQuickEntryAccount()
            withAnimation(.snappy(duration: 0.25)) {
                isPresentingQuickEntry = true
            }
        } else {
            addPresentation = AddTransactionPresentation(command: nil, accountID: nil)
        }
    }

    private func handleQuickEntryBackgroundTap() {
        dismissQuickEntry()
    }

    @MainActor
    private func submitQuickEntry() async {
        guard !trimmedQuickEntryText.isEmpty, let quickEntryAccountID else { return }
        let command = trimmedQuickEntryText
        isInterpretingQuickEntry = true
        defer { isInterpretingQuickEntry = false }

        do {
            let presentation = try await transactionStore.interpretQuickEntry(
                text: command,
                defaultAccountID: quickEntryAccountID
            )
            quickEntryText = ""
            dismissQuickEntry()
            quickEntryReview = presentation
        } catch {
            quickEntryErrorMessage = error.localizedDescription
        }
    }

    private var trimmedQuickEntryText: String {
        quickEntryText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func dismissQuickEntry() {
        isQuickEntryFocused = false
        withAnimation(.snappy(duration: 0.25)) {
            isPresentingQuickEntry = false
        }
    }

    private func configureQuickEntryAccount() {
        if let quickEntryAccountID,
           accountStore.accounts.contains(where: { $0.id == quickEntryAccountID }) {
            return
        }

        if let selectedAccountID = accountStore.selectedAccountID,
           accountStore.accounts.contains(where: { $0.id == selectedAccountID }) {
            quickEntryAccountID = selectedAccountID
            return
        }

        if let lastAccountID = UUID(uuidString: lastTransactionAccountID),
           accountStore.accounts.contains(where: { $0.id == lastAccountID }) {
            quickEntryAccountID = lastAccountID
            return
        }

        quickEntryAccountID = accountStore.accounts.first?.id
    }
}

private struct QuickEntryReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore

    @State private var drafts: [QuickEntryDraft]
    @State private var editingDraft: QuickEntryDraft?
    @State private var isSaving = false
    @State private var errorMessage: String?
    private let prompt: String
    private let unparsedText: [String]

    init(presentation: QuickEntryReviewPresentation) {
        _drafts = State(initialValue: presentation.drafts)
        prompt = presentation.prompt
        unparsedText = presentation.unparsedText
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("“\(prompt)”")
                        .italic()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }

                if hasConvertedDrafts {
                    Section {
                        HStack(alignment: .top, spacing: AppSpacing.medium) {
                            AppIcon("information-circle", size: 20)
                                .foregroundStyle(AppColor.informative)
                                .frame(width: 24)

                            Text("Some transactions were converted to match their account currency.")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, AppSpacing.extraSmall)
                    }
                    .listRowBackground(AppColor.informative.opacity(0.12))
                }

                if !unparsedText.isEmpty {
                    Section {
                        Label {
                            Text("Some text needs your review: \(unparsedText.joined(separator: " · "))")
                        } icon: {
                            AppIcon("warning", size: 16)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                if drafts.isEmpty {
                    ContentUnavailableView(
                        "No transaction drafts",
                        iconName: "list",
                        description: Text("Dismiss this review and try a different description.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(groupedDrafts, id: \.day) { group in
                        Section {
                            ForEach(group.drafts) { draft in
                                draftButton(draft)
                            }
                        } header: {
                            Text(group.day, format: .dateTime.day().month(.wide).year())
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.custom(4))
            .environment(\.defaultMinListRowHeight, 0)
            .navigationTitle("Review quick entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton(submitTitle, isLoading: isSaving) {
                    Task { await commitDrafts() }
                }
                .disabled(!canSubmit)
                .padding(.horizontal, AppSpacing.medium)
                .padding(.vertical, AppSpacing.small)
                .background(.bar)
            }
            .sheet(item: $editingDraft) { draft in
                AddTransactionView(draft: draft) { updated in
                    if let index = drafts.firstIndex(where: { $0.id == updated.id }) {
                        drafts[index] = updated
                    }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .alert(
                "Couldn’t add transactions",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                ),
                actions: { Button("OK", role: .cancel) {} },
                message: { Text(errorMessage ?? "Unknown error") }
            )
        }
    }

    private func draftButton(_ draft: QuickEntryDraft) -> some View {
        Button {
            editingDraft = draft
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.small) {
                ForEach(draft.warnings, id: \.self) { warning in
                    Label(warning, icon: "warning")
                        .font(.caption)
                        .foregroundStyle(AppColor.warning)
                }
                TransactionRow(
                    transaction: draft,
                    account: account(draft.accountId),
                    titleOverride: title(for: draft),
                    secondaryAmountText: originalAmountText(for: draft)
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edit transaction draft")
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                drafts.removeAll { $0.id == draft.id }
            } label: {
                Label("Delete", icon: "trash")
            }
        }
    }

    private func originalAmountText(for draft: QuickEntryDraft) -> String? {
        guard let conversion = draft.conversion,
              let amount = Decimal(
                string: conversion.originalAmount,
                locale: Locale(identifier: "en_US_POSIX")
              ) else { return nil }
        let signedAmount = draft.kind == .expense ? -amount : amount
        return MoneyFormatter.format(
            signedAmount,
            currency: conversion.originalCurrency,
            showPositiveSign: draft.kind == .income
        )
    }

    private func title(for draft: QuickEntryDraft) -> String? {
        guard draft.mode == .transfer else { return nil }
        let destination = draft.destinationAccountId.flatMap(account)
        return destination.map { "Transfer to \($0.name)" } ?? "Transfer"
    }

    private func account(_ id: UUID) -> Account? {
        accountStore.accounts.first { $0.id == id }
    }

    private var hasConvertedDrafts: Bool {
        drafts.contains { $0.conversion != nil }
    }

    private var groupedDrafts: [(day: Date, drafts: [QuickEntryDraft])] {
        let groups = Dictionary(grouping: drafts) {
            Calendar.current.startOfDay(for: $0.occurredAt)
        }
        return groups.keys.sorted(by: >).map { day in
            let sorted = (groups[day] ?? []).sorted { $0.occurredAt > $1.occurredAt }
            return (day: day, drafts: sorted)
        }
    }

    private var submitTitle: String {
        "Add \(drafts.count) transaction\(drafts.count == 1 ? "" : "s")"
    }

    private var canSubmit: Bool {
        !isSaving && !drafts.isEmpty && drafts.allSatisfy(isValid)
    }

    private func isValid(_ draft: QuickEntryDraft) -> Bool {
        guard let amount = Decimal(
            string: draft.amount.replacingOccurrences(of: ",", with: "."),
            locale: Locale(identifier: "en_US_POSIX")
        ), amount > 0, account(draft.accountId) != nil else { return false }
        if draft.mode == .transfer {
            guard let destinationID = draft.destinationAccountId,
                  destinationID != draft.accountId,
                  let source = account(draft.accountId),
                  let destination = account(destinationID) else { return false }
            return source.currency == destination.currency
        }
        return !draft.isRecurring || draft.recurrenceEndAt == nil || draft.recurrenceEndAt! >= draft.occurredAt
    }

    @MainActor
    private func commitDrafts() async {
        guard canSubmit else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await transactionStore.commitQuickEntryDrafts(drafts)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
