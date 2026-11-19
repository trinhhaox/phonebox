import CryptoKit
import Foundation

enum AppUpdateError: LocalizedError, Equatable {
    case invalidResponse
    case untrustedRedirect
    case fileTooLarge
    case missingChecksum(String)
    case checksumMismatch
    case extractionFailed(String)
    case invalidBundle(String)
    case signatureFailed(String)
    case cannotLaunchHelper(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Phản hồi từ máy chủ cập nhật không hợp lệ."
        case .untrustedRedirect:
            return "Chuyển hướng tải về trỏ tới địa chỉ không đáng tin cậy."
        case .fileTooLarge:
            return "Tệp cập nhật vượt quá dung lượng cho phép."
        case let .missingChecksum(name):
            return "Không tìm thấy mã SHA-256 cho \(name) trong SHA256SUMS.txt."
        case .checksumMismatch:
            return "Mã kiểm tra SHA-256 không khớp."
        case let .extractionFailed(detail):
            return "Không giải nén được bản cập nhật: \(detail)"
        case let .invalidBundle(detail):
            return "Gói ứng dụng tải về không hợp lệ: \(detail)"
        case let .signatureFailed(detail):
            return "Chữ ký ứng dụng không hợp lệ: \(detail)"
        case let .cannotLaunchHelper(detail):
            return "Không khởi chạy được trình thay thế ứng dụng: \(detail)"
        }
    }
}

final class PinnedRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(AppUpdatePolicy.isAllowedDownloadURL(request.url) ? request : nil)
    }
}

enum AppUpdateInstaller {
    static let stagingPrefix = "phonebox-update-"

    static func sha256Hex(ofFile url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 65_536)
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func downloadAndVerify(
        release: AppRelease,
        currentVersion: AppVersion,
        session: URLSession,
        onVerifying: (@Sendable () -> Void)? = nil
    ) async throws -> (stagingRoot: URL, stagedApp: URL) {
        guard AppUpdatePolicy.isAllowedDownloadURL(release.checksumsURL),
              AppUpdatePolicy.isAllowedDownloadURL(release.zipURL) else {
            throw AppUpdateError.untrustedRedirect
        }

        let fm = FileManager.default
        let stagingRoot = fm.temporaryDirectory.appendingPathComponent("\(stagingPrefix)\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stagingRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        do {
            let expectedHash = try await fetchExpectedSHA256(for: release, session: session)
            let zipFile = try await downloadZip(from: release.zipURL, into: stagingRoot, name: release.zipAssetName, session: session)

            onVerifying?()

            let actualHash = try sha256Hex(ofFile: zipFile)
            guard actualHash == expectedHash else {
                throw AppUpdateError.checksumMismatch
            }

            let extractDir = stagingRoot.appendingPathComponent("extracted", isDirectory: true)
            try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
            try await runTool(
                "/usr/bin/ditto",
                arguments: ["-x", "-k", zipFile.path, extractDir.path],
                onFailure: { AppUpdateError.extractionFailed($0) }
            )

            let stagedApp = extractDir.appendingPathComponent("PhoneBox.app", isDirectory: true)
            try validateStagedBundle(at: stagedApp, expectedVersion: release.version, currentVersion: currentVersion)

            try await runTool(
                "/usr/bin/codesign",
                arguments: ["--verify", "--deep", "--strict", "-R", AppUpdatePolicy.codesignRequirement, stagedApp.path],
                onFailure: { AppUpdateError.signatureFailed($0) }
            )

            return (stagingRoot, stagedApp)
        } catch {
            try? fm.removeItem(at: stagingRoot)
            throw error
        }
    }

    static let swapShellScript = """
    pid="$1"
    target="$2"
    staged="$3"
    root="$4"
    backup="${target}.updating-backup-$$"
    i=0
    while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 150 ]; do
      sleep 0.1
      i=$((i + 1))
    done
    if [ -e "$target" ]; then
      mv "$target" "$backup" || exit 1
    fi
    if /usr/bin/ditto "$staged" "$target"; then
      rm -rf "$backup" "$root"
      /usr/bin/open "$target" >/dev/null 2>&1
      exit 0
    else
      rm -rf "$target"
      if [ -e "$backup" ]; then mv "$backup" "$target"; fi
      rm -rf "$root"
      exit 1
    fi
    """

    static func swapScriptArguments(pid: Int32, targetApp: URL, stagedApp: URL, stagingRoot: URL) -> [String] {
        ["-c", swapShellScript, "phonebox-updater", String(pid), targetApp.path, stagedApp.path, stagingRoot.path]
    }

