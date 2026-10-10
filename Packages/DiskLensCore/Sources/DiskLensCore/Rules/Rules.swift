import Darwin
import Foundation

public enum Safety: String, Codable, Sendable, Comparable {
    case safe, rebuildable, caution
    public var label: String { rawValue.capitalized }
    public static func < (a: Safety, b: Safety) -> Bool {
        [Safety.safe, .rebuildable, .caution].firstIndex(of: a)! < [Safety.safe, .rebuildable, .caution].firstIndex(of: b)!
    }
}

public struct Rule: Codable, Sendable, Identifiable, Hashable {
    public var id: UInt16
    public var name: String
    public var paths: [String]?
    public var artifact: Bool?
    public var safety: Safety
    public var ecosystem: String
    /// Tool command that cleans instead of quarantining. Placeholders: {path} {name} {stem} {sdkPackage}.
    public var command: [String]?
    public var preCommand: [String]?
    public var runningTools: [String]?
    public var keepNewest: Int?
    public var note: String?

    public var isArtifact: Bool { artifact == true }
    /// Items cleaned by a tool command cannot be quarantined or restored.
    public var quarantinable: Bool { command == nil }
}

struct RulesFile: Codable {
    var version: Int
    var projectMarkers: [String]
    var artifactFolders: [String]
    var rules: [Rule]
}

/// A path the rules allow cleaning.
public struct RuleMatch: Sendable, Hashable {
    public var rule: Rule
    public var path: String
    /// Project folder that owns an artifact folder.
    public var projectPath: String?
}

/// Loads `rules.json` and decides what is cleanable. `match` checks the real file system every time,
/// so nothing outside a rule's paths (or a project's known artifact folders) can ever be selected.
public struct RuleSet: Sendable {
    public let rules: [Rule]
    public let projectMarkers: [String]
    public let artifactFolders: [String]
    let patterns: [(pattern: String, rule: Rule)]

    /// `home`, `tmpDir` and `androidHome` are injectable so tests point the rules at fixtures.
    public init(data: Data? = nil, home: String = NSHomeDirectory(), tmpDir: String = NSTemporaryDirectory(),
                androidHome: String? = ProcessInfo.processInfo.environment["ANDROID_HOME"]) throws {
        let raw = try data ?? Data(contentsOf: Bundle.module.url(forResource: "rules", withExtension: "json")!)
        let file = try JSONDecoder().decode(RulesFile.self, from: raw)
        rules = file.rules
        projectMarkers = file.projectMarkers
        artifactFolders = file.artifactFolders
        let tmp = tmpDir.hasSuffix("/") ? String(tmpDir.dropLast()) : tmpDir
        let android = androidHome ?? home + "/Library/Android/sdk"
        var pats: [(String, Rule)] = []
        for r in file.rules {
            for p in r.paths ?? [] {
                let expanded = p.replacingOccurrences(of: "~", with: home)
                    .replacingOccurrences(of: "$TMPDIR", with: tmp)
                    .replacingOccurrences(of: "$ANDROID_HOME", with: android)
                pats.append((expanded, r))
                // Scans from `/` reach /var/... through /private.
                if expanded.hasPrefix("/var/") || expanded.hasPrefix("/tmp/") { pats.append(("/private" + expanded, r)) }
            }
        }
        patterns = pats
    }

    public static let `default`: RuleSet = try! RuleSet()

    public func rule(id: UInt16) -> Rule? { rules.first { $0.id == id } }
    public var artifactRule: Rule { rules.first { $0.isArtifact }! }

    /// The rule that allows cleaning `path`, if any. Never matches symlinks, the home folder or `/`.
    public func match(_ path: String) -> RuleMatch? {
        guard path.hasPrefix("/"), path.count > 1, !path.contains("/../"), !path.hasSuffix("/..") else { return nil }
        var st = stat()
        guard lstat(path, &st) == 0, (st.st_mode & S_IFMT) != S_IFLNK else { return nil }
        for (pattern, rule) in patterns where fnmatch(pattern, path, FNM_PATHNAME) == 0 {
            if let keep = rule.keepNewest, isAmongNewest(path, pattern: pattern, keep: keep) { return nil }
            return RuleMatch(rule: rule, path: path)
        }
        if (st.st_mode & S_IFMT) == S_IFDIR, let project = projectOwning(artifact: path) {
            return RuleMatch(rule: artifactRule, path: path, projectPath: project)
        }
        return nil
    }

    /// For `.../proj/ios/Pods`, returns `.../proj` when it has a project marker file.
    public func projectOwning(artifact path: String) -> String? {
        for rel in artifactFolders where path.hasSuffix("/" + rel) {
            let project = String(path.dropLast(rel.count + 1))
            if !project.isEmpty, isProject(project) { return project }
        }
        return nil
    }

    public func isProject(_ dir: String) -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return false }
        return isProject(entries: names)
    }

    public func isProject(entries names: [String]) -> Bool {
        names.contains { n in projectMarkers.contains { fnmatch($0, n, 0) == 0 } }
    }

    func isAmongNewest(_ path: String, pattern: String, keep: Int) -> Bool {
        let parent = (path as NSString).deletingLastPathComponent
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: parent) else { return true }
        let siblings = names.map { parent + "/" + $0 }.filter { fnmatch(pattern, $0, FNM_PATHNAME) == 0 }
        func mtime(_ p: String) -> Int { var s = stat(); return lstat(p, &s) == 0 ? s.st_mtimespec.tv_sec : 0 }
        let newest = siblings.sorted { mtime($0) > mtime($1) }.prefix(keep)
        return newest.contains(path)
    }

    /// Scanner hook: marks projects and tags cleanable folders as they are listed.
    public func listingHook() -> ListingHook {
        { store, dir, path, entries, newDirs in
            if self.isProject(entries: entries.map(\.name)) { store.setProject(dir) }
            let base = path == "/" ? "" : path
            for id in newDirs {
                let child = base + "/" + store.node(id).name
                // Cheap prefilter before touching the file system.
                let name = (child as NSString).lastPathComponent
                let maybeArtifact = self.artifactFolders.contains { $0 == name || $0.hasSuffix("/" + name) }
                let maybePattern = self.patterns.contains { fnmatch($0.pattern, child, FNM_PATHNAME) == 0 }
                guard maybeArtifact || maybePattern, let m = self.match(child) else { continue }
                store.setRule(id, m.rule.id)
            }
        }
    }
}
