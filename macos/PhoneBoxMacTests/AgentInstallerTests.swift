import XCTest
@testable import PhoneBox

final class AgentInstallerTests: XCTestCase {
    func testCommandIsBashWithArrayArgumentsAndNoSudo() {
        let script = URL(fileURLWithPath: "/Applications/PhoneBox.app/Contents/Resources/setup.sh")
        let command = AgentInstaller.command(script: script, baseEnvironment: ["HOME": "/Users/x", "PATH": "/usr/bin"])
        XCTAssertEqual(command.executable.path, "/bin/bash")
        XCTAssertEqual(command.arguments, [script.path, "--yes", "--no-phone"])
        XCTAssertFalse(command.arguments.contains("sudo"))
        XCTAssertEqual(command.environment["HOME"], "/Users/x")
        XCTAssertTrue(command.environment["PATH"]?.contains("/opt/homebrew/bin") == true)
    }

    func testScriptPathWithSpacesStaysOneArgument() {
        let script = URL(fileURLWithPath: "/Volumes/My Disk/PhoneBox.app/Contents/Resources/setup.sh")
        XCTAssertEqual(AgentInstaller.command(script: script).arguments.first, script.path)
    }

    func testBundledScriptMissingThrows() {
        XCTAssertThrowsError(try AgentInstaller.bundledScript(in: Bundle(for: AgentInstallerTests.self)))
    }

    func testAnsiColoursAreStripped() {
        XCTAssertEqual(AgentInstaller.stripANSI("\u{1B}[1;32mOK\u{1B}[0m done"), "OK done")
    }

    func testRunStreamsOutputAndExitStatus() async throws {
        let command = AgentInstaller.Command(executable: URL(fileURLWithPath: "/bin/sh"),
                                             arguments: ["-c", "echo one; echo two >&2; exit 3"], environment: [:])
        var events: [AgentInstaller.Event] = []
        for try await event in AgentInstaller.run(command) { events.append(event) }
        XCTAssertTrue(events.contains(.line("one")))
        XCTAssertTrue(events.contains(.line("two")))
        XCTAssertEqual(events.last, .finished(status: 3))
    }

    func testRunFailsWhenExecutableMissing() async {
        let command = AgentInstaller.Command(executable: URL(fileURLWithPath: "/nonexistent/bash"), arguments: [], environment: [:])
        do {
            for try await _ in AgentInstaller.run(command) {}
            XCTFail("expected an error")
        } catch {}
    }
}
