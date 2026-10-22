import Darwin
import Foundation

/// Runs tool commands (`xcrun`, `npm`, `docker`, ...). In dry-run mode it only logs them.
public final class CommandRunner: @unchecked Sendable {
    public let dryRun: Bool
    private let lock = NSLock()
    private var _log: [String] = []
    public var log: [String] { lock.withLock { _log } }

    /// Dry run is forced when `DISKLENS_DRY_RUN=1` is set (tests, UI tests, screenshots).
    public init(dryRun: Bool = ProcessInfo.processInfo.environment["DISKLENS_DRY_RUN"] == "1") {
        self.dryRun = dryRun
    }

    @discardableResult
    public func run(_ args: [String], in dir: String? = nil) -> (ok: Bool, output: String) {
        let line = (dir.map { "cd \($0) && " } ?? "") + args.joined(separator: " ")
        lock.withLock { _log.append((dryRun ? "[dry-run] " : "") + line) }
        guard !dryRun else { return (true, "") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        if let dir { p.currentDirectoryURL = URL(fileURLWithPath: dir) }
        // GUI apps get a minimal PATH; add the usual tool locations.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (env["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin:" + NSHomeDirectory() + "/Library/Android/sdk/cmdline-tools/latest/bin"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (false, error.localizedDescription) }
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        p.waitUntilExit()
        return (p.terminationStatus == 0, out)
    }

    /// Read-only output of a command (never dry-run; only for queries like `pgrep`, `simctl list`).
    public static func query(_ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}

/// Detects tools that own cleanable data, so we can warn before cleaning.
public enum RunningTools {
    static let probes: [String: [String]] = [
        "Xcode": ["pgrep", "-x", "Xcode"],
        "Simulator": ["pgrep", "-x", "Simulator"],
        "Metro": ["pgrep", "-f", "metro|react-native start"],
        "Gradle daemon": ["pgrep", "-f", "GradleDaemon"],
        "Android Emulator": ["pgrep", "-f", "qemu-system"],
        "Docker": ["pgrep", "-f", "com.docker.backend"],
    ]
    /// How to stop a running tool (GUI apps are asked to quit by the app instead).
    public static let stopCommands: [String: [String]] = [
        "Gradle daemon": ["gradle", "--stop"],
        "Metro": ["pkill", "-f", "metro"],
    ]

    public static func running(_ names: [String]) -> [String] {
        names.filter { name in probes[name].flatMap { CommandRunner.query($0) }.map { !$0.isEmpty } ?? false }
    }
}

public struct CleanItem: Sendable, Identifiable, Hashable {
    public var id: String { match.path }
    public var match: RuleMatch
    public var bytes: UInt64
    public var path: String { match.path }
    public var rule: Rule { match.rule }
    /// The resolved tool command for command-based rules.
    public var command: [String]? {
        guard let c = rule.command else { return nil }
        let name = (path as NSString).lastPathComponent
        let stem = (name as NSString).deletingPathExtension
        // $ANDROID_HOME/system-images/android-34/google_apis/arm64-v8a -> system-images;android-34;google_apis;arm64-v8a
        let parts = path.split(separator: "/").suffix(4)
        let sdkPackage = parts.joined(separator: ";")
        return c.map { $0.replacingOccurrences(of: "{path}", with: path).replacingOccurrences(of: "{name}", with: name)
            .replacingOccurrences(of: "{stem}", with: stem).replacingOccurrences(of: "{sdkPackage}", with: sdkPackage) }
    }
}

public enum CleanError: Error, Equatable {
    case notCleanable(String)
    case crossVolume(String)
    case restoreTargetExists(String)
    case commandFailed(String)
}

extension CleanError {
    /// Short text for the UI instead of the enum dump.
    public var message: String {
        switch self {
        case .notCleanable: "not cleanable (changed or no longer matches a cleanup rule)"
        case .crossVolume: "on another volume"
        case .restoreTargetExists: "something already exists at the original location"
        case .commandFailed(let out): out.isEmpty ? "failed" : String(out.prefix(160))
        }
    }
}

public struct CleanResult: Sendable {
    public var item: CleanItem
    public var quarantined: QuarantineItem?
    /// True when the path itself was deleted (tool commands clean inside it and may leave it).
    public var removed = false
    public var error: CleanError?
}

/// Cleans only what `RuleSet.match` allows, re-checked right before acting.
public final class Cleaner: Sendable {
    public let rules: RuleSet
    public let quarantine: Quarantine
    public let runner: CommandRunner

    public init(rules: RuleSet = .default, quarantine: Quarantine = Quarantine(), runner: CommandRunner = CommandRunner()) {
        self.rules = rules
        self.quarantine = quarantine
        self.runner = runner
    }

    /// Builds the plan. Throws if any path is not allowed by a rule.
    public func plan(_ paths: [(path: String, bytes: UInt64)]) throws -> [CleanItem] {
        try paths.map { p in
            guard let m = rules.match(p.path) else { throw CleanError.notCleanable(p.path) }
            return CleanItem(match: m, bytes: p.bytes)
        }
    }

    public func execute(_ items: [CleanItem]) -> [CleanResult] {
        var preDone = Set<[String]>()
        return items.map { item in
            // Re-check: the file system may have changed since the plan was made.
            guard let m = rules.match(item.path), m.rule.id == item.rule.id else {
                return CleanResult(item: item, error: .notCleanable(item.path))
            }
            if let pre = item.rule.preCommand, preDone.insert(pre).inserted { runner.run(pre) }
            if let cmd = item.command {
                let r = runner.run(cmd)
                return CleanResult(item: item, error: r.ok ? nil : .commandFailed(r.output))
            }
            // Permanent delete by request: no quarantine step. The rule re-check above is the only guard.
            let fm = FileManager.default
            if !fm.fileExists(atPath: item.path) { return CleanResult(item: item, removed: true) } // already gone
            do {
                try fm.removeItem(atPath: item.path)
                return CleanResult(item: item, removed: true)
            } catch {
                // Read-only folders (some package caches) block deletion: make them writable once and retry.
                _ = CommandRunner.query(["chmod", "-R", "u+w", item.path])
                do {
                    try fm.removeItem(atPath: item.path)
                    return CleanResult(item: item, removed: true)
                } catch {
                    return CleanResult(item: item, error: .commandFailed(error.localizedDescription))
                }
            }
        }
    }
}
