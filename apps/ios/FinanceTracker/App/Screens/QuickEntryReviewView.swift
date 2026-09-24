import SwiftUI

struct QuickEntryReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore

    @State private var drafts: [QuickEntryDraft]
    @State private var editingDraft: QuickEntryDraft?
    @State private var isSaving = false
    @State private var didSubmit = false
    @State private var errorMessage: String?
    private let presentationID: UUID
    private let prompt: String
    private let source: QuickEntryReviewPresentation.Source?
    private let onSubmit: (() -> Void)?
    private let onDraftsChange: (([QuickEntryDraft]) -> Void)?
    private let onCommit: (([QuickEntryDraft]) async throws -> Int)?
    private let onBottomActionBarHeightChange: (CGFloat) -> Void

    init(
        presentation: QuickEntryReviewPresentation,
        onSubmit: (() -> Void)? = nil,
        onDraftsChange: (([QuickEntryDraft]) -> Void)? = nil,
        onCommit: (([QuickEntryDraft]) async throws -> Int)? = nil,
        onBottomActionBarHeightChange: @escaping (CGFloat) -> Void = { _ in }
    ) {
        _drafts = State(initialValue: presentation.drafts)
        presentationID = presentation.id
        prompt = presentation.prompt
        source = presentation.source
        self.onSubmit = onSubmit
        self.onDraftsChange = onDraftsChange
        self.onCommit = onCommit
        self.onBottomActionBarHeightChange = onBottomActionBarHeightChange
    }

    var body: some View {
        NavigationStack {
            AppList {
                AppSection {
                    Text(source != nil ? prompt : "“\(prompt)”")
                        .italic()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    if source == .csv || source == .document {
                        Text(reviewInstructions)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if hasConvertedDrafts {
                    AppSection {
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

                if drafts.isEmpty {
                    ContentUnavailableView(
                        "No transaction drafts",
                        iconName: "list",
                        description: Text(source == .csv ? "Discard this review and choose another CSV file." : source == .document ? "Dismiss this review and try another document." : source == .photo ? "Dismiss this review and try another photo." : "Dismiss this review and try a different description.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(groupedDrafts, id: \.day) { group in
                        AppSection {
                            ForEach(group.drafts) { draft in
                                draftButton(draft)
                            }
                        } header: {
                            Text(group.day, format: .dateTime.day().month(.wide).year())
                        }
                    }
                }
            }
            .onChange(of: drafts) { _, drafts in
                if let onDraftsChange {
                    onDraftsChange(drafts)
                    if drafts.isEmpty { dismiss() }
                    return
                }
                do {
                    if source != .csv {
                        try transactionStore.saveQuickEntryReview(drafts.isEmpty ? nil : QuickEntryReviewPresentation(
                            id: presentationID, prompt: prompt, drafts: drafts, source: source
                        ))
                    }
                    if drafts.isEmpty { dismiss() }
                } catch { errorMessage = error.localizedDescription }
            }
            .animateListChanges(value: drafts.map(\.id))
            .listStyle(.insetGrouped)
            .listSectionSpacing(.custom(4))
            .environment(\.defaultMinListRowHeight, 0)
            .navigationTitle(source == .csv ? "Review CSV import" : source == .document ? "Review document" : source == .photo ? "Review scan" : "Review quick entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Group {
                        Button(onCommit == nil ? "Discard" : "Close") {
                            if onCommit != nil { dismiss(); return }
                            if source == .csv { dismiss(); return }
                            do { try transactionStore.saveQuickEntryReview(nil); dismiss() } catch { errorMessage = error.localizedDescription }
                        }
                            .disabled(isSaving)
                    }
                    .legacyToolbarControl()
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton(submitTitle, isLoading: isSaving) {
                    Task { await commitDrafts() }
                }
                .disabled(!canSubmit)
                .padding(.horizontal, AppSpacing.medium)
                .padding(.vertical, AppSpacing.small)
                .reportScanDraftBottomBarHeight(onBottomActionBarHeightChange)
            }
            .interactiveDismissDisabled(isSaving)
            .appSheet(item: $editingDraft) { draft in
                AddTransactionView(draft: draft, isCSVImport: source == .csv, onSaveDraft: { updated in
                    if let index = drafts.firstIndex(where: { $0.id == updated.id }) {
                        drafts[index] = updated
                    }
                })
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
            TransactionRow(
                transaction: draft,
                account: account(draft.accountId),
                titleOverride: title(for: draft),
                secondaryAmountText: originalAmountText(for: draft)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Edit transaction draft")
        .circleSwipeActions {
            CircleSwipeAction.delete {
                drafts.removeAll { $0.id == draft.id }
                return true
            }
        }
    }

    private func originalAmountText(for draft: QuickEntryDraft) -> String? {
        guard let conversion = draft.conversion,
              let amount = Decimal(
                string: conversion.originalAmount,
                locale: Locale(identifier: "en_US_POSIX")
              ) else { return nil }
        let magnitude = abs(amount)
        let signedAmount = draft.kind == .expense ? -magnitude : magnitude
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
        if source == .csv || source == .document { return "Submit \(drafts.count) transaction\(drafts.count == 1 ? "" : "s")" }
        return "Add \(drafts.count) transaction\(drafts.count == 1 ? "" : "s")"
    }

    private var reviewInstructions: String {
        let count = "\(drafts.count) transaction\(drafts.count == 1 ? "" : "s")"
        let duplicate = source == .csv
            ? "Importing the same file again adds another copy."
            : "Processing the same file again creates another draft."
        return "\(count) to add. Tap a row to edit or swipe to remove it. Nothing is added until you press Submit. \(duplicate)"
    }

    private var canSubmit: Bool {
        !isSaving && !didSubmit && !drafts.isEmpty && drafts.allSatisfy(isValid)
    }

    private func isValid(_ draft: QuickEntryDraft) -> Bool {
        guard let amount = Decimal(
            string: draft.amount.replacingOccurrences(of: ",", with: "."),
            locale: Locale(identifier: "en_US_POSIX")
        ), amount != 0, account(draft.accountId) != nil else { return false }
        if draft.mode == .debt {
            return !draft.isRecurring && draft.category == nil && transactionStore.debts.contains { $0.id == draft.debtId }
        }
        if draft.mode == .transfer {
            guard amount > 0 else { return false }
            guard let destinationID = draft.destinationAccountId,
                  destinationID != draft.accountId,
                  let source = account(draft.accountId),
                  let destination = account(destinationID) else { return false }
            return source.currency == destination.currency && source.currency == draft.currency
        }
        return !draft.isRecurring || draft.recurrenceEndAt == nil || draft.recurrenceEndAt! >= draft.occurredAt
    }

    @MainActor
    private func commitDrafts() async {
        guard canSubmit else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            if let onCommit { _ = try await onCommit(drafts) }
            else if source == .csv { _ = try await transactionStore.commitCSVImport(drafts) }
            else { _ = try await transactionStore.commitQuickEntryDrafts(drafts) }
            didSubmit = true
            onSubmit?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
