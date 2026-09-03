import Foundation

struct TransactionCommandParser {
    private struct DateCandidate {
        let range: NSRange
        let components: DateComponents?
        let isValid: Bool
    }

    private struct TimeCandidate {
        let range: NSRange
        let hour: Int
        let minute: Int
    }

    private struct AmountCandidate {
        let range: NSRange
        let amount: Decimal
        let sign: String
    }

    private static let isoDateExpression = try! NSRegularExpression(
        pattern: #"\b(?:on\s+)?(\d{4})-(\d{1,2})-(\d{1,2})\b"#,
        options: [.caseInsensitive]
    )
    private static let dayMonthYearExpression = try! NSRegularExpression(
        pattern: #"\b(?:on\s+)?(\d{1,2})\.(\d{1,2})\.(\d{4})\b"#,
        options: [.caseInsensitive]
    )
    private static let relativeDateExpression = try! NSRegularExpression(
        pattern: #"\b(?:on\s+)?(day before yesterday|two days ago|yesterday|today|\d+\s+days?\s+ago)\b"#,
        options: [.caseInsensitive]
    )
    private static let englishMonthDayYearExpression = try! NSRegularExpression(
        pattern: #"\b(?:on\s+)?(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+(\d{1,2})(?:st|nd|rd|th)?(?:,\s*|\s+)(\d{4})\b"#,
        options: [.caseInsensitive]
    )
    private static let englishDayMonthYearExpression = try! NSRegularExpression(
        pattern: #"\b(?:on\s+)?(\d{1,2})(?:st|nd|rd|th)?\s+(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+(\d{4})\b"#,
        options: [.caseInsensitive]
    )
    private static let timeExpression = try! NSRegularExpression(
        pattern: #"\b(?:at\s+)?((?:1[0-2]|0?[1-9])(?::[0-5]\d)?\s?(?:am|pm)|(?:[01]?\d|2[0-3]):[0-5]\d)\b"#,
        options: [.caseInsensitive]
    )
    private static let dateDetector = try! NSDataDetector(
        types: NSTextCheckingResult.CheckingType.date.rawValue
    )

    func parse(
        _ command: String,
        context: TransactionCommandContext = TransactionCommandContext()
    ) -> TransactionCommandResult {
        var calendar = context.calendar
        calendar.locale = context.locale
        calendar.timeZone = context.timeZone

        let fullRange = NSRange(command.startIndex..<command.endIndex, in: command)
        let timeCandidates = Self.timeExpression
            .matches(in: command, range: fullRange)
            .compactMap { match -> TimeCandidate? in
                guard
                    let value = substring(command, range: match.range(at: 1)),
                    let time = parseTime(value)
                else {
                    return nil
                }

                return TimeCandidate(
                    range: match.range,
                    hour: time.hour,
                    minute: time.minute
                )
            }

        var dateCandidates: [DateCandidate] = []
        dateCandidates += explicitDateCandidates(
            in: command,
            expression: Self.isoDateExpression,
            calendar: calendar,
            componentOrder: (year: 1, month: 2, day: 3)
        )
        dateCandidates += explicitDateCandidates(
            in: command,
            expression: Self.dayMonthYearExpression,
            calendar: calendar,
            componentOrder: (year: 3, month: 2, day: 1)
        )
        dateCandidates += englishDateCandidates(
            in: command,
            expression: Self.englishMonthDayYearExpression,
            calendar: calendar,
            componentOrder: (year: 3, month: 1, day: 2)
        )
        dateCandidates += englishDateCandidates(
            in: command,
            expression: Self.englishDayMonthYearExpression,
            calendar: calendar,
            componentOrder: (year: 3, month: 2, day: 1)
        )
        dateCandidates += relativeDateCandidates(
            in: command,
            context: context,
            calendar: calendar
        )

        let existingDateRanges = dateCandidates.map(\.range)
        for match in Self.dateDetector.matches(in: command, range: fullRange) {
            guard let date = match.date else { continue }
            if existingDateRanges.contains(where: { rangesOverlap($0, match.range) }) {
                continue
            }
            if timeCandidates.contains(where: { rangesOverlap($0.range, match.range) }) {
                continue
            }

            let components = calendar.dateComponents([.year, .month, .day], from: date)
            dateCandidates.append(
                DateCandidate(
                    range: match.range,
                    components: components,
                    isValid: components.year != nil && components.month != nil && components.day != nil
                )
            )
        }

        let hasDateConflict =
            dateCandidates.count > 1 ||
            timeCandidates.count > 1 ||
            dateCandidates.contains(where: { !$0.isValid })

        let occurredAt: Date?
        if hasDateConflict {
            occurredAt = nil
        } else {
            occurredAt = composeDate(
                date: dateCandidates.first,
                time: timeCandidates.first,
                context: context,
                calendar: calendar
            )
        }

        var consumedRanges = dateCandidates.map(\.range) + timeCandidates.map(\.range)
        let maskedCommand = replacing(ranges: consumedRanges, in: command)
        let amountCandidates = amountCandidates(
            in: maskedCommand,
            context: context
        )
        let hasAmountConflict = amountCandidates.count > 1
        let amountCandidate = hasAmountConflict ? nil : amountCandidates.first

        if let amountCandidate {
            consumedRanges.append(amountCandidate.range)
        } else if hasAmountConflict {
            consumedRanges.append(contentsOf: amountCandidates.map(\.range))
        }

        return TransactionCommandResult(
            amount: amountCandidate?.amount,
            kind: amountCandidate?.sign == "+" ? .income : .expense,
            description: cleanedDescription(
                replacing(ranges: consumedRanges, in: command)
            ),
            occurredAt: occurredAt,
            amountConflict: hasAmountConflict,
            dateConflict: hasDateConflict
        )
    }

