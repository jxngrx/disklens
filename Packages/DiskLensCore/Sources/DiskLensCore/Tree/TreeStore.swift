import Foundation

public struct NodeID: Hashable, Sendable {
    public let raw: Int32
    public init(_ raw: Int32) { self.raw = raw }
    public static let root = NodeID(0)
}

public enum NodeKind: UInt8, Sendable { case dir, file, bundle, otherFiles, restricted, systemOther }
public enum ScanState: UInt8, Sendable { case pending, partial, complete }

/// Read-only copy of one node for the UI.
public struct NodeInfo: Identifiable, Hashable, Sendable {
    public var id: NodeID
    public var name: String
    public var kind: NodeKind
    public var totalBytes: UInt64
    public var fileCount: UInt32
    public var modified: Int64
    public var state: ScanState
    public var ruleID: UInt16
    public var hasChildren: Bool
    public var isDirectory: Bool { kind == .dir || kind == .bundle }
}

/// Result of listing one directory, already deduped and folded by the scanner.
public struct Listing: Sendable {
    public var dirs: [(name: String, kind: NodeKind, modified: Int64)] = []
    public var files: [(name: String, bytes: UInt64, modified: Int64)] = []
    public var otherCount: UInt32 = 0
    public var otherBytes: UInt64 = 0
    public var ownBytes: UInt64 = 0
    public var ownFiles: UInt32 = 0
    public var modified: Int64 = 0
    public init() {}
}

/// Single source of truth. Parallel arrays indexed by `NodeID.raw`, guarded by one lock.
/// ponytail: one global lock; shard it if worker contention shows up in profiles.
public final class TreeStore: @unchecked Sendable {
    public let rootPath: String
    let lock = NSLock()

    var name: [String] = []
    var parent: [Int32] = []
    var firstChild: [Int32] = []
    var nextSibling: [Int32] = []
    var kind: [NodeKind] = []
    var ownBytes: [UInt64] = []
    var totalBytes: [UInt64] = []
    var ownFiles: [UInt32] = []
    var fileCount: [UInt32] = []
    var modified: [Int64] = []
    var state: [ScanState] = []
    var ruleID: [UInt16] = []
    var pendingChildren: [Int32] = []
    var projectFlags: [Bool] = []
    /// Bumped on every mutation so observers can poll cheaply.
    public private(set) var version: UInt64 = 0

    public init(rootPath: String, rootName: String) {
        self.rootPath = rootPath
        _ = append(name: rootName, parent: -1, kind: .dir, state: .pending, modified: 0)
    }

    public var count: Int { lock.withLock { name.count } }

    // MARK: - Writes (internal, caller does not hold the lock)

    @discardableResult
    func append(name n: String, parent p: Int32, kind k: NodeKind, state s: ScanState, modified m: Int64) -> Int32 {
        let id = Int32(name.count)
        name.append(n); parent.append(p); kind.append(k); state.append(s); modified.append(m)
        firstChild.append(-1); nextSibling.append(-1)
        ownBytes.append(0); totalBytes.append(0); ownFiles.append(0); fileCount.append(0)
        ruleID.append(0); pendingChildren.append(0); projectFlags.append(false)
        if p >= 0 {
            nextSibling[Int(id)] = firstChild[Int(p)]
            firstChild[Int(p)] = id
        }
        return id
    }

    /// Adds deltas to `id` and every ancestor.
    func rollUp(from id: Int32, bytes: Int64, files: Int64) {
        guard bytes != 0 || files != 0 else { return }
        var i = id
        while i >= 0 {
            totalBytes[Int(i)] = UInt64(max(0, Int64(totalBytes[Int(i)]) + bytes))
            fileCount[Int(i)] = UInt32(max(0, Int64(fileCount[Int(i)]) + files))
            i = parent[Int(i)]
        }
    }

    func childCompleted(_ p: Int32) {
        var p = p
        while p >= 0 {
            pendingChildren[Int(p)] -= 1
            guard pendingChildren[Int(p)] <= 0, state[Int(p)] == .partial else { return }
            state[Int(p)] = .complete
            p = parent[Int(p)]
        }
    }

