import SwiftUI

struct MainView: View {
    @EnvironmentObject private var accountStore: AccountStore
    @EnvironmentObject private var transactionStore: TransactionStore
    @EnvironmentObject private var scanDraftStore: ScanDraftStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(AppPreferences.preferSimpleTransactionEntryKey)
    private var preferSimpleTransactionEntry = false
    @AppStorage(AppPreferences.openScanDraftsAutomaticallyKey)
    private var openScanDraftsAutomatically = false
    @AppStorage("lastTransactionAccountID") private var lastTransactionAccountID = ""

    @State private var addPresentation: AddTransactionPresentation?
    @State private var isPresentingQuickEntry = false
    @State private var isDismissingQuickEntry = false
    @State private var quickEntryAccountID: UUID?
    @State private var quickEntryErrorMessage: String?
    @State private var isInterpretingQuickEntry = false
    @State private var scanPresentation: ScanPresentation?
    @State private var scanDraftReview: ScanDraftReview?
    @State private var listedScanDraftReview: ScanDraftReview?
    @State private var isShowingDrafts = false
    @State private var isScanDraftPillSuppressed = false
    @State private var pendingDraftPresentation: PendingDraftPresentation?

    private struct ScanPresentation: Identifiable {
        let id = UUID()
        let accountID: UUID
        let replacingDraftID: UUID?
    }

    private struct ScanDraftReview: Identifiable {
        let id: UUID
        let presentation: QuickEntryReviewPresentation
    }

    private enum PendingDraftPresentation {
        case replacement(UUID)
        case manualEntry(UUID)
    }

