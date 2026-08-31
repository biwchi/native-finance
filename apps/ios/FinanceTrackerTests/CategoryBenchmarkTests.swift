import XCTest
@testable import FinanceTracker

final class CategoryBenchmarkTests: XCTestCase {
    func testCorpusHasRequiredCoverageAndNoSeedDuplicates() {
        XCTAssertEqual(CategoryBenchmarkCorpus.seeds.count, 22)
        XCTAssertGreaterThanOrEqual(CategoryBenchmarkCorpus.modelGateHoldout.count, 50)
        XCTAssertFalse(CategoryBenchmarkCorpus.historyLearningCases.isEmpty)

        for seed in CategoryBenchmarkCorpus.seeds {
            let phrases = CategoryBenchmarkCorpus.coldStartPhrases[seed.systemKey] ?? []
            XCTAssertGreaterThanOrEqual(phrases.count, 10, seed.systemKey)

            let seededValues = Set(([seed.name] + seed.examples).map(LocalCategoryMatcher.normalize))
            for phrase in phrases {
                XCTAssertFalse(
                    seededValues.contains(LocalCategoryMatcher.normalize(phrase)),
                    "\(seed.systemKey) duplicates a seed: \(phrase)"
                )
            }
        }
    }

    func testCalibrationMaintainsAtLeastNinetyFivePercentPrecision() {
        let metrics = evaluate(CategoryBenchmarkCorpus.calibrationCases)

        XCTAssertGreaterThanOrEqual(metrics.precision, 0.95)
        XCTAssertGreaterThanOrEqual(metrics.coverage, 0.95)
    }

    func testCheckedHoldoutMaintainsAtLeastNinetyFivePercentPrecision() {
        let metrics = evaluate(CategoryBenchmarkCorpus.holdoutCases)

        XCTAssertGreaterThanOrEqual(metrics.precision, 0.95)
        XCTAssertGreaterThanOrEqual(metrics.coverage, 0.95)
    }

    func testModelGateCorpusLeavesAtLeastFiftyCasesForBaselineFiltering() {
        let unresolved = CategoryBenchmarkCorpus.modelGateHoldout.filter { item in
            guard let expected = category(for: item.expectedSystemKey) else { return false }
            let sameKind = CategoryBenchmarkCorpus.categories.filter { $0.kind == expected.kind }
            return LocalCategoryMatcher.resolve(
                description: item.description,
                categories: sameKind
            ) == nil
        }

        XCTAssertGreaterThanOrEqual(
            unresolved.count,
            50,
            "Refresh model-gate cases when the pinned embedding revision changes"
        )
    }

    private func evaluate(
        _ cases: [CategoryBenchmarkCase]
    ) -> (precision: Double, coverage: Double) {
        var resolved = 0
        var correct = 0

        for item in cases {
            guard let expected = category(for: item.expectedSystemKey) else {
                XCTFail("Missing fixture category \(item.expectedSystemKey)")
                continue
            }

            let sameKind = CategoryBenchmarkCorpus.categories.filter { $0.kind == expected.kind }
            guard let result = LocalCategoryMatcher.resolve(
                description: item.description,
                categories: sameKind
            ) else {
                continue
            }

            resolved += 1
            if result.categoryID == expected.id {
                correct += 1
            }
        }

        return (
            precision: resolved == 0 ? 0 : Double(correct) / Double(resolved),
            coverage: cases.isEmpty ? 0 : Double(resolved) / Double(cases.count)
        )
    }

    private func category(for systemKey: String) -> TransactionCategory? {
        CategoryBenchmarkCorpus.categories.first { $0.systemKey == systemKey }
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
final class FoundationModelBenchmarkTests: XCTestCase {
    func testFoundationResolverMeetsReleaseGate() async throws {
#if targetEnvironment(simulator)
        throw XCTSkip("The Foundation Models release gate requires an eligible physical device")
#else
        guard ProcessInfo.processInfo.environment["RUN_FOUNDATION_MODEL_BENCHMARK"] == "1" else {
            throw XCTSkip("Set RUN_FOUNDATION_MODEL_BENCHMARK=1 for an intentional release-gate run")
        }

        let unresolved = CategoryBenchmarkCorpus.modelGateHoldout.filter { item in
            guard let expected = category(for: item.expectedSystemKey) else { return false }
            let sameKind = CategoryBenchmarkCorpus.categories.filter { $0.kind == expected.kind }
            return LocalCategoryMatcher.resolve(
                description: item.description,
                categories: sameKind
            ) == nil
        }
        XCTAssertGreaterThanOrEqual(unresolved.count, 50, "The benchmark sample is insufficient")

        var filled = 0
        var correct = 0
        var latencies: [TimeInterval] = []

        for item in unresolved {
            guard let expected = category(for: item.expectedSystemKey) else { continue }
            let sameKind = CategoryBenchmarkCorpus.categories.filter { $0.kind == expected.kind }
            let start = Date()
            let result = await FoundationCategoryResolver.resolve(
                description: item.description,
                categories: sameKind
            )
            latencies.append(Date().timeIntervalSince(start))

            if let result {
                filled += 1
                if result.categoryID == expected.id {
                    correct += 1
                }
            }
        }

        XCTAssertGreaterThan(filled, 0, "The model was unavailable or filled no cases")
        let accuracy = Double(correct) / Double(filled)
        let coverageLift = Double(filled) / Double(CategoryBenchmarkCorpus.modelGateHoldout.count)
        let sortedLatencies = latencies.sorted()
        let p95Index = max(0, Int(ceil(Double(sortedLatencies.count) * 0.95)) - 1)
        let p95 = sortedLatencies[p95Index]

        XCTAssertGreaterThanOrEqual(accuracy, 0.95)
        XCTAssertGreaterThanOrEqual(coverageLift, 0.10)
        XCTAssertLessThanOrEqual(p95, 2.0)
#endif
    }

    private func category(for systemKey: String) -> TransactionCategory? {
        CategoryBenchmarkCorpus.categories.first { $0.systemKey == systemKey }
    }
}
#endif