    /// A complete node gets new pending work: walk up re-opening complete ancestors.
    func reopen(_ id: Int32) {
        var i = id
        while i >= 0, state[Int(i)] == .complete {
            state[Int(i)] = .partial
            let p = parent[Int(i)]
            if p >= 0 { pendingChildren[Int(p)] += 1 }
            i = p
        }
    }

    func unlink(_ id: Int32) {
        let p = parent[Int(id)]
        guard p >= 0 else { return }
        if firstChild[Int(p)] == id {
            firstChild[Int(p)] = nextSibling[Int(id)]
        } else {
            var c = firstChild[Int(p)]
            while c >= 0 {
                if nextSibling[Int(c)] == id { nextSibling[Int(c)] = nextSibling[Int(id)]; break }
                c = nextSibling[Int(c)]
            }
        }
        // ponytail: detached nodes stay in the arrays as garbage; compact on snapshot save.
        rollUp(from: p, bytes: -Int64(totalBytes[Int(id)]), files: -Int64(fileCount[Int(id)]))
        if state[Int(id)] != .complete && (kind[Int(id)] == .dir || kind[Int(id)] == .bundle) {
            childCompleted(p)
        }
        parent[Int(id)] = -1
        nextSibling[Int(id)] = -1
    }

    /// Applies a directory listing (first scan or rescan). Existing dir children are matched
    /// by name and kept; new dirs are returned so the scanner can queue them.
    public func apply(_ listing: Listing, to node: NodeID) -> [NodeID] {
        lock.withLock {
            let id = node.raw
            guard Int(id) < name.count, parent[Int(id)] >= 0 || id == 0 else { return [] }
            var oldDirs: [String: Int32] = [:]
            var c = firstChild[Int(id)]
            while c >= 0 {
                let next = nextSibling[Int(c)]
                switch kind[Int(c)] {
                case .file, .otherFiles: unlinkLeaf(c)
                default: oldDirs[name[Int(c)]] = c
                }
                c = next
            }
            let wasListed = state[Int(id)] != .pending
            rollUp(from: id, bytes: Int64(listing.ownBytes) - Int64(ownBytes[Int(id)]),
                   files: Int64(listing.ownFiles) - Int64(ownFiles[Int(id)]))
            ownBytes[Int(id)] = listing.ownBytes
            ownFiles[Int(id)] = listing.ownFiles
            modified[Int(id)] = listing.modified

            var added: [NodeID] = []
            for d in listing.dirs {
                if oldDirs.removeValue(forKey: d.name) != nil { continue }
                let k = append(name: d.name, parent: id, kind: d.kind, state: .pending, modified: d.modified)
                added.append(NodeID(k))
            }
            for (_, gone) in oldDirs { unlink(gone) }
            for f in listing.files {
                let k = append(name: f.name, parent: id, kind: .file, state: .complete, modified: f.modified)
                ownBytes[Int(k)] = f.bytes; totalBytes[Int(k)] = f.bytes
                ownFiles[Int(k)] = 1; fileCount[Int(k)] = 1
            }
            if listing.otherCount > 0 {
                let k = append(name: "\(listing.otherCount) other files", parent: id, kind: .otherFiles,
                               state: .complete, modified: 0)
                ownBytes[Int(k)] = listing.otherBytes; totalBytes[Int(k)] = listing.otherBytes
                ownFiles[Int(k)] = listing.otherCount; fileCount[Int(k)] = listing.otherCount
            }

            if !wasListed {
                pendingChildren[Int(id)] += Int32(added.count)
                state[Int(id)] = .partial
                if pendingChildren[Int(id)] <= 0 {
                    state[Int(id)] = .complete
                    if parent[Int(id)] >= 0 { childCompleted(parent[Int(id)]) }
                }
            } else if !added.isEmpty {
                reopen(id)
                pendingChildren[Int(id)] += Int32(added.count)
            }
            version &+= 1
            return added
        }
    }

