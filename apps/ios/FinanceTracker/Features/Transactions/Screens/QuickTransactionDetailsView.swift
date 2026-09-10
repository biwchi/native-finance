import SwiftUI

struct QuickTransactionDetailsView: View {
    @Binding var merchant: String
    @Binding var payee: String
    @Binding var note: String
    let supportsRecurrence: Bool
    @Binding var isRecurring: Bool
    @Binding var frequency: RecurrenceFrequency
    @Binding var hasEndDate: Bool
    @Binding var endDate: Date

    var body: some View {
        AppForm {
            AppSection("People and places") {
                TextField("Merchant", text: $merchant)
                    .textContentType(.organizationName)
                TextField("Payee", text: $payee)
                    .textContentType(.name)
            }

            AppSection("Details") {
                TextField("Note", text: $note, axis: .vertical)
                    .lineLimit(2...6)
            }

            if supportsRecurrence {
                AppSection("Recurring transaction") {
                    Toggle("Repeat", isOn: $isRecurring)

                    if isRecurring {
                        Picker("Frequency", selection: $frequency) {
                            ForEach(RecurrenceFrequency.allCases) { frequency in
                                Text(frequency.title).tag(frequency)
                            }
                        }

                        Toggle("Set end date", isOn: $hasEndDate)

                        if hasEndDate {
                            DatePicker(
                                "End date and time",
                                selection: $endDate,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                        } else {
                            LabeledContent("Ends", value: "Forever")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: AppColor.switchTrack))
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}
