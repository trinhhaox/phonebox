import Foundation

/// Semantic version (`major.minor.patch`) parsed strictly for app versions and `apps-v*` release tags.
struct AppVersion: Comparable, Equatable, Hashable, CustomStringConvertible, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    var description: String { "\(major).\(minor).\(patch)" }

    init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    init?(string: String) {
        let trimmed = string.hasPrefix("v") ? string.dropFirst() : string[...]
        self.init(exact: trimmed)
    }

    private init?(exact: Substring) {
        let parts = exact.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var nums: [Int] = []
        nums.reserveCapacity(3)
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0 >= "0" && $0 <= "9" }), let value = Int(part) else {
                return nil
            }
            nums.append(value)
        }
        self.major = nums[0]
        self.minor = nums[1]
        self.patch = nums[2]
    }

    static func fromReleaseTag(_ tag: String) -> AppVersion? {
        let prefix = "apps-v"
        guard tag.hasPrefix(prefix) else { return nil }
        return AppVersion(exact: tag.dropFirst(prefix.count))
    }

    static func current(bundle: Bundle = .main) -> AppVersion {
        guard let raw = bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
              let parsed = AppVersion(string: raw) else {
            return AppVersion(major: 0, minor: 0, patch: 0)
        }
        return parsed
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
