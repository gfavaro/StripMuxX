@testable import AppBundle
import XCTest

@MainActor
final class ConfigurationReferenceTest: WorkspaceTestCase {

    func testExamplesParseAsIndependentConfigurationSnippets() {
        for section in configurationReferenceSections {
            guard let example = section.example else { continue }
            let result = parseConfig("config-version = 2\n" + example)
            XCTAssertTrue(result.errors.isEmpty, "\(section.id): \(result.errors)")
        }
    }

    func testReferenceUsesAppDefaultsInsteadOfPersonalValues() {
        config.startAtLogin = !defaultConfig.startAtLogin
        let section = configurationReferenceSections.first { $0.id == "general" }
        XCTAssertTrue(section?.defaults?.contains("start-at-login = \(defaultConfig.startAtLogin)") == true)
    }
}
