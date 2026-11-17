import XCTest
@testable import PhoneBox

@MainActor
final class PanelPreferencesTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "pbmac-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testDefaults() {
        let prefs = PanelPreferences(defaults: makeDefaults())
        XCTAssertFalse(prefs.alwaysOnTop)
        XCTAssertEqual(prefs.opacity, 1.0)
    }

    func testValuesPersistAndOpacityIsClamped() {
        let defaults = makeDefaults()
        let prefs = PanelPreferences(defaults: defaults)
        prefs.alwaysOnTop = true
        prefs.opacity = 0.05
        XCTAssertEqual(prefs.opacity, PanelPreferences.opacityRange.lowerBound)
        let reloaded = PanelPreferences(defaults: defaults)
        XCTAssertTrue(reloaded.alwaysOnTop)
        XCTAssertEqual(reloaded.opacity, PanelPreferences.opacityRange.lowerBound)
    }
}
