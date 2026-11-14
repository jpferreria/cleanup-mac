import Foundation
import FoundationModels

@main
struct CleanupTests {
    static func assert(_ condition: @autoclosure () -> Bool, _ message: String, file: String = #file, line: Int = #line) {
        if !condition() {
            fputs("FAIL [\(file):\(line)]: \(message)\n", stderr)
            exit(1)
        }
    }

    static func main() {
        print("Running Swift unit tests...")

        // 1. Version check
        assert(APP_VERSION == "1.1.0", "Expected APP_VERSION to be 1.1.0")
        print("  [PASS] testAppVersion")

        // 2. Categories initialization check
        let vm = CleanupViewModel()
        assert(vm.categories.count == 7, "Expected 7 cleanup categories")
        assert(vm.categories.first(where: { $0.id == "downloads_installers" })?.isInstallersOnly == true, "downloads_installers should have isInstallersOnly = true")
        print("  [PASS] testCategoriesInitialization")

        // 3. Parse valid AI JSON response (including surrounding markdown fences)
        let sampleJSON = """
        ```json
        {
          "needsCleaning": true,
          "urgencyLevel": "High",
          "explanation": "Disk is nearly full and caches are large.",
          "recommendedCategories": ["user_caches", "package_manager_caches"]
        }
        ```
        """
        let parsed = vm.parseAssessment(from: sampleJSON, totalReclaimable: 1000, usedPct: 50)
        assert(parsed.needsCleaning == true, "Expected needsCleaning == true")
        assert(parsed.urgencyLevel == "High", "Expected urgencyLevel == High")
        assert(parsed.recommendedCategories == ["user_caches", "package_manager_caches"], "Expected recommendedCategories to match")
        print("  [PASS] testParseValidAIJSON")

        // 4. Fallback heuristic when invalid JSON is returned
        let fallbackHigh = vm.heuristicAssessment(totalReclaimable: 6 * 1024 * 1024 * 1024, usedPct: 88)
        assert(fallbackHigh.needsCleaning == true, "Expected heuristic needsCleaning == true for 88% used")
        assert(fallbackHigh.urgencyLevel == "High", "Expected High urgency for 88% used")

        let fallbackLow = vm.heuristicAssessment(totalReclaimable: 10 * 1024 * 1024, usedPct: 40)
        assert(fallbackLow.needsCleaning == false, "Expected heuristic needsCleaning == false for 40% used and 10MB")
        assert(fallbackLow.urgencyLevel == "Low", "Expected Low urgency")
        print("  [PASS] testHeuristicAssessmentFallback")

        // 5. Apply AI recommendations selection toggle
        vm.aiAssessment = parsed
        vm.applyAIRecommendations()
        for cat in vm.categories {
            if cat.id == "user_caches" || cat.id == "package_manager_caches" {
                assert(cat.isSelected == true, "\(cat.id) should be selected")
            } else {
                assert(cat.isSelected == false, "\(cat.id) should be deselected")
            }
        }
        print("  [PASS] testApplyAIRecommendations")

        // 6. Verify Apple Intelligence FoundationModels framework availability API
        let availability = SystemLanguageModel.default.availability
        print("  [PASS] testFoundationModelsAvailability (status: \(availability))")

        print("All 6 Swift unit tests passed!")
    }
}
