import Foundation
@testable import FinanceTracker

struct CategoryBenchmarkCase {
    let description: String
    let expectedSystemKey: String
}

struct HistoryLearningCase {
    let description: String
    let historicalDescriptions: [String]
    let expectedSystemKey: String
}

enum CategoryBenchmarkCorpus {
    struct Seed {
        let systemKey: String
        let name: String
        let kind: TransactionKind
        let examples: [String]
    }

    static let seeds: [Seed] = [
        Seed(systemKey: "expense.food-drink", name: "Food & Drink", kind: .expense, examples: ["coffee", "cafe", "restaurant", "lunch", "dinner", "takeaway", "fast food", "bakery"]),
        Seed(systemKey: "expense.groceries", name: "Groceries", kind: .expense, examples: ["supermarket", "grocery store", "vegetables", "food market", "food shopping", "butcher", "produce", "pantry"]),
        Seed(systemKey: "expense.fuel", name: "Fuel", kind: .expense, examples: ["gas", "gasoline", "petrol", "diesel", "fuel station", "service station", "charging station", "car fuel"]),
        Seed(systemKey: "expense.transport", name: "Transport", kind: .expense, examples: ["taxi", "bus", "train", "subway", "ride share", "parking", "toll road", "public transit"]),
        Seed(systemKey: "expense.housing", name: "Housing", kind: .expense, examples: ["rent", "mortgage", "property maintenance", "home repair", "apartment", "homeowners association", "landlord", "property fee"]),
        Seed(systemKey: "expense.utilities", name: "Utilities", kind: .expense, examples: ["electricity", "water bill", "heating", "natural gas bill", "internet bill", "phone bill", "waste collection", "utility bill"]),
        Seed(systemKey: "expense.shopping", name: "Shopping", kind: .expense, examples: ["clothes", "electronics", "online order", "department store", "shoes", "household goods", "retail", "purchase"]),
        Seed(systemKey: "expense.health", name: "Health", kind: .expense, examples: ["pharmacy", "doctor", "dentist", "hospital", "clinic", "medicine", "therapy", "optician"]),
        Seed(systemKey: "expense.insurance", name: "Insurance", kind: .expense, examples: ["car insurance", "health insurance", "home insurance", "life insurance", "insurance premium", "policy payment", "insurer", "coverage"]),
        Seed(systemKey: "expense.entertainment", name: "Entertainment", kind: .expense, examples: ["cinema", "movie", "concert", "video game", "museum", "streaming rental", "nightclub", "event ticket"]),
        Seed(systemKey: "expense.education", name: "Education", kind: .expense, examples: ["school", "tuition", "course", "textbooks", "training", "university", "class", "exam fee"]),
        Seed(systemKey: "expense.travel", name: "Travel", kind: .expense, examples: ["hotel", "flight", "vacation", "luggage", "travel booking", "hostel", "resort", "sightseeing"]),
        Seed(systemKey: "expense.subscriptions", name: "Subscriptions", kind: .expense, examples: ["video subscription", "music subscription", "membership", "software subscription", "monthly plan", "cloud storage", "newspaper subscription", "app subscription"]),
        Seed(systemKey: "expense.fees-charges", name: "Fees & Charges", kind: .expense, examples: ["bank fee", "service charge", "commission", "late fee", "atm fee", "interest charge", "penalty", "transaction fee"]),
        Seed(systemKey: "expense.gifts-donations", name: "Gifts & Donations", kind: .expense, examples: ["charity", "donation", "present", "birthday gift", "fundraiser", "nonprofit", "church donation", "gift for friend"]),
        Seed(systemKey: "expense.other", name: "Other", kind: .expense, examples: ["miscellaneous", "uncategorized", "unknown expense", "cash expense"]),
        Seed(systemKey: "income.salary", name: "Salary", kind: .income, examples: ["salary", "paycheck", "wages", "payroll", "bonus", "employer payment", "monthly pay", "compensation"]),
        Seed(systemKey: "income.business-freelance", name: "Business & Freelance", kind: .income, examples: ["freelance", "client payment", "invoice paid", "consulting", "side job", "business income", "contract work", "sales revenue"]),
        Seed(systemKey: "income.investments", name: "Investments", kind: .income, examples: ["dividend", "interest income", "capital gain", "investment return", "bond interest", "stock income", "portfolio payout", "savings interest"]),
        Seed(systemKey: "income.refunds", name: "Refunds", kind: .income, examples: ["refund", "reimbursement", "cashback", "returned purchase", "chargeback", "rebate", "tax refund", "repayment"]),
        Seed(systemKey: "income.gifts-received", name: "Gifts Received", kind: .income, examples: ["gift received", "birthday money", "family gift", "cash gift", "present money", "donation received", "inheritance", "prize"]),
        Seed(systemKey: "income.other", name: "Other", kind: .income, examples: ["other income", "cash income", "deposit", "credit received", "money received", "incoming payment", "windfall", "unknown income"]),
    ]