    private func explicitDateCandidates(
        in command: String,
        expression: NSRegularExpression,
        calendar: Calendar,
        componentOrder: (year: Int, month: Int, day: Int)
    ) -> [DateCandidate] {
        let fullRange = NSRange(command.startIndex..<command.endIndex, in: command)
        return expression.matches(in: command, range: fullRange).map { match in
            let year = integer(in: command, range: match.range(at: componentOrder.year))
            let month = integer(in: command, range: match.range(at: componentOrder.month))
            let day = integer(in: command, range: match.range(at: componentOrder.day))
            let components = DateComponents(year: year, month: month, day: day)
            let isValid = validDateComponents(components, calendar: calendar)

            return DateCandidate(
                range: match.range,
                components: isValid ? components : nil,
                isValid: isValid
            )
        }
    }

    private func relativeDateCandidates(
        in command: String,
        context: TransactionCommandContext,
        calendar: Calendar
    ) -> [DateCandidate] {
        let fullRange = NSRange(command.startIndex..<command.endIndex, in: command)
        return Self.relativeDateExpression.matches(in: command, range: fullRange).map { match in
            guard let rawValue = substring(command, range: match.range(at: 1)) else {
                return DateCandidate(range: match.range, components: nil, isValid: false)
            }

            let value = rawValue.lowercased()
            let dayOffset: Int
            switch value {
            case "today":
                dayOffset = 0
            case "yesterday":
                dayOffset = -1
            case "day before yesterday", "two days ago":
                dayOffset = -2
            default:
                let count = Int(value.split(separator: " ").first ?? "") ?? 0
                dayOffset = -min(count, 36_500)
            }

            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: context.now) else {
                return DateCandidate(range: match.range, components: nil, isValid: false)
            }

            return DateCandidate(
                range: match.range,
                components: calendar.dateComponents([.year, .month, .day], from: date),
                isValid: true
            )
        }
    }

    private func englishDateCandidates(
        in command: String,
        expression: NSRegularExpression,
        calendar: Calendar,
        componentOrder: (year: Int, month: Int, day: Int)
    ) -> [DateCandidate] {
        let fullRange = NSRange(command.startIndex..<command.endIndex, in: command)
        return expression.matches(in: command, range: fullRange).map { match in
            let year = integer(in: command, range: match.range(at: componentOrder.year))
            let day = integer(in: command, range: match.range(at: componentOrder.day))
            let month = substring(command, range: match.range(at: componentOrder.month))
                .flatMap(monthNumber)
            let components = DateComponents(year: year, month: month, day: day)
            let isValid = validDateComponents(components, calendar: calendar)

            return DateCandidate(
                range: match.range,
                components: isValid ? components : nil,
                isValid: isValid
            )
        }
    }

    private func composeDate(
        date: DateCandidate?,
        time: TimeCandidate?,
        context: TransactionCommandContext,
        calendar: Calendar
    ) -> Date? {
        guard date != nil || time != nil else { return nil }

        let defaultDate = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: context.now
        )
        var components = DateComponents()
        components.timeZone = context.timeZone
        components.year = date?.components?.year ?? defaultDate.year
        components.month = date?.components?.month ?? defaultDate.month
        components.day = date?.components?.day ?? defaultDate.day
        components.hour = time?.hour ?? defaultDate.hour
        components.minute = time?.minute ?? defaultDate.minute
        components.second = time == nil ? defaultDate.second : 0

        guard let result = calendar.date(from: components) else { return nil }
        let resolved = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: result
        )
        guard
            resolved.year == components.year,
            resolved.month == components.month,
            resolved.day == components.day,
            resolved.hour == components.hour,
            resolved.minute == components.minute
        else {
            return nil
        }

        return result
    }

    private func amountCandidates(
        in command: String,
        context: TransactionCommandContext
    ) -> [AmountCandidate] {
        let escapedCurrency = context.currencyCode.map(NSRegularExpression.escapedPattern(for:))
        let currency = escapedCurrency.map { "(?:\($0)|[$€£¥₸])" } ?? "[$€£¥₸]"
        let pattern = "(?<![\\p{L}\\p{N}.,-])([+\\-−＋－]?)(?:\(currency)\\s*)?((?:\\d{1,3}(?:[ \\u00A0\\u202F'.,]\\d{3})+(?:[.,]\\d{1,4})?|\\d+(?:[.,]\\d{1,4})?))(?![\\p{L}\\p{N}.,-])"
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return []
        }

        let fullRange = NSRange(command.startIndex..<command.endIndex, in: command)
        return expression.matches(in: command, range: fullRange).compactMap { match in
            guard
                let number = substring(command, range: match.range(at: 2)),
                let amount = parseTransactionDecimal(number, locale: context.locale)
            else {
                return nil
            }

            let sign = substring(command, range: match.range(at: 1)) ?? ""
            return AmountCandidate(
                range: match.range,
                amount: abs(amount),
                sign: sign == "＋" ? "+" : sign
            )
        }
    }
}

