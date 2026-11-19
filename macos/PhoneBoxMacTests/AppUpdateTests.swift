import XCTest
@testable import PhoneBox

final class AppUpdateTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("pbmac-upd-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: tempDir)
    }

    func testAppVersionParsingAndComparison() {
        XCTAssertEqual(AppVersion(string: "1.0.1"), AppVersion(major: 1, minor: 0, patch: 1))
        XCTAssertEqual(AppVersion(string: "v1.2.3"), AppVersion(major: 1, minor: 2, patch: 3))
        XCTAssertNil(AppVersion(string: "1.0"))
        XCTAssertNil(AppVersion(string: "1.0.1.2"))
        XCTAssertNil(AppVersion(string: "abc"))
        XCTAssertNil(AppVersion(string: "-1.0.0"))
        XCTAssertNil(AppVersion(string: " 1.0.1"))

        XCTAssertEqual(AppVersion.fromReleaseTag("apps-v1.0.1"), AppVersion(major: 1, minor: 0, patch: 1))
        XCTAssertNil(AppVersion.fromReleaseTag("v0.9.21"))
        XCTAssertNil(AppVersion.fromReleaseTag("apps-vv1.0.1"))

        XCTAssertTrue(AppVersion(major: 1, minor: 0, patch: 10) > AppVersion(major: 1, minor: 0, patch: 2))
        XCTAssertTrue(AppVersion(major: 1, minor: 1, patch: 0) > AppVersion(major: 1, minor: 0, patch: 9))
        XCTAssertFalse(AppVersion(major: 1, minor: 0, patch: 1) > AppVersion(major: 1, minor: 0, patch: 1))
    }

    func testAllowedDownloadURLs() {
        XCTAssertTrue(AppUpdatePolicy.isAllowedDownloadURL(URL(string: "https://github.com/trinhhaox/phonebox/releases/download/apps-v1.0.1/PhoneBox-1.0.1-mac.zip")))
        XCTAssertTrue(AppUpdatePolicy.isAllowedDownloadURL(URL(string: "https://objects.githubusercontent.com/some/path")))
        XCTAssertTrue(AppUpdatePolicy.isAllowedDownloadURL(URL(string: "https://release-assets.githubusercontent.com/some/path")))
        XCTAssertTrue(AppUpdatePolicy.isAllowedDownloadURL(URL(string: "https://api.github.com/repos/trinhhaox/phonebox/releases")))

        XCTAssertFalse(AppUpdatePolicy.isAllowedDownloadURL(URL(string: "http://github.com/trinhhaox/phonebox")))
        XCTAssertFalse(AppUpdatePolicy.isAllowedDownloadURL(URL(string: "https://github.com.evil.com/file.zip")))
        XCTAssertFalse(AppUpdatePolicy.isAllowedDownloadURL(URL(string: "https://user:pass@github.com/file.zip")))
        XCTAssertFalse(AppUpdatePolicy.isAllowedDownloadURL(URL(string: "file:///tmp/PhoneBox.zip")))
        XCTAssertFalse(AppUpdatePolicy.isAllowedDownloadURL(nil))
    }

    func testSelectLatestReleaseFiltersAndPicksHighest() throws {
        let json = """
        [
          {
            "tag_name": "v0.9.21",
            "draft": false,
            "prerelease": false,
            "html_url": "https://github.com/trinhhaox/phonebox/releases/tag/v0.9.21",
            "assets": [
              {"name": "PhoneBox-0.9.21-mac.zip", "browser_download_url": "https://github.com/a/PhoneBox-0.9.21-mac.zip"},
              {"name": "SHA256SUMS.txt", "browser_download_url": "https://github.com/a/SHA256SUMS.txt"}
            ]
          },
          {
            "tag_name": "apps-v1.3.0",
            "draft": true,
            "prerelease": false,
            "html_url": "https://github.com/trinhhaox/phonebox/releases/tag/apps-v1.3.0",
            "assets": [
              {"name": "PhoneBox-1.3.0-mac.zip", "browser_download_url": "https://github.com/a/PhoneBox-1.3.0-mac.zip"},
              {"name": "SHA256SUMS.txt", "browser_download_url": "https://github.com/a/SHA256SUMS.txt"}
            ]
          },
          {
            "tag_name": "apps-v1.2.0",
            "draft": false,
            "prerelease": true,
            "html_url": "https://github.com/trinhhaox/phonebox/releases/tag/apps-v1.2.0",
            "assets": [
              {"name": "PhoneBox-1.2.0-mac.zip", "browser_download_url": "https://github.com/a/PhoneBox-1.2.0-mac.zip"},
              {"name": "SHA256SUMS.txt", "browser_download_url": "https://github.com/a/SHA256SUMS.txt"}
            ]
          },
          {
            "tag_name": "apps-v1.1.0",
            "draft": false,
            "prerelease": false,
            "html_url": "https://github.com/trinhhaox/phonebox/releases/tag/apps-v1.1.0",
            "assets": [
              {"name": "PhoneBox-1.1.0-mac.zip", "browser_download_url": "https://evil.example/PhoneBox-1.1.0-mac.zip"},
              {"name": "SHA256SUMS.txt", "browser_download_url": "https://github.com/a/SHA256SUMS.txt"}
            ]
          },
          {
            "tag_name": "apps-v1.0.2",
            "draft": false,
            "prerelease": false,
            "html_url": "https://github.com/trinhhaox/phonebox/releases/tag/apps-v1.0.2",
            "body": "Notes",
            "assets": [
              {"name": "PhoneBox-1.0.2-mac.zip", "browser_download_url": "https://github.com/trinhhaox/phonebox/releases/download/apps-v1.0.2/PhoneBox-1.0.2-mac.zip"},
              {"name": "SHA256SUMS.txt", "browser_download_url": "https://github.com/trinhhaox/phonebox/releases/download/apps-v1.0.2/SHA256SUMS.txt"}
            ]
          },
          {
            "tag_name": "apps-v1.0.1",
            "draft": false,
            "prerelease": false,
            "html_url": "https://github.com/trinhhaox/phonebox/releases/tag/apps-v1.0.1",
            "assets": [
              {"name": "PhoneBox-1.0.1-mac.zip", "browser_download_url": "https://github.com/trinhhaox/phonebox/releases/download/apps-v1.0.1/PhoneBox-1.0.1-mac.zip"},
              {"name": "SHA256SUMS.txt", "browser_download_url": "https://github.com/trinhhaox/phonebox/releases/download/apps-v1.0.1/SHA256SUMS.txt"}
            ]
          }
        ]
        """
        let releases = try JSONDecoder().decode([GitHubRelease].self, from: Data(json.utf8))
        let picked = AppUpdatePolicy.selectLatestRelease(from: releases)
        XCTAssertEqual(picked?.version, AppVersion(major: 1, minor: 0, patch: 2))
        XCTAssertEqual(picked?.tagName, "apps-v1.0.2")
        XCTAssertEqual(picked?.zipAssetName, "PhoneBox-1.0.2-mac.zip")
        XCTAssertEqual(picked?.notes, "Notes")

        let missingChecksums = GitHubRelease(
            tagName: "apps-v2.0.0",
            htmlURL: "https://github.com/trinhhaox/phonebox/releases/tag/apps-v2.0.0",
            assets: [
                .init(name: "PhoneBox-2.0.0-mac.zip", browserDownloadURL: "https://github.com/x/PhoneBox-2.0.0-mac.zip")
            ]
        )
        XCTAssertNil(AppUpdatePolicy.selectLatestRelease(from: [missingChecksums]))
    }

    func testParseSHA256HandlesStandardBinaryAndInvalidLines() {
        let hex = "A15ECEA5B60637633772044D57004D8CDF9232CB7CB473DD987A17346EE7D0DD"
        let lower = hex.lowercased()

        XCTAssertEqual(AppUpdatePolicy.parseSHA256(from: "\(hex)  PhoneBox-1.0.1-mac.zip\n", forAsset: "PhoneBox-1.0.1-mac.zip"), lower)
        XCTAssertEqual(AppUpdatePolicy.parseSHA256(from: "\(lower) *./PhoneBox-1.0.1-mac.zip\r\n", forAsset: "PhoneBox-1.0.1-mac.zip"), lower)
        XCTAssertNil(AppUpdatePolicy.parseSHA256(from: "deadbeef  PhoneBox-1.0.1-mac.zip", forAsset: "PhoneBox-1.0.1-mac.zip"))
        XCTAssertNil(AppUpdatePolicy.parseSHA256(from: "\(lower)  PhoneBox-1.0.0-mac.zip", forAsset: "PhoneBox-1.0.1-mac.zip"))
    }

    func testCanReplaceInPlaceChecksLocationAndWritability() throws {
        let writableApp = tempDir.appendingPathComponent("PhoneBox.app", isDirectory: true)
        try FileManager.default.createDirectory(at: writableApp, withIntermediateDirectories: true)
        XCTAssertTrue(AppUpdatePolicy.canReplaceInPlace(bundleURL: writableApp))

        let notApp = tempDir.appendingPathComponent("PhoneBox", isDirectory: true)
        try FileManager.default.createDirectory(at: notApp, withIntermediateDirectories: true)
        XCTAssertFalse(AppUpdatePolicy.canReplaceInPlace(bundleURL: notApp))

        let derived = tempDir.appendingPathComponent("DerivedData/PhoneBox.app", isDirectory: true)
        try FileManager.default.createDirectory(at: derived, withIntermediateDirectories: true)
        XCTAssertFalse(AppUpdatePolicy.canReplaceInPlace(bundleURL: derived))

        let translocated = URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/PhoneBox.app")
        XCTAssertFalse(AppUpdatePolicy.canReplaceInPlace(bundleURL: translocated))
    }

    func testSHA256HexOfKnownBytes() throws {
        let file = tempDir.appendingPathComponent("hello.txt")
        try Data("hello\n".utf8).write(to: file)
        XCTAssertEqual(
            try AppUpdateInstaller.sha256Hex(ofFile: file),
            "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03"
        )
    }

    func testSwapScriptArgumentsKeepSpacedPathsIntact() {
        let target = URL(fileURLWithPath: "/Applications/My Apps/PhoneBox.app")
        let staged = URL(fileURLWithPath: "/tmp/stage dir/PhoneBox.app")
        let root = URL(fileURLWithPath: "/tmp/stage dir")
        let args = AppUpdateInstaller.swapScriptArguments(pid: 4242, targetApp: target, stagedApp: staged, stagingRoot: root)
        XCTAssertEqual(args.count, 7)
        XCTAssertEqual(args[0], "-c")
        XCTAssertEqual(args[2], "phonebox-updater")
        XCTAssertEqual(args[3], "4242")
        XCTAssertEqual(args[4], target.path)
        XCTAssertEqual(args[5], staged.path)
        XCTAssertEqual(args[6], root.path)
    }

    @MainActor
    func testAutoUpdatePreferenceDefaultsTrueAndPersists() {
        let suiteName = "pbmac-upd-prefs-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }

        let updater = AppUpdater(currentVersion: AppVersion(major: 1, minor: 0, patch: 1), defaults: defaults)
        XCTAssertTrue(updater.autoUpdateEnabled)

        updater.autoUpdateEnabled = false
        let reloaded = AppUpdater(currentVersion: AppVersion(major: 1, minor: 0, patch: 1), defaults: defaults)
        XCTAssertFalse(reloaded.autoUpdateEnabled)
    }
}
