import SwiftUI

extension MonthlyBudget {
    @MainActor
    func converted(to currency: String, using rates: ExchangeRateStore) -> MonthlyBudget? {
        guard self.currency.caseInsensitiveCompare(currency) != .orderedSame else {
            return self
        }

        func convert(_ amount: String) -> String? {
            guard let decimal = Decimal(
                string: amount,
                locale: Locale(identifier: "en_US_POSIX")
            ), let converted = rates.convert(
                decimal,
                from: self.currency,
                to: currency
            ) else {
                return nil
            }
            var value = converted
            var rounded = Decimal()
            NSDecimalRound(&rounded, &value, 4, .bankers)
            return NSDecimalNumber(decimal: rounded).stringValue
        }

        let convertedLimit: String?
        if let monthlyLimit {
            guard let value = convert(monthlyLimit) else { return nil }
            convertedLimit = value
        } else {
            convertedLimit = nil
        }

        let convertedGroups = groups.compactMap { group -> BudgetGroup? in
            guard let limit = convert(group.limit) else { return nil }
            return BudgetGroup(
                id: group.id,
                name: group.name,
                limit: limit,
                sortOrder: group.sortOrder
            )
        }
        guard convertedGroups.count == groups.count else { return nil }

        let convertedAssignments = categoryAssignments.compactMap {
            assignment -> BudgetCategoryAssignment? in
            guard let currentLimit = assignment.limit else {
                return BudgetCategoryAssignment(
                    categoryId: assignment.categoryId,
                    groupId: assignment.groupId,
                    limit: nil
                )
            }
            guard let limit = convert(currentLimit) else { return nil }
            return BudgetCategoryAssignment(
                categoryId: assignment.categoryId,
                groupId: assignment.groupId,
                limit: limit
            )
        }
        guard convertedAssignments.count == categoryAssignments.count else { return nil }

        return MonthlyBudget(
            id: id,
            accountId: accountId,
            month: month,
            currency: currency,
            monthlyLimit: convertedLimit,
            groups: convertedGroups,
            categoryAssignments: convertedAssignments,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}


