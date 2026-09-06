import SwiftUI

struct TransactionMetadataBar: View {
    @State private var dateEditor: DateEditor?

    let accounts: [Account]
    let selectedAccountID: UUID?
    @Binding var date: Date
    let hasExtraDetails: Bool
    let onSelectAccount: (UUID) -> Void

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: AppSpacing.extraSmall) {
                    controls
                }
            } else {
                controls
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var controls: some View {
        HStack(spacing: AppSpacing.small) {
            QuickAccountMenu(
                accounts: accounts,
                selectedAccountID: selectedAccountID,
                appearance: .glass,
                onSelect: onSelectAccount
            )

            dateButton(.date)
            dateButton(.time)

            NavigationLink(value: AddTransactionRoute.details) {
                AppIcon(hasExtraDetails ? "clipboard-check" : "page-plus", size: 17)
                    .frame(width: AppControlSize.minimumTapTarget, height: AppControlSize.minimumTapTarget)
                    .modifier(CapsuleControlBackground(appearance: .glass))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Transaction details")
            .accessibilityValue(hasExtraDetails ? "Details added" : "No extra details")
        }
    }

    private func dateButton(_ editor: DateEditor) -> some View {
        Button {
            dateEditor = editor
        } label: {
            Text(date, format: editor == .date ? .dateTime.month(.abbreviated).day() : .dateTime.hour().minute())
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, AppSpacing.medium)
                .frame(minHeight: AppControlSize.minimumTapTarget)
                .modifier(CapsuleControlBackground(appearance: .glass))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(editor.title)
        .accessibilityValue(date.formatted(date: editor == .date ? .complete : .omitted, time: editor == .time ? .shortened : .omitted))
        .popover(isPresented: Binding(
            get: { dateEditor == editor },
            set: { if !$0 { dateEditor = nil } }
        )) {
            VStack(spacing: AppSpacing.medium) {
                HStack {
                    Text(editor.title).font(.headline)
                    Spacer()
                    Button("Done") { dateEditor = nil }
                }
                if editor == .date {
                    DatePicker("Transaction date", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                } else {
                    DatePicker("Transaction time", selection: $date, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                }
            }
            .padding(AppSpacing.large)
            .frame(minWidth: 300)
            .presentationCompactAdaptation(.popover)
        }
    }

    private enum DateEditor {
        case date
        case time

        var title: String { self == .date ? "Transaction date" : "Transaction time" }
    }
}
