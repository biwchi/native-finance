import SwiftUI

struct MonthlySummaryRow<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                leading.fixedSize()
                Spacer(minLength: AppSpacing.medium)
                trailing.fixedSize()
            }
            VStack(alignment: .leading, spacing: AppSpacing.extraSmall) {
                leading
                trailing
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
