import Foundation

struct AmountExpression: Equatable {
    private(set) var rawValue = ""

    init(rawValue: String = "") {
        self.rawValue = Self.normalizedInitialValue(rawValue)
    }

    var displayValue: String {
        rawValue
            .replacingOccurrences(of: "*", with: "×")
            .replacingOccurrences(of: "/", with: "÷")
            .replacingOccurrences(of: ".", with: MoneyFormatter.decimalSeparator)
    }

    var result: Decimal? {
        Self.evaluate(rawValue)
    }

    var canonicalResult: String? {
        guard let result, result > 0 else { return nil }
        return NSDecimalNumber(decimal: result).stringValue
    }

    mutating func enter(_ key: String) {
        switch key {
        case "⌫":
            if !rawValue.isEmpty {
                rawValue.removeLast()
            }
        case "+", "-", "*", "/":
            enterOperator(Character(key))
        case ".", ",":
            enterDecimalSeparator()
        default:
            guard key.count == 1, key.first?.isNumber == true else { return }
            guard rawValue.count < 32 else { return }
            rawValue.append(key)
        }
    }

    private mutating func enterOperator(_ value: Character) {
        guard !rawValue.isEmpty else { return }
        if let last = rawValue.last, Self.operators.contains(last) {
            rawValue.removeLast()
        }
        rawValue.append(value)
    }

    private mutating func enterDecimalSeparator() {
        let currentNumber = rawValue.split(whereSeparator: Self.operators.contains).last ?? ""
        guard !currentNumber.contains("."), rawValue.count < 32 else { return }
        if rawValue.isEmpty || rawValue.last.map(Self.operators.contains) == true {
            rawValue.append("0")
        }
        rawValue.append(".")
    }

    private static let operators = Set<Character>(["+", "-", "*", "/"])

    private static func normalizedInitialValue(_ value: String) -> String {
        guard
            !value.isEmpty,
            !value.contains(where: operators.contains),
            let amount = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
        else {
            return value
        }
        return NSDecimalNumber(decimal: amount).stringValue
    }

    private static func evaluate(_ expression: String) -> Decimal? {
        var completed = expression
        while completed.last.map(operators.contains) == true || completed.last == "." {
            completed.removeLast()
        }
        guard !completed.isEmpty else { return nil }

        var numbers: [Decimal] = []
        var operations: [Character] = []
        var current = ""

        for character in completed {
            if operators.contains(character) {
                guard let number = Decimal(string: current, locale: Locale(identifier: "en_US_POSIX")) else {
                    return nil
                }
                numbers.append(number)
                operations.append(character)
                current = ""
            } else {
                current.append(character)
            }
        }

        guard let finalNumber = Decimal(string: current, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        numbers.append(finalNumber)

        var collapsedNumbers = [numbers[0]]
        var collapsedOperations: [Character] = []

        for index in operations.indices {
            let operation = operations[index]
            let right = numbers[index + 1]
            if operation == "*" || operation == "/" {
                guard operation != "/" || right != 0, let left = collapsedNumbers.popLast() else {
                    return nil
                }
                collapsedNumbers.append(operation == "*" ? left * right : left / right)
            } else {
                collapsedOperations.append(operation)
                collapsedNumbers.append(right)
            }
        }

        var total = collapsedNumbers[0]
        for index in collapsedOperations.indices {
            total = collapsedOperations[index] == "+"
                ? total + collapsedNumbers[index + 1]
                : total - collapsedNumbers[index + 1]
        }
        return total
    }
}