    /// Leaf nodes never carry pending state, so unlinking them is just a list edit (totals
    /// for files are part of the parent's ownBytes and are fixed by `apply`).
    func unlinkLeaf(_ id: Int32) {
        let p = parent[Int(id)]
        if firstChild[Int(p)] == id {
            firstChild[Int(p)] = nextSibling[Int(id)]
        } else {
            var c = firstChild[Int(p)]
            while c >= 0 {
                if nextSibling[Int(c)] == id { nextSibling[Int(c)] = nextSibling[Int(id)]; break }
                c = nextSibling[Int(c)]
            }
        }
        parent[Int(id)] = -1
        nextSibling[Int(id)] = -1
    }

    public func markRestricted(_ node: NodeID) {
        lock.withLock {
            let id = node.raw
            let wasPending = state[Int(id)] == .pending
            kind[Int(id)] = .restricted
            state[Int(id)] = .complete
            if wasPending, parent[Int(id)] >= 0 { childCompleted(parent[Int(id)]) }
            version &+= 1
        }
    }

    /// Resets a directory so its whole subtree is scanned again (FSEvents MustScanSubDirs).
    public func resetSubtree(_ node: NodeID) {
        lock.withLock {
            let id = node.raw
            var c = firstChild[Int(id)]
            while c >= 0 {
                let next = nextSibling[Int(c)]
                if kind[Int(c)] == .file || kind[Int(c)] == .otherFiles { unlinkLeaf(c) } else { unlink(c) }
                c = next
            }
            rollUp(from: id, bytes: -Int64(ownBytes[Int(id)]), files: -Int64(ownFiles[Int(id)]))
            ownBytes[Int(id)] = 0; ownFiles[Int(id)] = 0
            if state[Int(id)] == .complete, parent[Int(id)] >= 0 {
                reopen(parent[Int(id)])
                pendingChildren[Int(parent[Int(id)])] += 1
            }
            state[Int(id)] = .pending
            pendingChildren[Int(id)] = 0
            version &+= 1
        }
    }

    /// Removes a node right away (after a clean) so the map updates before FSEvents confirms.
    public func remove(_ node: NodeID) {
        lock.withLock {
            guard node.raw > 0, parent[Int(node.raw)] >= 0 else { return }
            if kind[Int(node.raw)] == .file || kind[Int(node.raw)] == .otherFiles {
                let p = parent[Int(node.raw)]
                rollUp(from: p, bytes: -Int64(totalBytes[Int(node.raw)]), files: -Int64(fileCount[Int(node.raw)]))
                ownBytes[Int(p)] -= min(ownBytes[Int(p)], totalBytes[Int(node.raw)])
                ownFiles[Int(p)] -= min(ownFiles[Int(p)], fileCount[Int(node.raw)])
                unlinkLeaf(node.raw)
            } else {
                unlink(node.raw)
            }
            version &+= 1
        }
    }

    /// Sets (or replaces) the root's "System & other" child.
    public func setSystemOther(bytes: UInt64) {
        lock.withLock {
            var c = firstChild[0]
            while c >= 0 {
                if kind[Int(c)] == .systemOther {
                    rollUp(from: c, bytes: Int64(bytes) - Int64(totalBytes[Int(c)]), files: 0)
                    ownBytes[Int(c)] = bytes
                    version &+= 1
                    return
                }
                c = nextSibling[Int(c)]
            }
            let k = append(name: "System & other", parent: 0, kind: .systemOther, state: .complete, modified: 0)
            ownBytes[Int(k)] = bytes
            rollUp(from: k, bytes: Int64(bytes), files: 0)
            version &+= 1
        }
    }

    public func setRule(_ node: NodeID, _ rule: UInt16) {
        lock.withLock { ruleID[Int(node.raw)] = rule; version &+= 1 }
    }

    public func setProject(_ node: NodeID) {
        lock.withLock { projectFlags[Int(node.raw)] = true }
    }

    // MARK: - Reads

