import SwiftUI

struct DatePickerPopover: View {
    let title: String
    @Binding var selection: Date
    var components: DatePickerComponents = [.date]
    var clearTitle: String? = nil
    var onClear: (() -> Void)? = nil
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.medium) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button("Done", action: onDone)
                    .frame(minHeight: AppControlSize.minimumTapTarget)
            }
            DatePicker(title, selection: $selection, displayedComponents: components)
                .datePickerStyle(.graphical)
            if let clearTitle, let onClear {
                Button(clearTitle, action: onClear)
                    .frame(maxWidth: .infinity, minHeight: AppControlSize.minimumTapTarget, alignment: .leading)
            }
        }
        .padding(AppSpacing.large)
        .frame(minWidth: 300, idealWidth: 340)
        .presentationCompactAdaptation(.popover)
    }
}