    // The first five phrases per category form calibration; the last five are holdout.
    // No full phrase duplicates a category name or seeded example.
    static let coldStartPhrases: [String: [String]] = [
        "expense.food-drink": [
            "coffee before work", "cafe near the station", "restaurant with friends", "lunch at the office", "dinner downtown",
            "takeaway after class", "fast food stop", "bakery on main street", "iced coffee run", "neighborhood cafe visit",
        ],
        "expense.groceries": [
            "weekly supermarket run", "grocery store basket", "vegetables for the week", "saturday food market", "family food shopping",
            "local butcher visit", "fresh produce haul", "pantry restock", "supermarket essentials", "grocery store checkout",
        ],
        "expense.fuel": [
            "gas for the car", "gasoline refill downtown", "petrol before the trip", "diesel at highway stop", "fuel station visit",
            "service station fill up", "charging station session", "monthly car fuel", "late night gas stop", "diesel refill receipt",
        ],
        "expense.transport": [
            "taxi to the airport", "bus fare downtown", "train ticket home", "subway ride to work", "ride share after dinner",
            "parking near office", "toll road payment", "public transit pass", "morning bus fare", "train commute ticket",
        ],
        "expense.housing": [
            "rent for september", "monthly mortgage payment", "property maintenance visit", "home repair supplies", "apartment payment",
            "homeowners association dues", "payment to landlord", "annual property fee", "rent for the flat", "emergency home repair",
        ],
        "expense.utilities": [
            "electricity for august", "water bill payment", "heating for winter", "natural gas bill paid", "internet bill this month",
            "phone bill autopay", "waste collection invoice", "quarterly utility bill", "apartment electricity", "overdue water bill",
        ],
        "expense.shopping": [
            "clothes for autumn", "new electronics purchase", "online order delivery", "department store visit", "running shoes purchase",
            "household goods basket", "weekend retail purchase", "purchase at the mall", "winter clothes order", "electronics for home",
        ],
        "expense.health": [
            "pharmacy prescription pickup", "doctor appointment fee", "dentist checkup", "hospital copay", "clinic consultation",
            "medicine for a cold", "therapy session", "optician eye test", "late night pharmacy", "annual doctor visit",
        ],
        "expense.insurance": [
            "car insurance renewal", "health insurance monthly payment", "home insurance renewal", "life insurance installment", "insurance premium due",
            "policy payment for august", "payment to insurer", "extra travel coverage", "annual car insurance", "family health insurance",
        ],
        "expense.entertainment": [
            "cinema on friday", "movie with friends", "concert next month", "new video game", "museum entry",
            "streaming rental tonight", "nightclub cover", "event ticket purchase", "weekend cinema visit", "concert seat upgrade",
        ],
        "expense.education": [
            "school activity payment", "tuition for fall term", "online course enrollment", "textbooks for semester", "professional training day",
            "university application payment", "evening class fee", "exam fee for certification", "school supplies payment", "new course registration",
        ],
        "expense.travel": [
            "hotel for three nights", "flight to london", "summer vacation booking", "extra luggage payment", "travel booking deposit",
            "hostel in berlin", "beach resort stay", "city sightseeing pass", "airport hotel night", "return flight upgrade",
        ],
        "expense.subscriptions": [
            "video subscription renewal", "music subscription family plan", "gym membership renewal", "software subscription for work", "monthly plan renewal",
            "cloud storage upgrade", "newspaper subscription renewal", "app subscription charge", "annual membership payment", "software subscription invoice",
        ],
        "expense.fees-charges": [
            "bank fee on transfer", "service charge at venue", "broker commission paid", "late fee on card", "atm fee abroad",
            "interest charge this month", "cancellation penalty", "transaction fee on payment", "unexpected bank fee", "late fee adjustment",
        ],
        "expense.gifts-donations": [
            "charity after the race", "donation to relief fund", "present for mum", "birthday gift for alex", "school fundraiser support",
            "local nonprofit support", "church donation on sunday", "gift for friend wedding", "holiday charity appeal", "birthday gift wrapping",
        ],
        "expense.other": [
            "miscellaneous weekend spending", "uncategorized counter payment", "unknown expense from kiosk", "cash expense at market", "miscellaneous receipt",
            "uncategorized small purchase", "unknown expense review", "cash expense without receipt", "miscellaneous one off", "uncategorized card item",
        ],
        "income.salary": [
            "salary for august", "monthly paycheck arrived", "weekly wages received", "payroll from employer", "performance bonus received",
            "employer payment for work", "monthly pay deposited", "annual compensation payment", "salary adjustment", "paycheck from office",
        ],
        "income.business-freelance": [
            "freelance design project", "client payment received", "invoice paid by customer", "consulting engagement payment", "side job earnings",
            "business income for august", "contract work payout", "sales revenue received", "freelance writing payment", "client payment for website",
        ],
        "income.investments": [
            "quarterly dividend received", "interest income credited", "capital gain distribution", "investment return payout", "bond interest received",
            "stock income this quarter", "portfolio payout received", "savings interest credited", "dividend from shares", "investment return for fund",
        ],
        "income.refunds": [
            "refund from shop", "travel reimbursement received", "card cashback posted", "returned purchase credit", "merchant chargeback received",
            "energy rebate received", "tax refund deposited", "friend repayment received", "partial refund issued", "cashback from card",
        ],
        "income.gifts-received": [
            "gift received from family", "birthday money from aunt", "family gift transfer", "cash gift at wedding", "present money from grandparents",
            "donation received for project", "inheritance payment received", "competition prize received", "birthday money transfer", "cash gift from friend",
        ],
        "income.other": [
            "other income this week", "cash income received", "deposit from unknown source", "credit received on account", "money received by transfer",
            "incoming payment to review", "unexpected windfall received", "unknown income item", "other income adjustment", "cash income at event",
        ],
    ]

