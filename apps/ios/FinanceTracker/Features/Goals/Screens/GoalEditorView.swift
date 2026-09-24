import SwiftUI

struct GoalEditorView: View {
    private enum Field: Hashable { case name, amount }
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var goalStore: GoalStore
    @EnvironmentObject private var accountStore: AccountStore
    let goal: SavingsGoal?
    @State private var name: String
    @State private var amount: String
    @State private var accountID: UUID?
    @State private var icon: String
    @State private var color: CategoryColor
    @State private var deadline: String?
    @State private var chosenDate = Date.now
    @State private var showsCalendar = false
    @State private var isManagingAccounts = false
    @State private var confirmsDeletion = false
    @State private var errorMessage: String?
    @State private var didFocus = false
    @State private var isKeyboardVisible = false
    @FocusState private var focusedField: Field?

    init(goal: SavingsGoal? = nil, initialAccountID: UUID? = nil) {
        self.goal = goal
        _name = State(initialValue: goal?.name ?? "")
        _amount = State(initialValue: goal.map { MoneyFormatter.editingText($0.target) } ?? "")
        _accountID = State(initialValue: goal?.accountId ?? initialAccountID)
        _icon = State(initialValue: AppIcons.canonicalName(goal?.icon ?? "target"))
        _color = State(initialValue: goal?.color ?? .blue)
        _deadline = State(initialValue: goal?.deadline)
    }

    var body: some View {
        NavigationStack {
            AppForm {
                AppSection {
                    HStack(spacing: AppSpacing.medium) {
                        CategoryIcon(iconName: icon, color: color.swiftUIColor, size: 48)
                        TextField("Goal name", text: $name)
                            .font(.title2.weight(.semibold))
                            .textInputAutocapitalization(.words)
                            .focused($focusedField, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .amount }
                            .accessibilityIdentifier("goalNameField")
                    }
                    VStack(alignment: .leading, spacing: AppSpacing.small) {
                        Text("Target amount").font(.caption).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline) {
                            TextField("0", text: $amount)
                                .font(.largeTitle.weight(.semibold))
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .amount)
                                .accessibilityLabel("Target amount")
                                .accessibilityIdentifier("goalTargetField")
                            if let account { Text(account.currency).font(.subheadline).foregroundStyle(.secondary) }
                        }
                    }
                } header: {
                    ViewThatFits(in: .horizontal) {
                        HStack { accountPicker; Spacer(minLength: AppSpacing.medium); deadlinePicker }
                        VStack(alignment: .leading, spacing: AppSpacing.small) { accountPicker; deadlinePicker }
                    }
                    .foregroundStyle(.primary)
                }
                AppSection("Icon") {
                    CategoryColorPicker(selection: Binding(get: { color }, set: { color = $0; focusedField = nil }))
                    IconPicker(selection: Binding(get: { icon }, set: { icon = $0; focusedField = nil }))
                }
                if let errorMessage {
                    AppSection { Label(errorMessage, icon: "warning-triangle").foregroundStyle(AppColor.destructiveText) }
                }
                if goal != nil {
                    AppSection {
                        Button("Delete goal", role: .destructive) { confirmsDeletion = true }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .contentMargins(.top, AppSpacing.small, for: .scrollContent)
            .listSectionSpacing(.custom(AppSpacing.medium))
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(goal == nil ? "New goal" : "Edit goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { AppIcon("xmark", size: AppControlSize.iconButtonGlyph) }
                        .accessibilityLabel("Close").legacyToolbarIcon()
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !isKeyboardVisible {
                    PrimaryActionButton(goal == nil ? "Create goal" : "Save", action: save)
                        .disabled(!canSave)
                        .accessibilityIdentifier("saveGoalButton")
                        .padding(.horizontal, AppSpacing.extraLarge)
                        .padding(.vertical, AppSpacing.medium)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                isKeyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                isKeyboardVisible = false
            }
            .task {
                guard !didFocus else { return }
                if accountID == nil, accountStore.accounts.count == 1 { accountID = accountStore.accounts.first?.id }
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                guard !Task.isCancelled else { return }
                didFocus = true
                focusedField = .name
            }
            .alert("Delete \(goal?.name ?? "goal")?", isPresented: $confirmsDeletion) {
                Button("Delete goal", role: .destructive) {
                    guard let goal else { return }
                    do { try goalStore.delete(goal); dismiss() } catch { errorMessage = error.localizedDescription }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Your account and its money stay as they are.") }
        }
        .appSheet(isPresented: $isManagingAccounts) {
            AccountManagementView(selection: $accountID, allowsAllAccounts: false)
                .presentationDragIndicator(.visible)
        }
    }

    private var account: Account? { accountStore.accounts.first { $0.id == accountID } }
    private var accountPicker: some View {
        AccountPickerMenu(
            accounts: accountStore.accounts,
            selectedAccountID: accountID,
            subtitle: account?.currency,
            onManageAccounts: {
                focusedField = nil
                isManagingAccounts = true
            }
        ) { accountID = $0 }
            .accessibilityIdentifier("goalAccountPicker")
    }
    private var deadlinePicker: some View {
        Button {
            focusedField = nil
            chosenDate = deadline.flatMap { GoalDeadline.date(from: $0) } ?? .now
            showsCalendar = true
        } label: {
            HStack(spacing: AppSpacing.small) {
                AppIcon("calendar", size: 18)
                if let deadline, let date = GoalDeadline.date(from: deadline) {
                    Text(date, format: .dateTime.month(.abbreviated).day())
                } else { Text("Deadline") }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, AppSpacing.medium)
            .frame(minHeight: AppControlSize.minimumTapTarget)
            .modifier(TransactionGlassSurface(shape: Capsule(), isInteractive: true))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Goal deadline, \(deadline ?? "optional")")
        .accessibilityIdentifier("goalDeadlinePicker")
        .popover(isPresented: $showsCalendar) {
            DatePickerPopover(title: "Deadline", selection: $chosenDate, clearTitle: "No deadline", onClear: {
                deadline = nil
                showsCalendar = false
            }) {
                deadline = GoalDeadline.string(from: chosenDate)
                showsCalendar = false
            }
        }
    }
    private var canSave: Bool {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !cleaned.isEmpty && cleaned.count <= 120 && account != nil
            && (try? LocalEditor(snapshot: LocalSnapshot(), now: .now).amount(amount)) != nil
    }
    private func save() {
        guard canSave, let accountID else { return }
        do {
            try goalStore.save(id: goal?.id, name: name, accountID: accountID, targetAmount: amount,
                               icon: icon, color: color, deadline: deadline)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
