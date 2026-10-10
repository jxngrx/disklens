import Darwin
import Foundation

/// Directory waiting to be listed.
struct ScanItem: Sendable {
    var id: NodeID
    var path: String
}

/// Two-tier work queue: the subtree the user is looking at goes first.
/// LIFO inside each tier (depth-first) so started subtrees finish early and the queue stays small.
actor ScanQueue {
    private var high: [ScanItem] = []
    private var normal: [ScanItem] = []
    private var focus: NodeID?
    private var inFlight = 0
    private var stopped = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    let store: TreeStore

    init(store: TreeStore) { self.store = store }

    func push(_ items: [ScanItem]) {
        for item in items {
            if let f = focus, store.isDescendant(item.id, of: f) { high.append(item) } else { normal.append(item) }
        }
        wake()
    }

    func next() async -> ScanItem? {
        while true {
            if stopped { return nil }
            if let item = high.popLast() ?? normal.popLast() { inFlight += 1; return item }
            if inFlight == 0 { wake(); return nil }
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    func finished(_ children: [ScanItem]) {
        inFlight -= 1
        push(children)
    }

    func setFocus(_ id: NodeID?) {
        focus = id
        let all = normal + high
        high = []; normal = []
        push(all)
    }

    func stop() { stopped = true; wake() }

    var isIdle: Bool { high.isEmpty && normal.isEmpty && inFlight == 0 }

    private func wake() {
        let w = waiters
        waiters = []
        w.forEach { $0.resume() }
    }
}

public struct ScanOptions: Sendable {
    public var workers = 8
    /// Files at least this big get their own node (up to `maxFilesPerDir`); the rest fold into "N other files".
    public var fileNodeMinBytes: UInt64 = 1 << 20
    public var maxFilesPerDir = 50
    public var skipPaths: Set<String> = []
    public init() {}

    /// Defaults for scanning the startup volume from `/`.
    public static var startupVolume: ScanOptions {
        var o = ScanOptions()
        o.skipPaths = ["/Volumes", "/dev", "/System/Volumes", "/.fseventsd", "/.Spotlight-V100",
                       "/.DocumentRevisions-V100", "/.MobileBackups"]
        return o
    }
}

/// Hook to tag nodes (rules, projects) as directories are listed.
public typealias ListingHook = @Sendable (_ store: TreeStore, _ dir: NodeID, _ path: String,
                                          _ entries: [DirEntry], _ newDirs: [NodeID]) -> Void

public final class Scanner: Sendable {
    public let store: TreeStore
    public let options: ScanOptions
    let queue: ScanQueue
    let allowedDevices: Set<Int32>
    let hardLinks = HardLinkTable()
    let hook: ListingHook?

    static let bundleExtensions: Set<String> = ["app", "framework", "bundle", "plugin", "appex", "kext", "xpc",
                                                "photoslibrary", "xcarchive", "simruntime", "docset"]

    public init(rootPath: String, rootName: String? = nil, options: ScanOptions = ScanOptions(), hook: ListingHook? = nil) {
        let root = rootPath == "/" ? "/" : (rootPath.hasSuffix("/") ? String(rootPath.dropLast()) : rootPath)
        store = TreeStore(rootPath: root, rootName: rootName ?? (root == "/" ? "Macintosh HD" : (root as NSString).lastPathComponent))
        self.options = options
        self.hook = hook
        queue = ScanQueue(store: store)
        var devs: Set<Int32> = []
        var st = stat()
        if lstat(root, &st) == 0 { devs.insert(st.st_dev) }
        // `/Users`, `/Applications`, ... are firmlinks into the Data volume, which has its own device id.
        if root == "/", lstat("/System/Volumes/Data", &st) == 0 { devs.insert(st.st_dev) }
        allowedDevices = devs
    }

    /// Scans everything under the root. Returns when the queue drains or `stop()` is called.
    public func run() async {
        await queue.push([ScanItem(id: .root, path: store.rootPath)])
        await drain()
    }

    /// Queues directories to (re)list, e.g. from FSEvents, and processes them.
    public func rescan(_ ids: [NodeID]) async {
        await queue.push(ids.map { ScanItem(id: $0, path: store.path(of: $0)) }.filter { !$0.path.isEmpty })
        await drain()
    }

    public func setFocus(_ id: NodeID?) async { await queue.setFocus(id) }
    public func stop() async { await queue.stop() }

    func drain() async {
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<options.workers {
                group.addTask {
                    while let item = await self.queue.next() {
                        let children = self.process(item)
                        await self.queue.finished(children)
                    }
                }
            }
        }
    }

    func process(_ item: ScanItem) -> [ScanItem] {
        switch DirectoryReader.read(item.path) {
        case .failure(.denied):
            store.markRestricted(item.id)
            return []
        case .failure:
            // Vanished or unreadable for another reason: record as empty.
            _ = store.apply(Listing(), to: item.id)
            return []
        case .success(let entries):
            let listing = makeListing(dirPath: item.path, owner: item.id, entries: entries)
            let added = store.apply(listing, to: item.id)
            hook?(store, item.id, item.path, entries, added)
            let base = item.path == "/" ? "" : item.path
            return added.map { ScanItem(id: $0, path: base + "/" + store.node($0).name) }
        }
    }

    func makeListing(dirPath: String, owner: NodeID, entries: [DirEntry]) -> Listing {
        var l = Listing()
        var st = stat()
        if lstat(dirPath, &st) == 0 { l.modified = Int64(st.st_mtimespec.tv_sec) }
        let base = dirPath == "/" ? "" : dirPath
        var files: [(name: String, bytes: UInt64, modified: Int64)] = []
        var seenLinks = Set<UInt64>()
        for e in entries {
            if e.isDir {
                let full = base + "/" + e.name
                if options.skipPaths.contains(full) || !allowedDevices.contains(e.device) { continue }
                let ext = (e.name as NSString).pathExtension.lowercased()
                l.dirs.append((e.name, Self.bundleExtensions.contains(ext) ? .bundle : .dir, e.modified))
                continue
            }
            var bytes = e.allocatedBytes
            if e.linkCount > 1,
               !seenLinks.insert(e.inode).inserted || !hardLinks.claim(device: e.device, inode: e.inode, owner: owner.raw) {
                bytes = 0
            }
            l.ownBytes += bytes
            l.ownFiles += 1
            files.append((e.name, bytes, e.modified))
        }
        files.sort { $0.bytes > $1.bytes }
        let keep = files.prefix(options.maxFilesPerDir).prefix { $0.bytes >= options.fileNodeMinBytes }
        l.files = Array(keep)
        for f in files.dropFirst(keep.count) { l.otherCount += 1; l.otherBytes += f.bytes }
        return l
    }

    /// Volume used bytes (total − available) for the volume holding `path`.
    public static func volumeUsedBytes(_ path: String = "/") -> UInt64? {
        let url = URL(fileURLWithPath: path)
        guard let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
              let total = v.volumeTotalCapacity, let avail = v.volumeAvailableCapacity else { return nil }
        return UInt64(max(0, total - avail))
    }

    /// Adds the "System & other" box so the root total matches the volume's used space.
    public func updateSystemOther() {
        guard store.rootPath == "/", let used = Self.volumeUsedBytes() else { return }
        let scanned = store.children(of: .root).filter { $0.kind != .systemOther }.reduce(UInt64(0)) { $0 + $1.totalBytes }
        store.setSystemOther(bytes: used > scanned ? used - scanned : 0)
    }
}

/// Counts each hard-linked inode once. The first directory to see it owns the bytes,
/// so a rescan of that same directory still counts it.
final class HardLinkTable: @unchecked Sendable {
    private struct Key: Hashable { var dev: Int32; var ino: UInt64 }
    private var owners: [Key: Int32] = [:]
    private let lock = NSLock()

    func claim(device: Int32, inode: UInt64, owner: Int32) -> Bool {
        lock.withLock {
            let k = Key(dev: device, ino: inode)
            if let o = owners[k] { return o == owner }
            owners[k] = owner
            return true
        }
    }
}
