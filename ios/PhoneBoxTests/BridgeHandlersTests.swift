import UIKit
import XCTest
@testable import PhoneBox

@MainActor
private final class FakeHaptics: HapticsPlaying {
    var impacts = 0
    var buzzes: [[Int]] = []
    func impact() { impacts += 1 }
    func buzz(_ pattern: [Int]) { buzzes.append(pattern) }
}

private final class FakeScreen: BrightnessScreen {
    var brightness: CGFloat = 0.8
}

private actor FakeComputers: PairedComputerSource {
    var state: PairedState
    var selected: [String] = []
    var routeValue: AgentRoute = .wifi
    init(_ state: PairedState) { self.state = state }
    var computers: PairedState { state }
    var route: AgentRoute { routeValue }
    func select(_ id: String) throws { selected.append(id); state.select(id) }
    func forget(_ id: String) throws { state.forget(id) }
}

private final class StubEngine: SpeechEngine {
    var isAvailable: Bool { true }
    func requestPermissions(_ done: @escaping @MainActor (SpeechPermission) -> Void) { done(.granted) }
    func start(lang: String, onDevice: Bool, onEvent: @escaping @MainActor (SpeechEvent) -> Void) throws {}
    func stop() {}
    func cancel() {}
}

@MainActor
final class BridgeHandlersTests: XCTestCase {
    private let a = PairedComputer(id: String(repeating: "a", count: 64), name: "Desk", hosts: ["10.0.0.2"], port: 8766, token: "t")
    private let b = PairedComputer(id: String(repeating: "b", count: 64), name: "Laptop", hosts: ["10.0.0.3"], port: 8766, token: "t")
    private var savedMask: UIInterfaceOrientationMask = .landscape

    override func setUp() { savedMask = OrientationLock.mask }
    override func tearDown() { OrientationLock.mask = savedMask }

    private func makeBridge(computers: (any PairedComputerSource)? = nil, haptics: FakeHaptics? = nil,
                            screen: FakeScreen? = nil) -> NativeBridge {
        let haptics = haptics ?? FakeHaptics()
        let screen = screen ?? FakeScreen()
        return NativeBridge(key: "k", computers: computers, haptics: haptics, brightness: BrightnessController(screen: { screen }),
                     orientation: OrientationController(refresh: { _ in }), dictation: SpeechDictation(engine: StubEngine()),
                     shimTemplate: "KEY=__KEY__;STATE=__STATE__;")
    }

    func testHapticAndBuzzReachHaptics() {
        let haptics = FakeHaptics()
        let bridge = makeBridge(haptics: haptics)
        bridge.handle(.haptic)
        bridge.handle(.buzz([0, 80, 40, 80]))
        XCTAssertEqual(haptics.impacts, 1)
        XCTAssertEqual(haptics.buzzes, [[0, 80, 40, 80]])
    }

    func testBuzzPatternBecomesPulses() {
        let pulses = HapticPattern.pulses([0, 80, 40, 80])
        XCTAssertEqual(pulses.count, 2)
        XCTAssertEqual(pulses[0].start, 0, accuracy: 0.0001)
        XCTAssertEqual(pulses[0].duration, 0.08, accuracy: 0.0001)
        XCTAssertEqual(pulses[1].start, 0.12, accuracy: 0.0001)
        XCTAssertEqual(HapticPattern.pulses([300]), [])
        let skipped = HapticPattern.pulses([100, 0, 50, 20])
        XCTAssertEqual(skipped.count, 1)
        XCTAssertEqual(skipped[0].start, 0.15, accuracy: 0.0001)
    }

    func testBrightnessIsSavedAndRestored() {
        let screen = FakeScreen()
        let bridge = makeBridge(screen: screen)
        bridge.handle(.setBrightness(0.1))
        XCTAssertEqual(screen.brightness, 0.1, accuracy: 0.001)
        bridge.handle(.setBrightness(0.3))
        XCTAssertEqual(screen.brightness, 0.3, accuracy: 0.001)
        bridge.handle(.setBrightness(-1))
        XCTAssertEqual(screen.brightness, 0.8, accuracy: 0.001)
    }

    func testBrightnessSuspendAndResume() {
        let screen = FakeScreen()
        let controller = BrightnessController(screen: { screen })
        controller.request(0)
        XCTAssertEqual(screen.brightness, 0.01, accuracy: 0.001)
        controller.suspend()
        XCTAssertEqual(screen.brightness, 0.8, accuracy: 0.001)
        controller.resume()
        XCTAssertEqual(screen.brightness, 0.01, accuracy: 0.001)
        controller.request(-1)
        controller.resume()
        XCTAssertEqual(screen.brightness, 0.8, accuracy: 0.001)
    }

    func testOrientationUpdatesLockAndRefreshesScenes() {
        var refreshed: [UIInterfaceOrientationMask] = []
        let controller = OrientationController(refresh: { refreshed.append($0) })
        OrientationLock.mask = .landscape
        controller.set(.portrait)
        XCTAssertEqual(OrientationLock.mask, .portrait)
        controller.set(.portrait)
        controller.set(.auto)
        XCTAssertEqual(OrientationLock.mask, .allButUpsideDown)
        controller.set(.landscape)
        XCTAssertEqual(OrientationLock.mask, .landscape)
        XCTAssertEqual(refreshed, [.portrait, .allButUpsideDown, .landscape])
    }

