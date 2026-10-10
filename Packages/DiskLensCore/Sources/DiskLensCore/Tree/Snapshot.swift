import Foundation

/// Compact binary snapshot of a TreeStore: header, then one fixed-size record per live node, then names.
/// Detached nodes are dropped (compaction). Read through a memory-mapped `Data`.
public enum Snapshot {
    static let magic: UInt32 = 0x4E53_4C44 // "DLSN"
    static let version: UInt32 = 1
    // parent i32, kind u8, state u8, ruleID u16, project u8, pad 3, ownBytes u64, totalBytes u64,
    // ownFiles u32, fileCount u32, modified i64, nameOffset u32, nameLength u32
    static let recordSize = 4 + 1 + 1 + 2 + 1 + 3 + 8 + 8 + 4 + 4 + 8 + 4 + 4

    public struct Meta: Sendable {
        public var eventID: UInt64
        public var volumeUUID: String
        public var savedAt: Date
        public var rootPath: String
        public var nodeCount: Int
    }

    public static func save(_ store: TreeStore, to url: URL, eventID: UInt64, volumeUUID: String) throws {
        let data = store.lock.withLock { () -> Data in
            // Breadth-first so parents come before children; new ids are positions in `order`.
            var order: [Int32] = [0]
            var newID = [Int32](repeating: -1, count: store.name.count)
            newID[0] = 0
            var i = 0
            while i < order.count {
                var c = store.firstChild[Int(order[i])]
                while c >= 0 {
                    newID[Int(c)] = Int32(order.count)
                    order.append(c)
                    c = store.nextSibling[Int(c)]
                }
                i += 1
            }
            var names = Data()
            var out = Data()
            out.reserveCapacity(64 + order.count * recordSize)
            func put<T>(_ v: T) { withUnsafeBytes(of: v) { out.append(contentsOf: $0) } }
            let root = Data(store.rootPath.utf8), uuid = Data(volumeUUID.utf8)
            put(magic); put(version); put(UInt32(order.count)); put(eventID)
            put(Date().timeIntervalSince1970)
            put(UInt32(root.count)); out.append(root)
            put(UInt32(uuid.count)); out.append(uuid)
            for old in order {
                let o = Int(old)
                let p = store.parent[o]
                let nameBytes = Data(store.name[o].utf8)
                put(p >= 0 ? newID[Int(p)] : -1)
                put(store.kind[o].rawValue); put(store.state[o].rawValue); put(store.ruleID[o])
                put(UInt8(store.projectFlags[o] ? 1 : 0)); put(UInt8(0)); put(UInt8(0)); put(UInt8(0))
                put(store.ownBytes[o]); put(store.totalBytes[o]); put(store.ownFiles[o]); put(store.fileCount[o])
                put(store.modified[o]); put(UInt32(names.count)); put(UInt32(nameBytes.count))
                names.append(nameBytes)
            }
            out.append(names)
            return out
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    public enum LoadError: Error { case badFormat }

    public static func load(from url: URL) throws -> (TreeStore, Meta) {
        let data = try Data(contentsOf: url, options: .alwaysMapped)
        return try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> (TreeStore, Meta) in
            var pos = 0
            func get<T>(_: T.Type) throws -> T {
                guard pos + MemoryLayout<T>.size <= raw.count else { throw LoadError.badFormat }
                defer { pos += MemoryLayout<T>.size }
                return raw.loadUnaligned(fromByteOffset: pos, as: T.self)
            }
            func bytes(_ n: Int) throws -> String {
                guard pos + n <= raw.count else { throw LoadError.badFormat }
                defer { pos += n }
                return String(decoding: UnsafeRawBufferPointer(rebasing: raw[pos..<pos + n]), as: UTF8.self)
            }
            guard try get(UInt32.self) == magic, try get(UInt32.self) == version else { throw LoadError.badFormat }
            let count = Int(try get(UInt32.self))
            let eventID = try get(UInt64.self)
            let savedAt = Date(timeIntervalSince1970: try get(Double.self))
            let rootPath = try bytes(Int(try get(UInt32.self)))
            let uuid = try bytes(Int(try get(UInt32.self)))
            let recordsStart = pos
            let namesStart = recordsStart + count * recordSize
            guard count > 0, namesStart <= raw.count else { throw LoadError.badFormat }

            let store = TreeStore(rootPath: rootPath, rootName: "")
            store.lock.withLock {
                store.name = []; store.name.reserveCapacity(count)
                store.parent = []; store.parent.reserveCapacity(count)
                store.kind = []; store.state = []; store.ruleID = []; store.projectFlags = []
                store.ownBytes = []; store.totalBytes = []; store.ownFiles = []; store.fileCount = []; store.modified = []
                store.kind.reserveCapacity(count); store.state.reserveCapacity(count); store.ruleID.reserveCapacity(count)
                store.projectFlags.reserveCapacity(count); store.ownBytes.reserveCapacity(count)
                store.totalBytes.reserveCapacity(count); store.ownFiles.reserveCapacity(count)
                store.fileCount.reserveCapacity(count); store.modified.reserveCapacity(count)
                for i in 0..<count {
                    let b = recordsStart + i * recordSize
                    func at<T>(_ off: Int, _: T.Type) -> T { raw.loadUnaligned(fromByteOffset: b + off, as: T.self) }
                    store.parent.append(at(0, Int32.self))
                    store.kind.append(NodeKind(rawValue: at(4, UInt8.self)) ?? .dir)
                    store.state.append(ScanState(rawValue: at(5, UInt8.self)) ?? .complete)
                    store.ruleID.append(at(6, UInt16.self))
                    store.projectFlags.append(at(8, UInt8.self) != 0)
                    store.ownBytes.append(at(12, UInt64.self)); store.totalBytes.append(at(20, UInt64.self))
                    store.ownFiles.append(at(28, UInt32.self)); store.fileCount.append(at(32, UInt32.self))
                    store.modified.append(at(36, Int64.self))
                    let off = Int(at(44, UInt32.self)), len = Int(at(48, UInt32.self))
                    let start = namesStart + off
                    store.name.append(start + len <= raw.count
                        ? String(decoding: UnsafeRawBufferPointer(rebasing: raw[start..<start + len]), as: UTF8.self) : "?")
                }
                store.firstChild = [Int32](repeating: -1, count: count)
                store.nextSibling = [Int32](repeating: -1, count: count)
                store.pendingChildren = [Int32](repeating: 0, count: count)
                // Link in reverse so sibling lists keep the saved order.
                for i in stride(from: count - 1, through: 1, by: -1) {
                    let p = Int(store.parent[i])
                    guard p >= 0, p < count else { continue }
                    store.nextSibling[i] = store.firstChild[p]
                    store.firstChild[p] = Int32(i)
                }
                store.restrictedCount = store.kind.lazy.filter { $0 == .restricted }.count
            }
            return (store, Meta(eventID: eventID, volumeUUID: uuid, savedAt: savedAt, rootPath: rootPath, nodeCount: count))
        }
    }
}
