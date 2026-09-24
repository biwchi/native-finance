import SwiftUI

struct DebtEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var transactionStore: TransactionStore
    let debt: Debt?
    let onSave: (Debt) -> Void
    @State private var name: String
    @State private var icon: String
    @State private var color: CategoryColor
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didRequestInitialFocus = false
    @State private var isKeyboardVisible = false
    @FocusState private var isNameFocused: Bool

    init(debt: Debt? = nil, onSave: @escaping (Debt) -> Void) {
        self.debt = debt
        self.onSave = onSave
        _name = State(initialValue: debt?.name ?? "")
        _icon = State(initialValue: AppIcons.canonicalName(debt?.icon ?? "user"))
        _color = State(initialValue: debt?.color ?? .blue)
    }

    var body: some View {
        NavigationStack {
            AppForm {
                AppSection {
                    HStack(spacing: AppSpacing.medium) {
                        DebtIcon(iconName: icon, color: color.swiftUIColor)
                        TextField("Recipient name", text: $name)
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)
                            .focused($isNameFocused)
                            .submitLabel(.done)
                            .onSubmit { isNameFocused = false }
                            .accessibilityIdentifier("debtRecipientNameField")
                    }
                } footer: {
                    Text("Choose this recipient whenever you lend them money.")
                }

                if !suggestedIcons.isEmpty {
                    AppSection("Suggested icons") {
                        ScrollView(.horizontal) {
                            HStack(spacing: AppSpacing.small) {
                                ForEach(suggestedIcons) { option in
                                    AccentSelectionButton(
                                        option.title, isSelected: icon == option.symbol,
                                        iconName: option.symbol, appearance: .iconBadge,
                                        selectionTint: color.swiftUIColor
                                    ) {
                                        isNameFocused = false
                                        icon = option.symbol
                                    }
                                }
                            }
                            .padding(.vertical, AppSpacing.extraSmall)
                        }
                        .scrollIndicators(.hidden)
                    }
                }

                AppSection("Icon") {
                    CategoryColorPicker(selection: Binding(
                        get: { color },
                        set: { color = $0; isNameFocused = false }
                    ))
                    IconPicker(selection: Binding(
                        get: { icon },
                        set: { icon = $0; isNameFocused = false }
                    ))
                }

                if let errorMessage {
                    AppSection {
                        Label(errorMessage, icon: "warning-triangle")
                            .foregroundStyle(AppColor.destructiveText)
                    }
                }
            }
            .disabled(isSaving)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(debt == nil ? "New recipient" : "Edit recipient")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { AppIcon("xmark", size: AppControlSize.iconButtonGlyph) }
                        .accessibilityLabel("Close")
                        .disabled(isSaving)
                        .legacyToolbarIcon()
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !isKeyboardVisible {
                    PrimaryActionButton("Save", isLoading: isSaving) {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                    .accessibilityIdentifier("debtRecipientSaveButton")
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
                guard debt == nil, !didRequestInitialFocus else { return }
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                guard !Task.isCancelled else { return }
                didRequestInitialFocus = true
                isNameFocused = true
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var suggestedIcons: [IconPickerOption] {
        AppIconCatalog.suggestions(matching: name)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && trimmedName.count <= 200
    }

    private func save() async {
        guard canSave, !isSaving else { return }
        isNameFocused = false
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let saved: Debt
            if let debt {
                saved = try await transactionStore.updateDebt(debt, name: trimmedName, icon: icon, color: color)
            } else {
                saved = try await transactionStore.createDebt(name: trimmedName, icon: icon, color: color)
            }
            onSave(saved)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
