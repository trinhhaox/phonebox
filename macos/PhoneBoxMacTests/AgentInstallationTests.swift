import XCTest
@testable import PhoneBox

final class AgentInstallationTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("pbmac-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: home) }

    private func install(binary: Bool, plist: Bool, executable: Bool = true) throws -> AgentInstallation {
        let target = AgentInstallation.standard(home: home)
        let fm = FileManager.default
        if binary {
            try fm.createDirectory(at: target.binary.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: target.binary.path, contents: Data("#!/bin/sh\n".utf8),
                          attributes: [.posixPermissions: executable ? 0o755 : 0o644])
        }
        if plist {
            try fm.createDirectory(at: target.launchAgentPlist.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: target.launchAgentPlist.path, contents: Data("<plist/>".utf8))
        }
        return target
    }

    func testPathsFollowSetupLayout() {
        let target = AgentInstallation.standard(home: home)
        XCTAssertTrue(target.binary.path.hasSuffix("Library/Application Support/PhoneBox/app/PhoneBoxAgent"))
        XCTAssertTrue(target.launchAgentPlist.path.hasSuffix("Library/LaunchAgents/net.oxog.phonebox.agent.plist"))
    }

    func testNothingInstalled() throws { XCTAssertFalse(try install(binary: false, plist: false).isInstalled()) }
    func testBinaryWithoutPlist() throws { XCTAssertFalse(try install(binary: true, plist: false).isInstalled()) }
    func testPlistWithoutBinary() throws { XCTAssertFalse(try install(binary: false, plist: true).isInstalled()) }
    func testNonExecutableBinary() throws { XCTAssertFalse(try install(binary: true, plist: true, executable: false).isInstalled()) }
    func testFullInstall() throws { XCTAssertTrue(try install(binary: true, plist: true).isInstalled()) }

    func testKickstartUsesArrayArguments() {
        XCTAssertEqual(AgentControl.kickstartArguments(uid: 501), ["kickstart", "-k", "gui/501/net.oxog.phonebox.agent"])
        XCTAssertEqual(AgentControl.kickstartArguments(uid: 501, killRunning: false), ["kickstart", "gui/501/net.oxog.phonebox.agent"])
    }

    func testLaunchdLifecycleArgumentsUseArrayArguments() {
        XCTAssertEqual(AgentControl.bootoutArguments(uid: 501), ["bootout", "gui/501/net.oxog.phonebox.agent"])
        let spacedPlist = "/Users/my user/Library/LaunchAgents/net.oxog.phonebox.agent.plist"
        XCTAssertEqual(AgentControl.bootstrapArguments(uid: 501, plistPath: spacedPlist), ["bootstrap", "gui/501", spacedPlist])
        XCTAssertEqual(AgentControl.printArguments(uid: 501), ["print", "gui/501/net.oxog.phonebox.agent"])
    }

    func testIsNotLoadedStatus() {
        XCTAssertTrue(AgentControl.isNotLoadedStatus(3))
        XCTAssertTrue(AgentControl.isNotLoadedStatus(113))
        XCTAssertFalse(AgentControl.isNotLoadedStatus(0))
        XCTAssertFalse(AgentControl.isNotLoadedStatus(1))
        XCTAssertFalse(AgentControl.isNotLoadedStatus(5))
    }
}