private func parseTime(_ value: String) -> (hour: Int, minute: Int)? {
    var normalized = value
        .lowercased()
        .replacingOccurrences(of: " ", with: "")
    let isAM = normalized.hasSuffix("am")
    let isPM = normalized.hasSuffix("pm")
    if isAM || isPM {
        normalized.removeLast(2)
    }

    let parts = normalized.split(separator: ":", omittingEmptySubsequences: false)
    guard let firstPart = parts.first, let rawHour = Int(firstPart) else {
        return nil
    }

    let minute: Int
    if parts.count == 2 {
        guard let parsedMinute = Int(parts[1]) else { return nil }
        minute = parsedMinute
    } else {
        minute = 0
    }
    guard (0...59).contains(minute) else { return nil }

    if isAM || isPM {
        guard (1...12).contains(rawHour) else { return nil }
        let hour = (rawHour % 12) + (isPM ? 12 : 0)
        return (hour, minute)
    }

    guard (0...23).contains(rawHour), parts.count == 2 else { return nil }
    return (rawHour, minute)
}

func parseTransactionDecimal(_ value: String, locale: Locale) -> Decimal? {
    var number = value
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "\u{00A0}", with: "")
        .replacingOccurrences(of: "\u{202F}", with: "")
        .replacingOccurrences(of: "'", with: "")

    let dotOffsets = number.indices.filter { number[$0] == "." }
    let commaOffsets = number.indices.filter { number[$0] == "," }
    let formatter = NumberFormatter()
    formatter.locale = locale
    let localeDecimal = formatter.decimalSeparator ?? "."
    let localeGrouping = formatter.groupingSeparator ?? ","

    if !dotOffsets.isEmpty && !commaOffsets.isEmpty {
        let decimalSeparator = dotOffsets.last! > commaOffsets.last! ? "." : ","
        let groupingSeparator = decimalSeparator == "." ? "," : "."
        number = number.replacingOccurrences(of: groupingSeparator, with: "")
        number = number.replacingOccurrences(of: decimalSeparator, with: ".")
    } else if !dotOffsets.isEmpty || !commaOffsets.isEmpty {
        let separator = dotOffsets.isEmpty ? "," : "."
        let parts = number.split(separator: Character(separator), omittingEmptySubsequences: false)

        if parts.count > 2 && parts.dropFirst().allSatisfy({ $0.count == 3 }) {
            number = parts.joined()
        } else if parts.count == 2 {
            let trailingCount = parts[1].count
            let isLocaleGrouping = separator == localeGrouping && separator != localeDecimal
            if isLocaleGrouping && trailingCount == 3 {
                number = parts.joined()
            } else {
                number = number.replacingOccurrences(of: separator, with: ".")
            }
        } else if parts.count > 2 {
            let decimalPart = parts.last ?? ""
            let integerPart = parts.dropLast().joined()
            number = "\(integerPart).\(decimalPart)"
        }
    }

    return Decimal(string: number, locale: Locale(identifier: "en_US_POSIX"))
}

