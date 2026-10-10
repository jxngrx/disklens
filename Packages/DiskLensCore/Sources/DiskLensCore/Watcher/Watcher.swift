import CoreServices
import Darwin
import Foundation

public struct FileChange: Sendable {
    public var path: String
    public var flags: UInt32
    public var id: UInt64

    public var mustScanSubDirs: Bool {
        flags & UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped) != 0
    }
    public var historyDone: Bool { flags & UInt32(kFSEventStreamEventFlagHistoryDone) != 0 }
    public var idsWrapped: Bool { flags & UInt32(kFSEventStreamEventFlagEventIdsWrapped | kFSEventStreamEventFlagRootChanged) != 0 }
    public var isDir: Bool { flags & UInt32(kFSEventStreamEventFlagItemIsDir) != 0 }
}

/// Thin FSEventStream wrapper: file-level events, ~1 s latency, delivered on a private queue.
public final class FSWatcher: @unchecked Sendable {
    let handler: @Sendable ([FileChange]) -> Void
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "disklens.fsevents")

    public init(paths: [String], since: UInt64 = UInt64(kFSEventStreamEventIdSinceNow), latency: Double = 1.0,
                handler: @escaping @Sendable ([FileChange]) -> Void) {
        self.handler = handler
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, ids in
            let me = Unmanaged<FSWatcher>.fromOpaque(info!).takeUnretainedValue()
            let cfPaths = unsafeBitCast(paths, to: NSArray.self)
            var out: [FileChange] = []
            out.reserveCapacity(count)
            for i in 0..<count {
                out.append(FileChange(path: cfPaths[i] as! String, flags: flags[i], id: ids[i]))
            }
            me.handler(out)
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot)
        stream = FSEventStreamCreate(nil, callback, &ctx, paths as CFArray, since, latency, flags)
    }

    public func start() {
        guard let s = stream else { return }
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
    }

    public func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    deinit { stop() }

    public static var currentEventID: UInt64 { FSEventsGetCurrentEventId() }

    /// FSEvents database UUID for the volume holding `path`; changes when history is reset.
    public static func volumeUUID(_ path: String) -> String {
        var st = stat()
        guard lstat(path, &st) == 0, let uuid = FSEventsCopyUUIDForDevice(st.st_dev) else { return "" }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

/// Turns raw events into directories to relist and subtrees to rescan.
public enum ChangeCoalescer {
    /// - `ignore`: path prefixes of the app's own writes (index, quarantine).
    /// - When more than `siblingLimit` child folders of one parent changed, the parent subtree is rescanned once.
    public static func coalesce(_ changes: [FileChange], ignore: [String], siblingLimit: Int = 8) -> (dirs: Set<String>, subtrees: Set<String>) {
        var dirs = Set<String>()
        var subtrees = Set<String>()
        for c in changes {
            let p = c.path.hasSuffix("/") && c.path.count > 1 ? String(c.path.dropLast()) : c.path
            if ignore.contains(where: { p == $0 || p.hasPrefix($0 + "/") }) { continue }
            if c.historyDone { continue }
            if c.mustScanSubDirs { subtrees.insert(p); continue }
            // A changed file or folder changes its parent's listing.
            dirs.insert((p as NSString).deletingLastPathComponent)
            if c.isDir { dirs.insert(p) }
        }
        var byParent: [String: Int] = [:]
        for d in dirs { byParent[(d as NSString).deletingLastPathComponent, default: 0] += 1 }
        for (parent, n) in byParent where n > siblingLimit { subtrees.insert(parent) }
        // Drop anything already covered by a subtree rescan.
        let covered = { (p: String) in subtrees.contains { p == $0 || p.hasPrefix($0 == "/" ? "/" : $0 + "/") } }
        dirs = dirs.filter { !covered($0) }
        subtrees = subtrees.filter { s in !subtrees.contains { $0 != s && s.hasPrefix($0 == "/" ? "/" : $0 + "/") } }
        return (dirs, subtrees)
    }
}
