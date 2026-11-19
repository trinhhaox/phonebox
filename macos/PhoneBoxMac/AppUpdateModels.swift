import Foundation

struct GitHubRelease: Decodable, Equatable {
    struct Asset: Decodable, Equatable {
        let name: String
        let browserDownloadURL: String
        let size: Int?

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case size
        }

        init(name: String, browserDownloadURL: String, size: Int? = nil) {
            self.name = name
            self.browserDownloadURL = browserDownloadURL
            self.size = size
        }
    }

    let tagName: String
    let draft: Bool
    let prerelease: Bool
    let htmlURL: String
    let body: String?
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case draft
        case prerelease
        case htmlURL = "html_url"
        case body
        case assets
    }

    init(
        tagName: String,
        draft: Bool = false,
        prerelease: Bool = false,
        htmlURL: String,
        body: String? = nil,
        assets: [Asset]
    ) {
        self.tagName = tagName
        self.draft = draft
        self.prerelease = prerelease
        self.htmlURL = htmlURL
        self.body = body
        self.assets = assets
    }
}

struct AppRelease: Equatable, Sendable {
    let version: AppVersion
    let tagName: String
    let htmlURL: URL
    let zipAssetName: String
    let zipURL: URL
    let checksumsURL: URL
    let notes: String
}

enum AppUpdatePolicy {
    static let repo = "trinhhaox/phonebox"
    static let releasesAPIURL = URL(string: "https://api.github.com/repos/trinhhaox/phonebox/releases?per_page=15")!
    static let allowedDownloadHosts: Set<String> = [
        "github.com",
        "api.github.com",
        "objects.githubusercontent.com",
        "release-assets.githubusercontent.com",
    ]
    static let expectedBundleIdentifier = "vn.xox.phonebox.mac"
    static let expectedTeamIdentifier = "4DU4BTV46U"
    static let codesignRequirement =
        "=anchor apple generic and identifier \"\(expectedBundleIdentifier)\" and certificate leaf[subject.OU] = \"\(expectedTeamIdentifier)\""
    static let maxChecksumsBytes: Int64 = 1_048_576
    static let maxZipBytes: Int64 = 104_857_600

    static func isAllowedDownloadURL(_ url: URL?) -> Bool {
        guard let url, let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        guard comps.scheme?.lowercased() == "https",
              comps.user == nil,
              comps.password == nil,
              let host = comps.host?.lowercased() else {
            return false
        }
        return allowedDownloadHosts.contains(host)
    }

    static func selectLatestRelease(from releases: [GitHubRelease]) -> AppRelease? {
        var best: AppRelease?
        for release in releases {
            guard !release.draft, !release.prerelease else { continue }
            guard let version = AppVersion.fromReleaseTag(release.tagName) else { continue }
            guard let htmlURL = URL(string: release.htmlURL),
                  let htmlComps = URLComponents(url: htmlURL, resolvingAgainstBaseURL: false),
                  htmlComps.scheme?.lowercased() == "https",
                  htmlComps.host?.lowercased() == "github.com",
                  htmlComps.user == nil,
                  htmlComps.password == nil else {
                continue
            }

            let zipAssetName = "PhoneBox-\(version)-mac.zip"
            guard let zipAsset = release.assets.first(where: { $0.name == zipAssetName }),
                  let zipURL = URL(string: zipAsset.browserDownloadURL),
                  isAllowedDownloadURL(zipURL),
                  let checksumsAsset = release.assets.first(where: { $0.name == "SHA256SUMS.txt" }),
                  let checksumsURL = URL(string: checksumsAsset.browserDownloadURL),
                  isAllowedDownloadURL(checksumsURL) else {
                continue
            }

            let candidate = AppRelease(
                version: version,
                tagName: release.tagName,
                htmlURL: htmlURL,
                zipAssetName: zipAssetName,
                zipURL: zipURL,
                checksumsURL: checksumsURL,
                notes: release.body ?? ""
            )
            if let existing = best {
                if candidate.version > existing.version { best = candidate }
            } else {
                best = candidate
            }
        }
        return best
    }

    static func parseSHA256(from text: String, forAsset assetName: String) -> String? {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            guard let splitIdx = line.firstIndex(where: { $0 == " " || $0 == "\t" }) else { continue }
            let hashPart = line[..<splitIdx]
            guard hashPart.count == 64, hashPart.allSatisfy(isHexChar) else { continue }

            var namePart = line[splitIdx...].drop(while: { $0 == " " || $0 == "\t" })
            if namePart.hasPrefix("*") {
                namePart = namePart.dropFirst()
            }
            let fileName = String(namePart)
            if fileName == assetName || fileName == "./\(assetName)" {
                return String(hashPart).lowercased()
            }
        }
        return nil
    }

    static func canReplaceInPlace(bundleURL: URL, fileManager: FileManager = .default) -> Bool {
        let resolved = bundleURL.resolvingSymlinksInPath()
        guard resolved.pathExtension == "app" else { return false }
        let path = resolved.path
        if path.contains("/AppTranslocation/") || path.contains("/DerivedData/") || path.contains("/Build/Products/") {
            return false
        }
        let parent = resolved.deletingLastPathComponent()
        return fileManager.isWritableFile(atPath: parent.path) && fileManager.isWritableFile(atPath: resolved.path)
    }

    private static func isHexChar(_ c: Character) -> Bool {
        (c >= "0" && c <= "9") || (c >= "a" && c <= "f") || (c >= "A" && c <= "F")
    }
}