    // Merchant-heavy cases exercise the optional model only after the pinned baseline
    // declines to answer. A physical-device run filters these through the baseline first.
    static let modelGateHoldout: [CategoryBenchmarkCase] = [
        CategoryBenchmarkCase(description: "Blue Bottle downtown", expectedSystemKey: "expense.food-drink"),
        CategoryBenchmarkCase(description: "Pret A Manger", expectedSystemKey: "expense.food-drink"),
        CategoryBenchmarkCase(description: "Nandos city center", expectedSystemKey: "expense.food-drink"),
        CategoryBenchmarkCase(description: "Trader Joes weekly run", expectedSystemKey: "expense.groceries"),
        CategoryBenchmarkCase(description: "Aldi neighborhood branch", expectedSystemKey: "expense.groceries"),
        CategoryBenchmarkCase(description: "Whole Foods checkout", expectedSystemKey: "expense.groceries"),
        CategoryBenchmarkCase(description: "Shell northbound", expectedSystemKey: "expense.fuel"),
        CategoryBenchmarkCase(description: "Chevron pump seven", expectedSystemKey: "expense.fuel"),
        CategoryBenchmarkCase(description: "Exxon roadside", expectedSystemKey: "expense.fuel"),
        CategoryBenchmarkCase(description: "Uber home", expectedSystemKey: "expense.transport"),
        CategoryBenchmarkCase(description: "Lyft airport", expectedSystemKey: "expense.transport"),
        CategoryBenchmarkCase(description: "Metrocard reload", expectedSystemKey: "expense.transport"),
        CategoryBenchmarkCase(description: "Greystar resident portal", expectedSystemKey: "expense.housing"),
        CategoryBenchmarkCase(description: "Camden resident payment", expectedSystemKey: "expense.housing"),
        CategoryBenchmarkCase(description: "Equity Residential portal", expectedSystemKey: "expense.housing"),
        CategoryBenchmarkCase(description: "Con Edison autopay", expectedSystemKey: "expense.utilities"),
        CategoryBenchmarkCase(description: "Comcast Xfinity", expectedSystemKey: "expense.utilities"),
        CategoryBenchmarkCase(description: "Verizon Fios", expectedSystemKey: "expense.utilities"),
        CategoryBenchmarkCase(description: "Zara city mall", expectedSystemKey: "expense.shopping"),
        CategoryBenchmarkCase(description: "Ikea warehouse", expectedSystemKey: "expense.shopping"),
        CategoryBenchmarkCase(description: "Amazon marketplace", expectedSystemKey: "expense.shopping"),
        CategoryBenchmarkCase(description: "CVS prescription counter", expectedSystemKey: "expense.health"),
        CategoryBenchmarkCase(description: "Kaiser Permanente copay", expectedSystemKey: "expense.health"),
        CategoryBenchmarkCase(description: "Walgreens pickup", expectedSystemKey: "expense.health"),
        CategoryBenchmarkCase(description: "Geico renewal", expectedSystemKey: "expense.insurance"),
        CategoryBenchmarkCase(description: "Aetna monthly debit", expectedSystemKey: "expense.insurance"),
        CategoryBenchmarkCase(description: "State Farm renewal", expectedSystemKey: "expense.insurance"),
        CategoryBenchmarkCase(description: "AMC Friday night", expectedSystemKey: "expense.entertainment"),
        CategoryBenchmarkCase(description: "Steam store", expectedSystemKey: "expense.entertainment"),
        CategoryBenchmarkCase(description: "Ticketmaster seats", expectedSystemKey: "expense.entertainment"),
        CategoryBenchmarkCase(description: "Coursera certificate", expectedSystemKey: "expense.education"),
        CategoryBenchmarkCase(description: "Udemy enrollment", expectedSystemKey: "expense.education"),
        CategoryBenchmarkCase(description: "Pearson learning portal", expectedSystemKey: "expense.education"),
        CategoryBenchmarkCase(description: "Marriott Bonvoy", expectedSystemKey: "expense.travel"),
        CategoryBenchmarkCase(description: "Delta Air Lines", expectedSystemKey: "expense.travel"),
        CategoryBenchmarkCase(description: "Airbnb reservation", expectedSystemKey: "expense.travel"),
        CategoryBenchmarkCase(description: "Netflix renewal", expectedSystemKey: "expense.subscriptions"),
        CategoryBenchmarkCase(description: "Spotify family", expectedSystemKey: "expense.subscriptions"),
        CategoryBenchmarkCase(description: "iCloud plus", expectedSystemKey: "expense.subscriptions"),
        CategoryBenchmarkCase(description: "NSF item debit", expectedSystemKey: "expense.fees-charges"),
        CategoryBenchmarkCase(description: "FX markup debit", expectedSystemKey: "expense.fees-charges"),
        CategoryBenchmarkCase(description: "wire handling debit", expectedSystemKey: "expense.fees-charges"),
        CategoryBenchmarkCase(description: "GoFundMe support", expectedSystemKey: "expense.gifts-donations"),
        CategoryBenchmarkCase(description: "UNICEF appeal", expectedSystemKey: "expense.gifts-donations"),
        CategoryBenchmarkCase(description: "Red Cross appeal", expectedSystemKey: "expense.gifts-donations"),
        CategoryBenchmarkCase(description: "corner kiosk item", expectedSystemKey: "expense.other"),
        CategoryBenchmarkCase(description: "unlabeled cash out", expectedSystemKey: "expense.other"),
        CategoryBenchmarkCase(description: "one off counter item", expectedSystemKey: "expense.other"),
        CategoryBenchmarkCase(description: "ADP direct dep", expectedSystemKey: "income.salary"),
        CategoryBenchmarkCase(description: "Gusto work deposit", expectedSystemKey: "income.salary"),
        CategoryBenchmarkCase(description: "Workday net pay", expectedSystemKey: "income.salary"),
        CategoryBenchmarkCase(description: "Stripe creator payout", expectedSystemKey: "income.business-freelance"),
        CategoryBenchmarkCase(description: "Upwork milestone", expectedSystemKey: "income.business-freelance"),
        CategoryBenchmarkCase(description: "Fiverr seller proceeds", expectedSystemKey: "income.business-freelance"),
        CategoryBenchmarkCase(description: "Vanguard distribution", expectedSystemKey: "income.investments"),
        CategoryBenchmarkCase(description: "Fidelity sweep credit", expectedSystemKey: "income.investments"),
        CategoryBenchmarkCase(description: "Robinhood proceeds", expectedSystemKey: "income.investments"),
        CategoryBenchmarkCase(description: "merchant credit reversal", expectedSystemKey: "income.refunds"),
        CategoryBenchmarkCase(description: "IRS treasury credit", expectedSystemKey: "income.refunds"),
        CategoryBenchmarkCase(description: "airline fare reversal", expectedSystemKey: "income.refunds"),
        CategoryBenchmarkCase(description: "grandma transfer", expectedSystemKey: "income.gifts-received"),
        CategoryBenchmarkCase(description: "wedding envelope", expectedSystemKey: "income.gifts-received"),
        CategoryBenchmarkCase(description: "birthday venmo", expectedSystemKey: "income.gifts-received"),
        CategoryBenchmarkCase(description: "Zelle incoming", expectedSystemKey: "income.other"),
        CategoryBenchmarkCase(description: "unidentified ACH credit", expectedSystemKey: "income.other"),
        CategoryBenchmarkCase(description: "cashback portal proceeds", expectedSystemKey: "income.other"),
    ]