    func info(_ i: Int32) -> NodeInfo {
        NodeInfo(id: NodeID(i), name: name[Int(i)], kind: kind[Int(i)], totalBytes: totalBytes[Int(i)],
                 fileCount: fileCount[Int(i)], modified: modified[Int(i)], state: state[Int(i)],
                 ruleID: ruleID[Int(i)], hasChildren: firstChild[Int(i)] >= 0)
    }

    public func node(_ id: NodeID) -> NodeInfo { lock.withLock { info(id.raw) } }

    /// Children sorted by size, largest first.
    public func children(of id: NodeID) -> [NodeInfo] {
        lock.withLock {
            var out: [NodeInfo] = []
            var c = firstChild[Int(id.raw)]
            while c >= 0 { out.append(info(c)); c = nextSibling[Int(c)] }
            return out.sorted { $0.totalBytes != $1.totalBytes ? $0.totalBytes > $1.totalBytes : $0.name < $1.name }
        }
    }

    public func parent(of id: NodeID) -> NodeID? {
        lock.withLock { parent[Int(id.raw)] >= 0 ? NodeID(parent[Int(id.raw)]) : nil }
    }

    /// Root first, `id` last.
    public func ancestry(of id: NodeID) -> [NodeID] {
        lock.withLock {
            var out: [NodeID] = []
            var i = id.raw
            while i >= 0 { out.append(NodeID(i)); i = parent[Int(i)] }
            return out.reversed()
        }
    }

    public func path(of id: NodeID) -> String {
        lock.withLock { pathUnlocked(id.raw) }
    }

    func pathUnlocked(_ id: Int32) -> String {
        var parts: [String] = []
        var i = id
        while i > 0 { parts.append(name[Int(i)]); i = parent[Int(i)] }
        guard i == 0 else { return "" } // detached
        let base = rootPath == "/" ? "" : rootPath
        return parts.isEmpty ? rootPath : base + "/" + parts.reversed().joined(separator: "/")
    }

    /// Finds the node for an absolute path under the root, if it is in the tree.
    public func find(path: String) -> NodeID? {
        lock.withLock {
            guard path.hasPrefix(rootPath) else { return nil }
            var cur: Int32 = 0
            for comp in path.dropFirst(rootPath.count).split(separator: "/") {
                var c = firstChild[Int(cur)]
                while c >= 0, name[Int(c)] != comp { c = nextSibling[Int(c)] }
                guard c >= 0 else { return nil }
                cur = c
            }
            return NodeID(cur)
        }
    }

    public func isDescendant(_ id: NodeID, of ancestor: NodeID) -> Bool {
        lock.withLock {
            var i = id.raw
            while i >= 0 { if i == ancestor.raw { return true }; i = parent[Int(i)] }
            return false
        }
    }

    func isLive(_ id: Int32) -> Bool {
        var i = id
        while i > 0 { i = parent[Int(i)] }
        return i == 0
    }

    public func isProject(_ id: NodeID) -> Bool { lock.withLock { projectFlags[Int(id.raw)] } }

    /// Directories in the subtree sorted by size (excluding root), for the CLI.
    public func largestDirectories(limit: Int) -> [(path: String, bytes: UInt64)] {
        lock.withLock {
            var ids: [Int32] = []
            for i in 1..<Int32(name.count) where (kind[Int(i)] == .dir || kind[Int(i)] == .bundle) && parent[Int(i)] >= 0 {
                ids.append(i)
            }
            ids.sort { totalBytes[Int($0)] > totalBytes[Int($1)] }
            return ids.prefix(limit).map { (pathUnlocked($0), totalBytes[Int($0)]) }
        }
    }

    /// All live nodes matching a predicate (used by rule tagging and projects view).
    public func nodes(where match: (NodeInfo) -> Bool) -> [NodeInfo] {
        lock.withLock {
            var out: [NodeInfo] = []
            for i in 0..<Int32(name.count) where i == 0 || parent[Int(i)] >= 0 {
                let n = info(i)
                if match(n) && isLive(i) { out.append(n) }
            }
            return out
        }
    }
}