func canonicalTransactionAmount(_ value: String, locale: Locale) -> String? {
    guard let amount = parseTransactionDecimal(value, locale: locale), amount > 0 else {
        return nil
    }

    var source = amount
    var rounded = Decimal()
    NSDecimalRound(&rounded, &source, 4, .plain)
    guard rounded == amount else { return nil }

    let result = NSDecimalNumber(decimal: rounded).stringValue
    let integerPart = result.split(separator: ".", omittingEmptySubsequences: false).first ?? ""
    guard integerPart.count <= 15 else { return nil }
    return result
}

private func validDateComponents(_ components: DateComponents, calendar: Calendar) -> Bool {
    guard let date = calendar.date(from: components) else { return false }
    let resolved = calendar.dateComponents([.year, .month, .day], from: date)
    return resolved.year == components.year &&
        resolved.month == components.month &&
        resolved.day == components.day
}

private func integer(in value: String, range: NSRange) -> Int? {
    substring(value, range: range).flatMap(Int.init)
}

private func monthNumber(_ value: String) -> Int? {
    switch value.lowercased().prefix(3) {
    case "jan": 1
    case "feb": 2
    case "mar": 3
    case "apr": 4
    case "may": 5
    case "jun": 6
    case "jul": 7
    case "aug": 8
    case "sep": 9
    case "oct": 10
    case "nov": 11
    case "dec": 12
    default: nil
    }
}

private func substring(_ value: String, range: NSRange) -> String? {
    guard range.location != NSNotFound, let swiftRange = Range(range, in: value) else {
        return nil
    }
    return String(value[swiftRange])
}

private func replacing(ranges: [NSRange], in value: String) -> String {
    let mutable = NSMutableString(string: value)
    for range in ranges.sorted(by: { $0.location > $1.location }) where range.location != NSNotFound {
        mutable.replaceCharacters(
            in: range,
            with: String(repeating: " ", count: range.length)
        )
    }
    return mutable as String
}

private func cleanedDescription(_ value: String) -> String {
    value
        .replacingOccurrences(
            of: #"[$€£¥₸]+"#,
            with: " ",
            options: .regularExpression
        )
        .replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        .trimmingCharacters(
            in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.;:-"))
        )
}

private func rangesOverlap(_ left: NSRange, _ right: NSRange) -> Bool {
    NSIntersectionRange(left, right).length > 0
}