    static let historyLearningCases: [HistoryLearningCase] = [
        HistoryLearningCase(description: "bluebottle market st", historicalDescriptions: ["blue bottle market street"], expectedSystemKey: "expense.food-drink"),
        HistoryLearningCase(description: "north fuel svc", historicalDescriptions: ["north fuel service"], expectedSystemKey: "expense.fuel"),
        HistoryLearningCase(description: "marias weekly shop", historicalDescriptions: ["maria weekly shopping"], expectedSystemKey: "expense.groceries"),
        HistoryLearningCase(description: "acme payroll aug", historicalDescriptions: ["acme payroll july"], expectedSystemKey: "income.salary"),
        HistoryLearningCase(description: "studio client inv 48", historicalDescriptions: ["studio client invoice 47"], expectedSystemKey: "income.business-freelance"),
        HistoryLearningCase(description: "landlord portal sep", historicalDescriptions: ["landlord portal aug"], expectedSystemKey: "expense.housing"),
    ]

    static let categories: [TransactionCategory] = seeds.enumerated().map { index, seed in
        TransactionCategory(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
            systemKey: seed.systemKey,
            name: seed.name,
            kind: seed.kind,
            isSystem: true,
            examples: seed.examples,
            sortOrder: (index + 1) * 10,
            createdAt: nil,
            updatedAt: nil
        )
    }

    static var calibrationCases: [CategoryBenchmarkCase] {
        cases(in: 0..<5)
    }

    static var holdoutCases: [CategoryBenchmarkCase] {
        cases(in: 5..<10)
    }

    private static func cases(in range: Range<Int>) -> [CategoryBenchmarkCase] {
        seeds.flatMap { seed in
            (coldStartPhrases[seed.systemKey] ?? [])[range].map {
                CategoryBenchmarkCase(
                    description: $0,
                    expectedSystemKey: seed.systemKey
                )
            }
        }
    }
}
