import Foundation

/// Mobile-dev items that need tool knowledge: AVDs, Android system images / NDKs, simulator runtimes,
/// unavailable simulators. Listing is read-only; cleaning goes through `CommandRunner` (dry-run aware).
public struct MobileItem: Sendable, Identifiable, Hashable {
    public enum Kind: String, Sendable { case avd, systemImage, ndk, simRuntime, unavailableSimulators }
    public var id: String { kind.rawValue + ":" + name }
    public var kind: Kind
    public var name: String
    public var path: String?
    public var bytes: UInt64
    /// Used by an AVD, a project, or a simulator device; never offered for cleaning by default.
    public var inUse: Bool
    public var usedBy: [String] = []
    public var command: [String]
    public var safety: Safety
}

public struct MobilePack: Sendable {
    public var home: String
    public var androidHome: String
    /// Projects to check for `ndkVersion` usage.
    public var projectPaths: [String]
    /// Injectable for tests; defaults to running `xcrun simctl ... -j` (read-only).
    public var simctl: @Sendable ([String]) -> String?

    public init(home: String = NSHomeDirectory(), androidHome: String? = nil, projectPaths: [String] = [],
                simctl: @escaping @Sendable ([String]) -> String? = { CommandRunner.query(["xcrun", "simctl"] + $0) }) {
        self.home = home
        self.androidHome = androidHome ?? ProcessInfo.processInfo.environment["ANDROID_HOME"] ?? home + "/Library/Android/sdk"
        self.projectPaths = projectPaths
        self.simctl = simctl
    }

    public func items() -> [MobileItem] { avds() + systemImages() + ndks() + simRuntimes() + unavailableSimulators() }

    func ls(_ dir: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
    }

    func avdConfigs() -> [(name: String, config: String)] {
        let dir = home + "/.android/avd"
        return ls(dir).filter { $0.hasSuffix(".avd") }.map {
            (($0 as NSString).deletingPathExtension, (try? String(contentsOfFile: dir + "/" + $0 + "/config.ini", encoding: .utf8)) ?? "")
        }
    }

    public func avds() -> [MobileItem] {
        avdConfigs().map { avd in
            let path = home + "/.android/avd/\(avd.name).avd"
            return MobileItem(kind: .avd, name: avd.name, path: path, bytes: Fixtures.duBytes(path), inUse: false,
                              command: ["avdmanager", "delete", "avd", "-n", avd.name], safety: .caution)
        }
    }

    /// `system-images;android-34;google_apis;arm64-v8a`, in use when an AVD's config points at it.
    public func systemImages() -> [MobileItem] {
        let base = androidHome + "/system-images"
        let configs = avdConfigs()
        var out: [MobileItem] = []
        for api in ls(base) { for tag in ls(base + "/" + api) { for abi in ls(base + "/\(api)/\(tag)") {
            let rel = "system-images/\(api)/\(tag)/\(abi)"
            let users = configs.filter { $0.config.contains(rel) }.map(\.name)
            let path = androidHome + "/" + rel
            out.append(MobileItem(kind: .systemImage, name: "\(api) · \(tag) · \(abi)", path: path, bytes: Fixtures.duBytes(path),
                                  inUse: !users.isEmpty, usedBy: users,
                                  command: ["sdkmanager", "--uninstall", "system-images;\(api);\(tag);\(abi)"], safety: .caution))
        } } }
        return out
    }

    /// NDK versions, in use when a project's Gradle files mention `ndkVersion` with that version.
    public func ndks() -> [MobileItem] {
        let gradleTexts = projectPaths.flatMap { p in
            ["build.gradle", "build.gradle.kts", "app/build.gradle", "app/build.gradle.kts", "android/app/build.gradle",
             "android/build.gradle", "android/app/build.gradle.kts"].compactMap { f in
                (try? String(contentsOfFile: p + "/" + f, encoding: .utf8)).map { (p, $0) }
            }
        }
        return ls(androidHome + "/ndk").map { v in
            let users = gradleTexts.filter { $0.1.contains("ndkVersion") && $0.1.contains(v) }.map { ($0.0 as NSString).lastPathComponent }
            let path = androidHome + "/ndk/" + v
            return MobileItem(kind: .ndk, name: v, path: path, bytes: Fixtures.duBytes(path), inUse: !users.isEmpty, usedBy: users,
                              command: ["sdkmanager", "--uninstall", "ndk;\(v)"], safety: .caution)
        }
    }

    /// Runtimes from `simctl runtime list -j`; in use when any simulator device uses that runtime.
    public func simRuntimes() -> [MobileItem] {
        guard let json = simctl(["runtime", "list", "-j"]), let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return [] }
        let usedRuntimes = Set(deviceRuntimes().filter { !$0.value.isEmpty }.keys)
        return dict.values.compactMap { r -> MobileItem? in
            guard let id = r["identifier"] as? String else { return nil }
            let runtimeID = r["runtimeIdentifier"] as? String ?? ""
            let version = r["version"] as? String ?? "?"
            let platform = (r["platformIdentifier"] as? String ?? "").replacingOccurrences(of: "com.apple.platform.", with: "")
            let bytes = (r["sizeBytes"] as? NSNumber)?.uint64Value ?? 0
            return MobileItem(kind: .simRuntime, name: "\(platform) \(version)", path: r["path"] as? String, bytes: bytes,
                              inUse: usedRuntimes.contains(runtimeID), usedBy: usedRuntimes.contains(runtimeID) ? ["simulators"] : [],
                              command: ["xcrun", "simctl", "runtime", "delete", id], safety: .caution)
        }.sorted { $0.name < $1.name }
    }

    /// runtime identifier → device names (available devices only).
    func deviceRuntimes() -> [String: [String]] {
        guard let json = simctl(["list", "devices", "-j"]), let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = dict["devices"] as? [String: [[String: Any]]] else { return [:] }
        return devices.mapValues { $0.filter { ($0["isAvailable"] as? Bool) ?? true }.compactMap { $0["name"] as? String } }
    }

    public func unavailableSimulators() -> [MobileItem] {
        guard let json = simctl(["list", "devices", "unavailable", "-j"]), let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = dict["devices"] as? [String: [[String: Any]]] else { return [] }
        let all = devices.values.flatMap { $0 }
        guard !all.isEmpty else { return [] }
        let bytes = all.compactMap { $0["dataPath"] as? String }.reduce(UInt64(0)) { $0 + Fixtures.duBytes(($1 as NSString).deletingLastPathComponent) }
        return [MobileItem(kind: .unavailableSimulators, name: "\(all.count) unavailable simulators", path: nil, bytes: bytes,
                           inUse: false, command: ["xcrun", "simctl", "delete", "unavailable"], safety: .safe)]
    }
}
