import SwiftUI

struct QuickTransactionDetailsView: View {
    @Binding var counterparty: String
    @Binding var note: String
    let supportsRecurrence: Bool
    @Binding var isRecurring: Bool
    @Binding var frequency: RecurrenceFrequency
    @Binding var hasEndDate: Bool
    @Binding var endDate: Date
    var currency: Binding<String>? = nil

    var body: some View {
        AppForm {
            if let currency {
                AppSection {
                    AppNavigationLink {
                        CurrencyPickerView(selection: currency, currencyCodes: AppPreferences.currencyCodes)
                    } label: {
                        LabeledContent("Currency", value: currency.wrappedValue)
                    }
                } footer: {
                    Text(isRecurring
                         ? "Changing currency keeps the numeric amount unchanged and applies to this transaction and future occurrences."
                         : "Changing currency keeps the numeric amount unchanged.")
                }
            }

            AppSection("Person or business") {
                TextField("Person or business", text: $counterparty)
                    .textInputAutocapitalization(.words)
            }

            AppSection("Note") {
                TextField("Add a note", text: $note, axis: .vertical)
                    .lineLimit(3...8)
                    .textInputAutocapitalization(.sentences)
                    .accessibilityLabel("Transaction note")
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
