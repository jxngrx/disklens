import Foundation

/// Ties scanner, snapshot and FSEvents together: open from the saved index, catch up on changes
/// since it was saved, then stay live. Used by the app and the CLI daemon.
public final class LiveIndex: @unchecked Sendable {
    public let scanner: DiskScanner
    public var store: TreeStore { scanner.store }
    public let snapshotURL: URL
    /// Snapshot this index was opened from (nil = fresh scan).
    public let loaded: Snapshot.Meta?
    /// Paths whose changes are ignored (our own index and quarantine writes).
    public let ignore: [String]
    /// Called on the FSEvents queue after a batch of changes was applied.
    public var onChange: (@Sendable () -> Void)?

    private let lock = NSLock()
    private var watcher: FSWatcher?
    private var _caughtUp = false
    private var _needsFullRescan = false
    public var caughtUp: Bool { lock.withLock { _caughtUp } }

    public static func defaultSnapshotURL(for rootPath: String) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DiskLens")
        let key = rootPath == "/" ? "root" : String(UInt64(bitPattern: Int64(rootPath.hashValueStable)), radix: 36)
        return dir.appendingPathComponent("index-\(key).bin")
    }

    public init(rootPath: String, options: ScanOptions, hook: ListingHook?, snapshotURL: URL? = nil, ignore: [String] = []) {
        let url = snapshotURL ?? Self.defaultSnapshotURL(for: rootPath)
        self.snapshotURL = url
        self.ignore = ignore + [url.deletingLastPathComponent().path]
        if let (store, meta) = try? Snapshot.load(from: url), meta.rootPath == rootPath,
           meta.volumeUUID == FSWatcher.volumeUUID(rootPath) {
            scanner = DiskScanner(store: store, options: options, hook: hook)
            loaded = meta
        } else {
            scanner = DiskScanner(rootPath: rootPath, options: options, hook: hook)
            loaded = nil
        }
    }

    /// Fresh index: full scan with the watcher already running. From snapshot: replay FSEvents since it was saved.
    public func start(watch: Bool = true) async {
        if let meta = loaded {
            if watch { startWatcher(since: meta.eventID) } else { lock.withLock { _caughtUp = true } }
            // The snapshot keeps "Restricted" from before Full Disk Access was granted; retry those folders.
            let denied = store.nodes { $0.kind == .restricted }.map(\.id)
            if !denied.isEmpty {
                await scanner.rescan(denied)
                scanner.updateSystemOther()
                try? save()
            }
            return
        }
        let startID = FSWatcher.currentEventID
        if watch { startWatcher(since: startID) }
        await scanner.run()
        scanner.updateSystemOther()
        try? save()
    }

    public func save() throws {
        guard store.node(.root).state == .complete else { return }
        try Snapshot.save(store, to: snapshotURL, eventID: FSWatcher.currentEventID,
                          volumeUUID: FSWatcher.volumeUUID(store.rootPath))
    }

    public func stop() { watcher?.stop(); watcher = nil }

    func startWatcher(since: UInt64) {
        let root = store.rootPath
        let w = FSWatcher(paths: [root], since: since, latency: 1.0) { [weak self] changes in self?.handle(changes) }
        watcher = w
        w.start()
        if since == UInt64(kFSEventStreamEventIdSinceNow) { lock.withLock { _caughtUp = true } }
    }

    /// Event path → path as stored in the tree.
    func normalize(_ p: String) -> String? {
        let root = store.rootPath
        var p = p
        if root == "/", p.hasPrefix("/System/Volumes/Data/") { p = String(p.dropFirst("/System/Volumes/Data".count)) }
        if !root.hasPrefix("/private/"), p.hasPrefix("/private/var/") || p.hasPrefix("/private/tmp/") { p = String(p.dropFirst(8)) }
        if p.count > 1, p.hasSuffix("/") { p.removeLast() }
        guard root == "/" || p == root || p.hasPrefix(root + "/") else { return nil }
        return p
    }

    /// Nearest directory node in the tree for a path (walking up when it is new).
    func nearestDir(_ path: String) -> NodeID? {
        var p = path
        while true {
            if let id = store.find(path: p) {
                let n = store.node(id)
                return n.isDirectory ? id : store.parent(of: id)
            }
            guard p != store.rootPath, p != "/", !p.isEmpty else { return nil }
            p = (p as NSString).deletingLastPathComponent
        }
    }

    func handle(_ changes: [FileChange]) {
        if changes.contains(where: \.historyDone) { lock.withLock { _caughtUp = true } }
        if changes.contains(where: \.idsWrapped) { lock.withLock { _needsFullRescan = true } }
        let normalized = changes.compactMap { c in normalize(c.path).map { FileChange(path: $0, flags: c.flags, id: c.id) } }
        let (dirs, subtrees) = ChangeCoalescer.coalesce(normalized, ignore: ignore.compactMap { normalize($0) ?? $0 })
        var relist = Set<NodeID>()
        for d in dirs {
            // Pending folders get scanned anyway.
            if let id = nearestDir(d), store.node(id).state != .pending { relist.insert(id) }
        }
        // MustScanSubDirs / dropped events: relist every folder of the subtree in place. Sizes stay on
        // screen (no reset to "pending") and only real differences are applied.
        var subtreeRoots: [NodeID] = subtrees.compactMap { nearestDir($0) }
        if lock.withLock({ _needsFullRescan }) {
            lock.withLock { _needsFullRescan = false }
            subtreeRoots = [.root]
        }
        guard !relist.isEmpty || !subtreeRoots.isEmpty else { return }
        if !subtreeRoots.isEmpty {
            NSLog("DiskLens: relisting subtrees %@", subtreeRoots.map { store.path(of: $0) }.joined(separator: ", "))
        }
        let scanner = self.scanner
        let done = onChange
        Task.detached {
            let all = Array(relist) + subtreeRoots.flatMap { scanner.store.directories(in: $0) }
            await scanner.rescan(Array(Set(all)))
            scanner.updateSystemOther()
            done?()
        }
    }
}

extension String {
    /// Stable across launches (Swift's hashValue is seeded per process).
    var hashValueStable: Int {
        var h: UInt64 = 1469598103934665603
        for b in utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return Int(bitPattern: UInt(truncatingIfNeeded: h))
    }
}
