import Foundation

/// "Keep N GB free": decides what to free when the volume runs low.
/// Order: expired quarantine, then the oldest quarantine items, then tool-command caches (freed at once),
/// then Safe/Rebuildable folders into quarantine (freed after the retention window). Caution items are never automatic.
public struct KeepFreePolicy: Sendable {
    public enum Step: Sendable, CustomStringConvertible {
        case purgeQuarantine(QuarantineItem)
        case clean(CleanItem)

        public var bytes: UInt64 {
            switch self {
            case .purgeQuarantine(let q): q.bytes
            case .clean(let c): c.bytes
            }
        }
        /// Space returned now (quarantined items only free space after the retention window).
        public var freesNow: Bool {
            switch self {
            case .purgeQuarantine: true
            case .clean(let c): c.command != nil
            }
        }
        public var description: String {
            switch self {
            case .purgeQuarantine(let q): "delete from quarantine: \(q.originalPath) (\(q.bytes) bytes)"
            case .clean(let c): (c.command.map { "run: \($0.joined(separator: " "))" } ?? "quarantine: \(c.path)") + " (\(c.bytes) bytes)"
            }
        }
    }

    public var keepFreeBytes: UInt64
    public init(keepFreeBytes: UInt64) { self.keepFreeBytes = keepFreeBytes }

    public func plan(freeBytes: UInt64, quarantine: [QuarantineItem], store: TreeStore, rules: RuleSet) -> [Step] {
        guard freeBytes < keepFreeBytes else { return [] }
        var need = keepFreeBytes - freeBytes
        var steps: [Step] = []
        for q in quarantine.sorted(by: { $0.date < $1.date }) where need > 0 {
            steps.append(.purgeQuarantine(q))
            need -= min(need, q.bytes)
        }
        guard need > 0 else { return steps }
        let candidates = store.nodes { $0.ruleID != 0 }
            .compactMap { n -> CleanItem? in
                guard let r = rules.rule(id: n.ruleID), r.safety != .caution, let m = rules.match(store.path(of: n.id)) else { return nil }
                return CleanItem(match: m, bytes: n.totalBytes)
            }
            // Nested matches (node_modules inside node_modules): keep the outermost only.
            .sorted { $0.path < $1.path }
            .reduce(into: [CleanItem]()) { acc, c in if let last = acc.last, c.path.hasPrefix(last.path + "/") { return }; acc.append(c) }
            // Tool commands first (space back now), then safest, then biggest.
            .sorted { a, b in
                if (a.command != nil) != (b.command != nil) { return a.command != nil }
                if a.rule.safety != b.rule.safety { return a.rule.safety < b.rule.safety }
                return a.bytes > b.bytes
            }
        for c in candidates where need > 0 {
            steps.append(.clean(c))
            need -= min(need, c.bytes)
        }
        return steps
    }

    /// Applies a plan. In dry-run nothing is deleted, moved or run; the steps are only returned as log lines.
    public func apply(_ steps: [Step], cleaner: Cleaner, dryRun: Bool) -> [String] {
        steps.map { step in
            if dryRun { return "[dry-run] " + step.description }
            switch step {
            case .purgeQuarantine(let q):
                let holder = (q.storedPath as NSString).deletingLastPathComponent
                guard holder.hasPrefix(cleaner.quarantine.root.path + "/") else { return "skipped " + step.description }
                try? FileManager.default.removeItem(atPath: holder)
                try? FileManager.default.removeItem(atPath: cleaner.quarantine.manifestPath(q))
                return step.description
            case .clean(let c):
                let r = cleaner.execute([c])[0]
                return (r.error.map { "FAILED \($0): " } ?? "") + step.description
            }
        }
    }
}

/// Disk growth timeline: one JSON line per sample in `history.jsonl`.
/// ponytail: JSON lines instead of SQLite/GRDB; switch when queries beyond "all samples" are needed.
public struct HistorySample: Codable, Sendable, Identifiable {
    public var id: Date { date }
    public var date: Date
    public var usedBytes: UInt64
    public var freeBytes: UInt64
    /// Biggest top-level folders at that time.
    public var top: [String: UInt64]
}

public enum History {
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DiskLens/history.jsonl")
    }

    static func coder() -> (JSONEncoder, JSONDecoder) {
        let e = JSONEncoder(), d = JSONDecoder()
        e.dateEncodingStrategy = .iso8601; d.dateDecodingStrategy = .iso8601
        e.outputFormatting = .sortedKeys
        return (e, d)
    }

    public static func append(_ s: HistorySample, to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var line = try coder().0.encode(s)
        line.append(0x0A)
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            try h.seekToEnd()
            try h.write(contentsOf: line)
        } else {
            try line.write(to: url)
        }
    }

    public static func load(from url: URL = defaultURL) -> [HistorySample] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let d = coder().1
        return data.split(separator: 0x0A).compactMap { try? d.decode(HistorySample.self, from: Data($0)) }
    }

    /// Sample from a scanned store plus the volume's free space. Skips if the last sample is under `minInterval` old.
    public static func record(store: TreeStore, to url: URL = defaultURL, minInterval: TimeInterval = 3600) {
        if let last = load(from: url).last, Date().timeIntervalSince(last.date) < minInterval { return }
        let v = try? URL(fileURLWithPath: store.rootPath).resourceValues(forKeys: [.volumeAvailableCapacityKey])
        let free = UInt64(max(0, v?.volumeAvailableCapacity ?? 0))
        let top = Dictionary(store.children(of: .root).prefix(8).map { ($0.name, $0.totalBytes) }, uniquingKeysWith: { a, _ in a })
        try? append(HistorySample(date: Date(), usedBytes: store.node(.root).totalBytes, freeBytes: free, top: top), to: url)
    }
}
