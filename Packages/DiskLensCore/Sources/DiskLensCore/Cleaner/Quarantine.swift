import Darwin
import Foundation

public struct QuarantineItem: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var originalPath: String
    public var storedPath: String
    public var bytes: UInt64
    public var date: Date
    public var ruleID: UInt16
}

/// "Clean" renames items into `<root>/<yyyy-MM-dd>/<uuid>/<name>` on the same volume, so it is instant and
/// reversible. A JSON manifest next to each item records where it came from.
public final class Quarantine: Sendable {
    public let root: URL
    public let retentionDays: Int

    public static var defaultRoot: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".disklens-quarantine")
    }

    public init(root: URL = Quarantine.defaultRoot, retentionDays: Int = 7) {
        self.root = root
        self.retentionDays = retentionDays
    }

    static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    public func add(path: String, bytes: UInt64, ruleID: UInt16, now: Date = Date()) throws -> QuarantineItem {
        let id = UUID()
        let dayDir = root.appendingPathComponent(Self.dayFormat.string(from: now))
        let holder = dayDir.appendingPathComponent(id.uuidString)
        try FileManager.default.createDirectory(at: holder, withIntermediateDirectories: true)
        var a = stat(), b = stat()
        guard lstat(path, &a) == 0, lstat(holder.path, &b) == 0, a.st_dev == b.st_dev else {
            try? FileManager.default.removeItem(at: holder)
            throw CleanError.crossVolume(path)
        }
        let stored = holder.appendingPathComponent((path as NSString).lastPathComponent)
        guard rename(path, stored.path) == 0 else {
            try? FileManager.default.removeItem(at: holder)
            throw CleanError.notCleanable(path)
        }
        let item = QuarantineItem(id: id, originalPath: path, storedPath: stored.path, bytes: bytes, date: now, ruleID: ruleID)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        try enc.encode(item).write(to: dayDir.appendingPathComponent(id.uuidString + ".json"))
        return item
    }

    public func items() -> [QuarantineItem] {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let days = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return days.flatMap { day in
            ((try? FileManager.default.contentsOfDirectory(at: day, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "json" }
                .compactMap { try? dec.decode(QuarantineItem.self, from: Data(contentsOf: $0)) }
        }.sorted { $0.date > $1.date }
    }

    public func restore(_ item: QuarantineItem) throws {
        guard !FileManager.default.fileExists(atPath: item.originalPath) else { throw CleanError.restoreTargetExists(item.originalPath) }
        try FileManager.default.createDirectory(atPath: (item.originalPath as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        guard rename(item.storedPath, item.originalPath) == 0 else { throw CleanError.notCleanable(item.storedPath) }
        try? FileManager.default.removeItem(atPath: (item.storedPath as NSString).deletingLastPathComponent)
        try? FileManager.default.removeItem(atPath: manifestPath(item))
    }

    /// Deletes for real the items older than the retention window (or all with `everything`). Returns them.
    @discardableResult
    public func purge(now: Date = Date(), everything: Bool = false) -> [QuarantineItem] {
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        let old = items().filter { everything || $0.date < cutoff }
        for item in old {
            let holder = (item.storedPath as NSString).deletingLastPathComponent
            // Only ever delete inside the quarantine root.
            guard holder.hasPrefix(root.path + "/") else { continue }
            try? FileManager.default.removeItem(atPath: holder)
            try? FileManager.default.removeItem(atPath: manifestPath(item))
        }
        // Drop empty day folders.
        for day in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            if (try? FileManager.default.contentsOfDirectory(atPath: day.path))?.isEmpty == true { try? FileManager.default.removeItem(at: day) }
        }
        return old
    }

    public var totalBytes: UInt64 { items().reduce(0) { $0 + $1.bytes } }

    func manifestPath(_ item: QuarantineItem) -> String {
        (((item.storedPath as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent as NSString)
            .appendingPathComponent(item.id.uuidString + ".json")
    }
}
