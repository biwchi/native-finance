import SwiftUI

struct MainView: View {
    @EnvironmentObject private var accountStore: AccountStore
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
            DashboardView(
                isPresentingQuickEntry: isPresentingQuickEntry,
                onAddTransaction: presentAddTransaction
            )

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
        .onChange(of: quickEntryText) { _, text in
            do { try transactionStore.saveQuickEntryText(text) } catch { quickEntryErrorMessage = error.localizedDescription }
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
        .sheet(item: $quickEntryReview, onDismiss: { quickEntryText = transactionStore.savedQuickEntryText() }) { presentation in
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
            quickEntryText = transactionStore.savedQuickEntryText()
            quickEntryReview = transactionStore.savedQuickEntryReview()
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
                                in: RoundedRectangle(cornerRadius: AppRadius.composer, style: .continuous)
                            )
                            .ignoresSafeArea(.keyboard, edges: .bottom)
                    }
            }
        } else {
            VStack(spacing: 0) {
                Spacer()
                quickEntryComposerContent
                    .background {
                        Color.clear
                            .modifier(LegacyGlassSurface(
                                shape: RoundedRectangle(cornerRadius: AppRadius.composer, style: .continuous)
                            ))
                            .ignoresSafeArea(.keyboard, edges: .bottom)
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
        if let review = transactionStore.savedQuickEntryReview() { quickEntryReview = review; return }
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
        guard !isInterpretingQuickEntry, !trimmedQuickEntryText.isEmpty, let quickEntryAccountID else { return }
        let command = trimmedQuickEntryText
        isInterpretingQuickEntry = true
        defer { isInterpretingQuickEntry = false }

        do {
            let presentation = try await transactionStore.interpretQuickEntry(
                text: command,
                defaultAccountID: quickEntryAccountID
            )
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