    var body: some View {
        QuickEntryPresentation(
            isPresented: $isPresentingQuickEntry,
            isDismissing: isDismissingQuickEntry,
            onBackgroundTap: dismissQuickEntry
        ) {
            DashboardView(
                isPresentingQuickEntry: isPresentingQuickEntry,
                onAddTransaction: presentAddTransaction,
                onScanTransaction: presentScan,
                scanDraftPill: { AnyView(activityPill) }
            )
        } composer: {
            quickEntryOverlay
        }
        .onChange(of: accountStore.accounts) { _, _ in
            if isPresentingQuickEntry {
                configureQuickEntryAccount()
            }
        }
        .onChange(of: isPresentingQuickEntry) { _, presented in
            if !presented {
                isDismissingQuickEntry = false
                presentAutomaticScanReviewIfEligible()
            }
        }
        .appSheet(item: $addPresentation, onDismiss: presentPendingDraftDestination) { presentation in
            AddTransactionView(
                initialCommand: presentation.command,
                initialAccountID: presentation.accountID
            )
                .environmentObject(accountStore)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .appSheet(item: $scanPresentation, layout: .content, background: AppColor.cameraBackground, onDismiss: scanPresentationDidDismiss) { presentation in
            ReceiptScannerView(
                defaultAccountID: presentation.accountID,
                replacingDraftID: presentation.replacingDraftID
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .appSheet(item: $scanDraftReview, onDismiss: presentPendingDraftDestination) { route in
            scanReviewView(route)
        }
        .appSheet(isPresented: $isShowingDrafts, onDismiss: presentPendingDraftDestination) {
            ScanDraftsView(
                onReview: presentScanReview,
                onReplace: { pendingDraftPresentation = .replacement($0) },
                onManualEntry: { pendingDraftPresentation = .manualEntry($0) }
            )
            .environmentObject(scanDraftStore)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .appSheet(item: $listedScanDraftReview) { route in
                scanReviewView(route)
            }
        }
        .appSheet(isPresented: $accountStore.isManagingAccounts, onDismiss: presentPendingDraftDestination) {
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
            await accountStore.loadAccounts()
            scanDraftStore.appBecameActive()
            presentAutomaticScanReviewIfEligible()
        }
        .task(id: accountStore.selectedAccountID) {
            await transactionStore.loadTransactions(accountID: accountStore.selectedAccountID)
        }
        .onChange(of: scanDraftStore.revision) { _, _ in
            presentAutomaticScanReviewIfEligible()
        }
        .onChange(of: openScanDraftsAutomatically) { _, enabled in
            if enabled { presentAutomaticScanReviewIfEligible() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                scanDraftStore.appBecameActive()
                presentAutomaticScanReviewIfEligible()
            }
        }
        .onChange(of: presentationIdle) { _, idle in
            if idle { presentAutomaticScanReviewIfEligible() }
        }
    }

    @ViewBuilder
    private var quickEntryOverlay: some View {
        if #available(iOS 26.0, *) {
            quickEntryComposerContent
                .background {
                    Color.clear
                        .glassEffect(
                            .regular,
                            in: RoundedRectangle(cornerRadius: AppRadius.composer, style: .continuous)
                        )
                }
                .padding(.bottom, AppSpacing.small)
        } else {
            quickEntryComposerContent
                .background {
                    if reduceTransparency {
                        Rectangle().fill(AppColor.elevatedSurface)
                    } else {
                        Rectangle().fill(.thinMaterial)
                    }
                }
        }
    }

    private var activityPill: some View {
        ScanDraftActivityPill(
            onReview: presentScanReview,
            onOpenDrafts: { isShowingDrafts = true },
            onReplace: presentReplacement,
            onManualEntry: { presentManualEntry(for: $0) },
            isVisible: !isScanDraftPillSuppressed
        )
        .environmentObject(scanDraftStore)
    }

    private var quickEntryComposerContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            HStack(spacing: AppSpacing.small) {
                QuickAccountMenu(
                    accounts: accountStore.accounts,
                    selectedAccountID: quickEntryAccountID
                ) { accountID in
                    quickEntryAccountID = accountID
                }

                Spacer(minLength: 0)

                Button(action: presentManualTransaction) {
                    AppIcon("page-plus", size: 22)
                        .foregroundStyle(.primary)
                        .frame(
                            width: AppControlSize.minimumTapTarget,
                            height: AppControlSize.minimumTapTarget
                        )
                        .background(AppColor.controlFill, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add transaction manually")
            }

            HStack(alignment: .top, spacing: AppSpacing.small) {
                QuickEntryTextView(text: $transactionStore.quickEntryText)
                .overlay(alignment: .topLeading) {
                    if transactionStore.quickEntryText.isEmpty {
                        Text("Coffee 4.50 this morning")
                            .foregroundStyle(.placeholder)
                            .accessibilityHidden(true)
                            .allowsHitTesting(false)
                    }
                }
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
    }

    private func presentAddTransaction() {
        if preferSimpleTransactionEntry {
            configureQuickEntryAccount()
            isDismissingQuickEntry = false
            isPresentingQuickEntry = true
        } else {
            addPresentation = AddTransactionPresentation(command: nil, accountID: nil)
        }
    }

    private func presentScan() {
        guard !isInterpretingQuickEntry else { return }
        quickEntryAccountID = nil
        configureQuickEntryAccount()
        guard let accountID = quickEntryAccountID else {
            quickEntryErrorMessage = "Add an account before scanning purchases."
            return
        }
        // Present the account and sheet together so the first opening cannot use stale state.
        isScanDraftPillSuppressed = true
        scanPresentation = ScanPresentation(accountID: accountID, replacingDraftID: nil)
    }

    private func presentScanReview(_ id: UUID) {
        guard let item = scanDraftStore.item(id: id),
              item.state == .ready,
              let review = item.review else {
            isShowingDrafts = true
            return
        }
        scanDraftStore.markPresented(id)
        let route = ScanDraftReview(id: id, presentation: review)
        if isShowingDrafts {
            listedScanDraftReview = route
        } else {
            scanDraftReview = route
        }
    }

    private func scanReviewView(_ route: ScanDraftReview) -> some View {
        QuickEntryReviewView(
            presentation: route.presentation,
            onDraftsChange: { scanDraftStore.updateDrafts($0, for: route.id) },
            onCommit: { try await scanDraftStore.commit($0, for: route.id) }
        )
        .environmentObject(accountStore)
        .environmentObject(transactionStore)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func presentReplacement(_ id: UUID) {
        guard let item = scanDraftStore.item(id: id) else { return }
        isScanDraftPillSuppressed = true
        scanPresentation = ScanPresentation(
            accountID: item.defaultAccountID,
            replacingDraftID: id
        )
    }

    private func scanPresentationDidDismiss() {
        isScanDraftPillSuppressed = false
        presentPendingDraftDestination()
    }

    private func presentManualEntry(for id: UUID) {
        let accountID = scanDraftStore.item(id: id)?.defaultAccountID
        scanDraftStore.remove(id)
        addPresentation = AddTransactionPresentation(command: nil, accountID: accountID)
    }

    private func presentPendingDraftDestination() {
        guard let pendingDraftPresentation else {
            presentAutomaticScanReviewIfEligible()
            return
        }
        self.pendingDraftPresentation = nil
        switch pendingDraftPresentation {
        case .replacement(let id): presentReplacement(id)
        case .manualEntry(let id): presentManualEntry(for: id)
        }
    }

    private func presentAutomaticScanReviewIfEligible() {
        guard openScanDraftsAutomatically,
              scenePhase == .active,
              presentationIdle,
              let candidate = scanDraftStore.oldestAutomaticReview else { return }
        presentScanReview(candidate.id)
    }

    private var presentationIdle: Bool {
        addPresentation == nil
            && scanPresentation == nil
            && scanDraftReview == nil
            && listedScanDraftReview == nil
            && !isShowingDrafts
            && !isPresentingQuickEntry
            && !isDismissingQuickEntry
            && quickEntryErrorMessage == nil
            && !accountStore.isManagingAccounts
            && pendingDraftPresentation == nil
    }

    private func presentManualTransaction() {
        dismissQuickEntry()
        addPresentation = AddTransactionPresentation(command: nil, accountID: quickEntryAccountID)
    }

    @MainActor
    private func submitQuickEntry() async {
        guard !isInterpretingQuickEntry, !trimmedQuickEntryText.isEmpty, let quickEntryAccountID else { return }
        let command = trimmedQuickEntryText
        isInterpretingQuickEntry = true
        defer { isInterpretingQuickEntry = false }

        do {
            // Preserve any review left in the legacy slot after a storage failure.
            try scanDraftStore.recoverSavedReview()
            let presentation = try await transactionStore.interpretQuickEntry(
                text: command,
                defaultAccountID: quickEntryAccountID
            )
            try scanDraftStore.recoverSavedReview()
            // Keep the saved review available without interrupting manual entry
            // if the user left the composer while interpretation was running.
            guard isPresentingQuickEntry, !isDismissingQuickEntry else { return }
            dismissQuickEntry()
            presentScanReview(presentation.id)
        } catch {
            guard isPresentingQuickEntry, !isDismissingQuickEntry else { return }
            quickEntryErrorMessage = error.localizedDescription
        }
    }

    private var trimmedQuickEntryText: String {
        transactionStore.quickEntryText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func dismissQuickEntry() {
        isDismissingQuickEntry = true
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
