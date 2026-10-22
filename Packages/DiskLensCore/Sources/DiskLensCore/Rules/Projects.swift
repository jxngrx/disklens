import Darwin
import Foundation

public struct ProjectArtifact: Sendable, Hashable, Identifiable {
    public var id: NodeID
    public var path: String
    public var bytes: UInt64
}

public struct ProjectInfo: Sendable, Identifiable, Hashable {
    public var id: String { path }
    public var path: String
    public var name: String { (path as NSString).lastPathComponent }
    public var artifacts: [ProjectArtifact]
    public var reclaimable: UInt64 { artifacts.reduce(0) { $0 + $1.bytes } }
}

public enum Projects {
    /// Projects that own at least one artifact folder, biggest reclaimable first. Nested artifacts
    /// (a node_modules inside node_modules) are folded into their outermost artifact.
    public static func collect(store: TreeStore, rules: RuleSet) -> [ProjectInfo] {
        let artifactID = rules.artifactRule.id
        let tagged = store.ruleTaggedNodes().filter { $0.ruleID == artifactID }
            .map { (info: $0, path: store.path(of: $0.id)) }
            .filter { !$0.path.isEmpty }
            .sorted { $0.path < $1.path }
        var groups: [String: [ProjectArtifact]] = [:]
        var lastTop: String?
        for t in tagged {
            if let top = lastTop, t.path.hasPrefix(top + "/") { continue }
            lastTop = t.path
            guard let project = rules.projectOwning(artifact: t.path) else { continue }
            groups[project, default: []].append(ProjectArtifact(id: t.info.id, path: t.path, bytes: t.info.totalBytes))
        }
        return groups.map { ProjectInfo(path: $0.key, artifacts: $0.value) }.sorted { $0.reclaimable > $1.reclaimable }
    }

    /// Later of the last git commit and the newest source file mtime (artifact folders and .git excluded).
    /// Access time is never used: it is unreliable on macOS.
    /// ponytail: walk capped at `limit` entries; huge monorepos fall back to whatever was seen.
    public static func lastWorkedOn(_ project: String, rules: RuleSet, limit: Int = 50_000) -> Date? {
        var newest: Int = 0
        let skip = Set(rules.artifactFolders.map { project + "/" + $0 } + [project + "/.git"])
        var stack = [project]
        var seen = 0
        while let dir = stack.popLast(), seen < limit {
            guard case .success(let entries) = DirectoryReader.read(dir) else { continue }
            for e in entries {
                seen += 1
                let p = dir + "/" + e.name
                if e.isDir {
                    if !skip.contains(p) && !rules.artifactFolders.contains(e.name) { stack.append(p) }
                } else {
                    newest = max(newest, Int(e.modified))
                }
            }
        }
        if let out = CommandRunner.query(["git", "-C", project, "log", "-1", "--format=%ct"]),
           let t = Int(out.trimmingCharacters(in: .whitespacesAndNewlines)) {
            newest = max(newest, t)
        }
        return newest > 0 ? Date(timeIntervalSince1970: TimeInterval(newest)) : nil
    }

    /// Lockfile-based restore command for a cleaned project (Pro restore button).
    public static func restoreCommand(_ project: String) -> [String]? {
        let fm = FileManager.default
        func has(_ f: String) -> Bool { fm.fileExists(atPath: project + "/" + f) }
        if has("pnpm-lock.yaml") { return ["pnpm", "install", "--frozen-lockfile"] }
        if has("yarn.lock") { return ["yarn", "install", "--frozen-lockfile"] }
        if has("package-lock.json") { return ["npm", "ci"] }
        if has("Podfile.lock") || has("Podfile") { return ["pod", "install"] }
        if has("ios/Podfile.lock") { return ["pod", "install", "--project-directory=ios"] }
        return nil
    }
}
