import SwiftUI

struct CategoryEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var transactionStore: TransactionStore

    let editor: CategoryEditor
    private let allowsKindChanges: Bool
    private let onCreated: ((TransactionCategory) -> Void)?

    @State private var name: String
    @State private var kind: TransactionKind
    @State private var parentID: UUID?
    @State private var icon: String
    @State private var color: CategoryColor
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var didRequestInitialFocus = false
    @State private var isKeyboardVisible = false
    @FocusState private var isNameFocused: Bool

    init(
        editor: CategoryEditor,
        allowsKindChanges: Bool = true,
        onCreated: ((TransactionCategory) -> Void)? = nil
    ) {
        self.editor = editor
        self.allowsKindChanges = allowsKindChanges
        self.onCreated = onCreated
        _name = State(initialValue: editor.category?.name ?? "")
        _kind = State(initialValue: editor.category?.kind ?? editor.kind)
        _parentID = State(initialValue: editor.category?.parentId)
        _icon = State(initialValue: editor.category?.displayIcon ?? "label")
        _color = State(initialValue: editor.category?.displayCategoryColor ?? .gray)
    }

    var body: some View {
        NavigationStack {
            AppForm {
                AppSection {
                    HStack(spacing: AppSpacing.medium) {
                        CategoryIcon(iconName: icon, color: color.swiftUIColor)
                        TextField("Category name", text: $name)
                            .textInputAutocapitalization(.words)
                            .focused($isNameFocused)
                            .submitLabel(.done)
                            .onSubmit { isNameFocused = false }
                            .accessibilityIdentifier("categoryNameField")
                    }
                } header: {
                    parentPicker
                } footer: {
                    if hasSubcategories {
                        Text("Move or delete its subcategories before assigning a parent.")
                    }
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
            .listSectionSpacing(.custom(AppSpacing.large))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                if parentID == nil {
                    ToolbarItem(placement: .principal) {
                        TransactionModeSelector(modes: [.income, .expense], selection: modeSelection)
                            .disabled(!canChangeKind || isSaving)
                            .accessibilityLabel("Category type")
                            .accessibilityHint(typeAccessibilityHint)
                            .accessibilityIdentifier("categoryTypeSelector")
                    }
                }

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
                    .accessibilityIdentifier("categorySaveButton")
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
                guard editor.category == nil, !didRequestInitialFocus else { return }
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                guard !Task.isCancelled else { return }
                didRequestInitialFocus = true
                isNameFocused = true
            }
        }
    }

    private var parentPicker: some View {
        Menu {
            Picker("Parent category", selection: Binding(
                get: { parentID },
                set: { parentID = $0; isNameFocused = false }
            )) {
                Text("None").tag(UUID?.none)

                ForEach(parentCandidates) { category in
                    Label(category.name, icon: category.displayIcon)
                        .tag(Optional(category.id))
                }
            }
        } label: {
            HStack(spacing: AppSpacing.small) {
                CategoryIcon(
                    iconName: selectedParent?.displayIcon ?? "folder",
                    color: selectedParent?.displayColor ?? .gray,
                    size: 28
                )
                Text(selectedParent?.name ?? "No parent category")
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                AppIcon("nav-arrow-down", size: 12)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, AppSpacing.medium)
            .padding(.vertical, AppSpacing.small)
            .frame(minHeight: AppControlSize.minimumTapTarget)
            .background(AppColor.elevatedSurface, in: RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, AppSpacing.small)
        .textCase(nil)
        .disabled(hasSubcategories || isSaving)
        .accessibilityLabel("Parent category")
        .accessibilityValue(selectedParent?.name ?? "None")
        .accessibilityIdentifier("categoryParentPicker")
    }

    private var selectedParent: TransactionCategory? {
        transactionStore.categories.first { $0.id == parentID }
    }

    private var suggestedIcons: [IconPickerOption] {
        AppIconCatalog.suggestions(matching: name)
    }

    private var canChangeKind: Bool {
        editor.category == nil && allowsKindChanges && parentID == nil
    }

    private var modeSelection: Binding<QuickTransactionMode> {
        Binding(
            get: { kind == .income ? .income : .expense },
            set: { mode in
                guard canChangeKind, !isSaving, mode == .income || mode == .expense else { return }
                isNameFocused = false
                kind = mode == .income ? .income : .expense
            }
        )
    }

    private var typeAccessibilityHint: String {
        if parentID != nil { return "Uses the parent category's type." }
        if editor.category != nil { return "Saved categories keep their original type." }
        if !allowsKindChanges { return "Uses the transaction's type." }
        return "Choose income or expense."
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parentCandidates: [TransactionCategory] {
        transactionStore.rootCategories(for: kind).filter {
            $0.id != editor.category?.id
        }
    }

    private var hasSubcategories: Bool {
        guard let category = editor.category else { return false }
        return !transactionStore.subcategories(of: category).isEmpty
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && hasChanges
    }

    private var hasChanges: Bool {
        guard let category = editor.category else { return true }
        return trimmedName != category.name ||
            parentID != category.parentId ||
            icon != category.displayIcon ||
            color != category.displayCategoryColor
    }

    private func save() async {
        guard canSave, !isSaving else { return }
        isNameFocused = false
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            if let category = editor.category {
                try await transactionStore.updateCategory(
                    category,
                    name: trimmedName,
                    parentID: parentID,
                    icon: icon,
                    color: color
                )
            } else {
                let category = try await transactionStore.createCategory(
                    name: trimmedName,
                    kind: kind,
                    parentID: parentID,
                    icon: icon,
                    color: color
                )
                onCreated?(category)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