    func testPushUpdatesSnapshotAndRunsScript() {
        let bridge = makeBridge()
        var scripts: [String] = []
        bridge.runScript = { scripts.append($0) }
        let battery = DeviceInfo.battery(level: 0.42, state: .charging)
        bridge.push(BridgeUpdate(battery: battery))
        XCTAssertEqual(bridge.snapshot.battery, BatterySnapshot(level: 42, plugged: true, temp: 0, source: ""))
        XCTAssertEqual(scripts.count, 1)
        XCTAssertTrue(scripts[0].hasPrefix("window.__pbNative && window.__pbNative.update({"))
        XCTAssertTrue(scripts[0].contains("\"level\":42"))
        XCTAssertFalse(scripts[0].contains("pcs"))
    }

    func testSnapshotFollowsPairedComputers() async {
        let state = PairedState(computers: [a, b], activeId: b.id)
        let bridge = makeBridge(computers: FakeComputers(state))
        var scripts: [String] = []
        bridge.runScript = { scripts.append($0) }
        await bridge.refreshComputers()
        XCTAssertEqual(bridge.snapshot.pcs, [BridgeComputer(id: a.id, name: "Desk", active: false),
                                              BridgeComputer(id: b.id, name: "Laptop", active: true)])
        XCTAssertEqual(bridge.snapshot.transport, "wifi")
        XCTAssertEqual(scripts.count, 1)
        XCTAssertTrue(scripts[0].contains("\"name\":\"Laptop\""))
        await bridge.refreshComputers()
        XCTAssertEqual(scripts.count, 1, "an unchanged list is not pushed again")
    }

    func testSelectPcSwitchesAndReloads() async throws {
        let fake = FakeComputers(PairedState(computers: [a, b], activeId: a.id))
        let bridge = makeBridge(computers: fake)
        let reloaded = expectation(description: "reload")
        bridge.reloadPanel = { reloaded.fulfill() }
        bridge.handle(.selectPc(b.id))
        await fulfillment(of: [reloaded], timeout: 2)
        let selected = await fake.selected
        XCTAssertEqual(selected, [b.id])
        XCTAssertEqual(bridge.snapshot.pcs.first(where: { $0.active })?.id, b.id)
    }

    func testSelectUnknownPcIsIgnored() async throws {
        let fake = FakeComputers(PairedState(computers: [a], activeId: a.id))
        let bridge = makeBridge(computers: fake)
        var reloads = 0
        bridge.reloadPanel = { reloads += 1 }
        bridge.handle(.selectPc(b.id))
        try await Task.sleep(for: .milliseconds(200))
        let selected = await fake.selected
        XCTAssertEqual(selected, [])
        XCTAssertEqual(reloads, 0)
    }

    func testShimTemplateGetsKeyAndState() throws {
        let snapshot = BridgeSnapshot(battery: DeviceInfo.battery(level: -1, state: .unknown), transport: "none", is24Hour: true,
                                      version: "0.1.0", pcs: [], canListen: false)
        let source = try XCTUnwrap(BridgeScripts.shim(template: "K='__KEY__';S=__STATE__;", key: "abc", snapshot: snapshot))
        XCTAssertTrue(source.hasPrefix("K='abc';S={"))
        XCTAssertFalse(source.contains("__STATE__"))
        XCTAssertTrue(source.contains("\"level\":-1"))
        XCTAssertTrue(source.contains("\"light\":false") && source.contains("\"proximity\":false"))
    }

    func testSpeechScriptQuotesAgentText() {
        let js = BridgeScripts.speech(kind: "final", text: "say \"hi\"\u{2028}</script>", id: 4)
        XCTAssertTrue(js.hasSuffix(", 4)"))
        XCTAssertFalse(js.contains("\u{2028}"))
        XCTAssertTrue(js.contains("\\\"hi\\\""))
    }

    func testBundledShimDefinesOnlySupportedMethods() throws {
        let shim = try XCTUnwrap(NativeBridge.bundledShim())
        for method in ["battery:", "haptic:", "buzz:", "pcs:", "listen:", "setOrientation:", "setBrightness:"] {
            XCTAssertTrue(shim.contains(method), method)
        }
        for method in ["setVolumeKeys", "setPinned", "setHomeScreen"] {
            XCTAssertFalse(shim.contains(method), "\(method) must stay out of the shim")
        }
        XCTAssertTrue(shim.contains("__KEY__") && shim.contains("__STATE__"))
    }

    func testBatteryAndClockHelpers() {
        XCTAssertEqual(DeviceInfo.battery(level: 0.555, state: .full), BatterySnapshot(level: 56, plugged: true, temp: 0, source: ""))
        XCTAssertFalse(DeviceInfo.battery(level: 0.5, state: .unplugged).plugged)
        XCTAssertEqual(DeviceInfo.battery(level: -1, state: .unknown).level, -1)
        XCTAssertTrue(DeviceInfo.is24Hour(locale: Locale(identifier: "vi_VN")) || !DeviceInfo.is24Hour(locale: Locale(identifier: "en_US")))
        XCTAssertFalse(DeviceInfo.version().isEmpty)
    }
}
