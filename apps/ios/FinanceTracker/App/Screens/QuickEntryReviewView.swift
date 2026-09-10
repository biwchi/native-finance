import SwiftUI

struct QuickEntryReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore

    @State private var drafts: [QuickEntryDraft]
    @State private var editingDraft: QuickEntryDraft?
    @State private var isSaving = false
    @State private var errorMessage: String?
    private let presentationID: UUID
    private let prompt: String
    private let unparsedText: [String]

    init(presentation: QuickEntryReviewPresentation) {
        _drafts = State(initialValue: presentation.drafts)
        presentationID = presentation.id
        prompt = presentation.prompt
        unparsedText = presentation.unparsedText
    }

    var body: some View {
        NavigationStack {
            AppList {
                AppSection {
                    Text("“\(prompt)”")
                        .italic()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
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

                if !unparsedText.isEmpty {
                    AppSection {
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
                do { try transactionStore.saveQuickEntryReview(QuickEntryReviewPresentation(id: presentationID, prompt: prompt, drafts: drafts, unparsedText: unparsedText)) }
                catch { errorMessage = error.localizedDescription }
            }
            .animateListChanges(value: drafts.map(\.id))
            .listStyle(.insetGrouped)
            .listSectionSpacing(.custom(4))
            .environment(\.defaultMinListRowHeight, 0)
            .navigationTitle("Review quick entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Group {
                        Button("Discard") {
                            do { try transactionStore.saveQuickEntryReview(nil); dismiss() } catch { errorMessage = error.localizedDescription }
                        }
                            .disabled(isSaving)
                    }
                    .legacyToolbarControl()
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton(submitTitle) {
                    Task { await commitDrafts() }
                }
                .disabled(!canSubmit)
                .padding(.horizontal, AppSpacing.medium)
                .padding(.vertical, AppSpacing.small)
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
                        .foregroundStyle(AppColor.warningText)
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