    static func launchSwapHelper(
        pid: Int32 = getpid(),
        targetApp: URL = Bundle.main.bundleURL,
        stagedApp: URL,
        stagingRoot: URL
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = swapScriptArguments(pid: pid, targetApp: targetApp, stagedApp: stagedApp, stagingRoot: stagingRoot)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.qualityOfService = .userInitiated
        do {
            try process.run()
        } catch {
            throw AppUpdateError.cannotLaunchHelper(error.localizedDescription)
        }
    }

    static func cleanupOldStaging(in tempDir: URL = FileManager.default.temporaryDirectory, fileManager: FileManager = .default) {
        guard let entries = try? fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) else { return }
        for entry in entries where entry.lastPathComponent.hasPrefix(stagingPrefix) {
            try? fileManager.removeItem(at: entry)
        }
    }

    private static func fetchExpectedSHA256(for release: AppRelease, session: URLSession) async throws -> String {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(from: release.checksumsURL)
        } catch let error as URLError where error.code == .cancelled {
            throw AppUpdateError.untrustedRedirect
        }
        guard let http = response as? HTTPURLResponse else { throw AppUpdateError.invalidResponse }
        guard AppUpdatePolicy.isAllowedDownloadURL(http.url) else { throw AppUpdateError.untrustedRedirect }
        guard http.statusCode == 200 else { throw AppUpdateError.invalidResponse }
        guard Int64(data.count) <= AppUpdatePolicy.maxChecksumsBytes else { throw AppUpdateError.fileTooLarge }
        guard let text = String(data: data, encoding: .utf8),
              let expected = AppUpdatePolicy.parseSHA256(from: text, forAsset: release.zipAssetName) else {
            throw AppUpdateError.missingChecksum(release.zipAssetName)
        }
        return expected
    }

    private static func downloadZip(from url: URL, into stagingRoot: URL, name: String, session: URLSession) async throws -> URL {
        let (tempFile, response): (URL, URLResponse)
        do {
            (tempFile, response) = try await session.download(from: url)
        } catch let error as URLError where error.code == .cancelled {
            throw AppUpdateError.untrustedRedirect
        }
        let fm = FileManager.default
        guard let http = response as? HTTPURLResponse else {
            try? fm.removeItem(at: tempFile)
            throw AppUpdateError.invalidResponse
        }
        guard AppUpdatePolicy.isAllowedDownloadURL(http.url) else {
            try? fm.removeItem(at: tempFile)
            throw AppUpdateError.untrustedRedirect
        }
        guard http.statusCode == 200 else {
            try? fm.removeItem(at: tempFile)
            throw AppUpdateError.invalidResponse
        }
        let attrs = try fm.attributesOfItem(atPath: tempFile.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 && size <= AppUpdatePolicy.maxZipBytes else {
            try? fm.removeItem(at: tempFile)
            throw AppUpdateError.fileTooLarge
        }
        let destination = stagingRoot.appendingPathComponent(name)
        if fm.fileExists(atPath: destination.path) {
            try? fm.removeItem(at: destination)
        }
        try fm.moveItem(at: tempFile, to: destination)
        return destination
    }

    private static func validateStagedBundle(at stagedApp: URL, expectedVersion: AppVersion, currentVersion: AppVersion) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: stagedApp.path, isDirectory: &isDir), isDir.boolValue else {
            throw AppUpdateError.invalidBundle("Không tìm thấy PhoneBox.app")
        }
        let values = try stagedApp.resourceValues(forKeys: [.isSymbolicLinkKey])
        if values.isSymbolicLink == true {
            throw AppUpdateError.invalidBundle("Bundle không được là liên kết tượng trưng")
        }
        let plistURL = stagedApp.appendingPathComponent("Contents/Info.plist")
        let plistData = try Data(contentsOf: plistURL)
        guard let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            throw AppUpdateError.invalidBundle("Không đọc được Info.plist")
        }
        guard (plist["CFBundleIdentifier"] as? String) == AppUpdatePolicy.expectedBundleIdentifier else {
            throw AppUpdateError.invalidBundle("Bundle identifier không khớp")
        }
        guard let rawVersion = plist["CFBundleShortVersionString"] as? String,
              let bundleVersion = AppVersion(string: rawVersion),
              bundleVersion == expectedVersion,
              bundleVersion > currentVersion else {
            throw AppUpdateError.invalidBundle("Phiên bản trong gói tải về không hợp lệ")
        }
    }

    private static func runTool(
        _ path: String,
        arguments: [String],
        onFailure: (String) -> AppUpdateError
    ) async throws {
        let result = try await Task.detached(priority: .userInitiated) { () throws -> (status: Int32, output: String) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (process.terminationStatus, text)
        }.value

        guard result.status == 0 else {
            let message = result.output.isEmpty ? "mã lỗi \(result.status)" : result.output
            throw onFailure(message)
        }
    }
}
