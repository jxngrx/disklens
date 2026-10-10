import AppKit
import DiskLensCore
import Observation
import SwiftUI

/// One box on screen. `node == nil` is the merged "N smaller items" box.
struct Box: Identifiable {
    var id: Int32 { node?.id.raw ?? -1 }
    var node: NodeInfo?
    var rect: CGRect
    var merged: [NodeInfo] = []
    var preview: [(rect: CGRect, category: Category)] = []
    /// Rect in the previous layout, so size changes animate.
    var from: CGRect?
    var category: Category
    var rule: Rule?
}

/// Zoom animation: content drawn so `bounds` maps to `from`, easing to identity.
struct Zoom {
    var from: CGRect
    var start: Date
    static let duration = 0.25
}

@MainActor @Observable
final class AppModel {
    let scanner: DiskScanner
    let rules: RuleSet
    let cleaner: Cleaner
    var store: TreeStore { scanner.store }

    private(set) var current: NodeID = .root
    private(set) var backStack: [NodeID] = []
    private(set) var children: [NodeInfo] = []
    private(set) var boxes: [Box] = []
    private(set) var crumbs: [NodeInfo] = []
    private(set) var scanning = true
    private(set) var scanStarted = Date()
    private(set) var firstBoxesAt: TimeInterval?
    private(set) var layoutAt = Date.distantPast
    private(set) var restrictedCount = 0
    /// True while boxes ease between two layouts.
    var resizing = false
    var canvasSize: CGSize = .zero { didSet { if canvasSize != oldValue { relayout() } } }
    var hovered: Box?
    var hoverPoint: CGPoint = .zero
    var zoom: Zoom?
    var smallerItems: [NodeInfo]?
    var trashCandidate: NodeInfo?
    var gitDates: [NodeID: String] = [:]
    // Cleaning
    var cleanPlan: [CleanItem]?
    var cleanRunningTools: [String] = []
    var cleanMessage: String?
    var showProjects = false
    var showQuarantine = false
    var quarantineItems: [QuarantineItem] = []

    private var seenVersion: UInt64 = .max
    private var order: [NodeID: Int] = [:]
    private var timer: Timer?

    /// Launch arguments for tests and screenshots: `-rulesHome` points `~` in rules at a fixture,
    /// `-quarantineRoot` moves the quarantine, `-dryRun YES` only logs tool commands.
    init(rootPath: String) {
        let d = UserDefaults.standard
        let home = d.string(forKey: "rulesHome") ?? NSHomeDirectory()
        rules = (try? RuleSet(home: home)) ?? .default
        let qRoot = d.string(forKey: "quarantineRoot").map { URL(fileURLWithPath: $0) } ?? Quarantine.defaultRoot
        let days = d.integer(forKey: "retentionDays")
        cleaner = Cleaner(rules: rules, quarantine: Quarantine(root: qRoot, retentionDays: days > 0 ? days : 7),
                          runner: CommandRunner(dryRun: d.bool(forKey: "dryRun") || ProcessInfo.processInfo.environment["DISKLENS_DRY_RUN"] == "1"))
        scanner = DiskScanner(rootPath: rootPath, options: rootPath == "/" ? .startupVolume : ScanOptions(), hook: rules.listingHook())
    }

    /// `openPath` (launch argument `-openPath`) drills into that folder once it has been listed.
    func start(openPath: String? = nil) {
        let scanner = self.scanner
        scanStarted = Date()
        let quarantine = cleaner.quarantine
        Task.detached(priority: .utility) {
            // Items past the retention window are deleted for real (only inside the quarantine folder).
            quarantine.purge()
        }
        Task.detached(priority: .userInitiated) {
            await scanner.run()
            scanner.updateSystemOther()
            await MainActor.run {
                self.scanning = false
                if let p = openPath, let id = self.store.find(path: p) { self.jump(to: id) }
                self.refresh(force: true)
                // Screenshot helper: `-hoverName <child name>` shows that box's tooltip.
                if let c = UserDefaults.standard.string(forKey: "cleanName"), let n = self.children.first(where: { $0.name == c }) {
                    self.requestClean([n])
                }
                if UserDefaults.standard.bool(forKey: "showProjects") { self.showProjects = true }
                if UserDefaults.standard.bool(forKey: "showQuarantine") { self.reloadQuarantine(); self.showQuarantine = true }
                if let h = UserDefaults.standard.string(forKey: "hoverName"), let b = self.boxes.first(where: { $0.node?.name == h }) {
                    self.hovered = b
                    self.hoverPoint = CGPoint(x: b.rect.midX, y: b.rect.midY)
                    if let n = b.node { self.loadGitDate(n) }
                }
            }
        }
        // ponytail: 10 Hz poll of the store version instead of change notifications from workers.
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated { self.refresh() }
        }
    }

    // MARK: - Navigation

    func activate(_ box: Box, rect: CGRect? = nil) {
        if let n = box.node {
            if n.isDirectory { open(n.id, from: rect ?? box.rect) }
        } else {
            smallerItems = box.merged
        }
    }

    func open(_ id: NodeID, from rect: CGRect? = nil) {
        guard id != current else { return }
        let n = store.node(id)
        guard n.isDirectory else { return }
        backStack.append(current)
        navigate(to: id, zoomFrom: rect)
    }

    func back() {
        guard let prev = backStack.popLast() else { return }
        navigate(to: prev, zoomFrom: nil, previous: current)
    }

    func up() {
        guard let p = store.parent(of: current) else { return }
        backStack.append(current)
        navigate(to: p, zoomFrom: nil, previous: current)
    }

    func jump(to id: NodeID) {
        guard id != current else { return }
        backStack.append(current)
        navigate(to: id, zoomFrom: nil, previous: current)
    }

    private func navigate(to id: NodeID, zoomFrom: CGRect?, previous: NodeID? = nil) {
        current = id
        order = [:]
        hovered = nil
        let scanner = self.scanner
        Task { await scanner.setFocus(id) }
        refresh(force: true)
        let bounds = CGRect(origin: .zero, size: canvasSize)
        if let r = zoomFrom {
            zoom = Zoom(from: r, start: Date())
        } else if let prev = previous, let child = boxes.first(where: { b in b.node.map { store.isDescendant(prev, of: $0.id) } ?? false }),
                  child.rect.width > 0, child.rect.height > 0 {
            // Zooming out: start with the previous folder filling the screen.
            let sx = bounds.width / child.rect.width, sy = bounds.height / child.rect.height
            zoom = Zoom(from: CGRect(x: -child.rect.minX * sx, y: -child.rect.minY * sy,
                                     width: bounds.width * sx, height: bounds.height * sy), start: Date())
        }
    }

    // MARK: - Data

    func refresh(force: Bool = false) {
        let v = store.version
        guard force || v != seenVersion else { return }
        seenVersion = v
        var kids = store.children(of: current)
        let currentInfo = store.node(current)
        // Keep box order stable while sizes are still growing so boxes don't jump around: items only
        // swap when one grows past the other by a size bucket (~41%), otherwise the previous order wins.
        if currentInfo.state != .complete, !order.isEmpty {
            func bucket(_ n: NodeInfo) -> Int { n.totalBytes == 0 ? -1 : Int(log2(Double(n.totalBytes)) * 2) }
            kids.sort { a, b in
                let (ba, bb) = (bucket(a), bucket(b))
                if ba != bb { return ba > bb }
                switch (order[a.id], order[b.id]) {
                case let (x?, y?): return x < y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return a.totalBytes > b.totalBytes
                }
            }
        }
        order = Dictionary(uniqueKeysWithValues: kids.enumerated().map { ($1.id, $0) })
        children = kids
        crumbs = store.ancestry(of: current).map { store.node($0) }
        if firstBoxesAt == nil, !kids.isEmpty {
            firstBoxesAt = Date().timeIntervalSince(scanStarted)
            NSLog("DiskLens first boxes after %.3f s (%d boxes)", firstBoxesAt!, kids.count)
        }
        restrictedCount = store.restrictedCount
        relayout(animated: true)
    }

    func relayout(animated: Bool = false) {
        let bounds = CGRect(origin: .zero, size: canvasSize)
        let old = animated && zoom == nil ? Dictionary(boxes.map { ($0.id, $0.rect) }, uniquingKeysWith: { a, _ in a }) : [:]
        let kids = children.filter { $0.totalBytes > 0 }
        let rects = Squarify.layout(sizes: kids.map { Double($0.totalBytes) }, in: bounds)
        boxes = rects.map { r in
            guard let i = r.index else {
                return Box(node: nil, rect: r.rect, merged: r.merged.map { kids[$0] }, category: .file)
            }
            let n = kids[i]
            let rule = n.ruleID == 0 ? nil : rules.rule(id: n.ruleID)
            var box = Box(node: n, rect: r.rect, category: Category.of(n, ruleEcosystem: rule?.ecosystem), rule: rule)
            // Faint second level: the folder's biggest children, once known.
            if n.isDirectory, r.rect.width > 80, r.rect.height > 90 {
                // Below the two-line label.
                let inside = CGRect(x: r.rect.minX + 5, y: r.rect.minY + 40, width: r.rect.width - 10, height: r.rect.height - 45)
                let sub = store.children(of: n.id).prefix(12).filter { $0.totalBytes > 0 }
                box.preview = Squarify.layout(sizes: sub.map { Double($0.totalBytes) }, in: inside, minSide: 8)
                    .compactMap { p in p.index.map { (p.rect, Category.of(sub[$0])) } }
            }
            return box
        }
        for i in boxes.indices { if let r = old[boxes[i].id], r != boxes[i].rect { boxes[i].from = r; resizing = true } }
        layoutAt = Date()
        if let h = hovered { hovered = boxes.first { $0.id == h.id } }
    }

    var sheetOpen: Bool { cleanPlan != nil || showProjects || showQuarantine || smallerItems != nil || trashCandidate != nil }

    func box(at p: CGPoint) -> Box? { boxes.first { $0.rect.contains(p) } }

    func path(_ n: NodeInfo) -> String { store.path(of: n.id) }

    // MARK: - Hover extras

    func loadGitDate(_ n: NodeInfo) {
        guard n.isDirectory, gitDates[n.id] == nil else { return }
        let path = store.path(of: n.id)
        guard FileManager.default.fileExists(atPath: path + "/.git") else { return }
        gitDates[n.id] = "…"
        Task.detached {
            let date = Shell.output("/usr/bin/git", ["-C", path, "log", "-1", "--format=%cr"])?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run { self.gitDates[n.id] = date ?? "" }
        }
    }

    // MARK: - Context actions

    func reveal(_ n: NodeInfo) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path(n))]) }

    func quickLook(_ n: NodeInfo) {
        // ponytail: qlmanage instead of a QLPreviewPanel controller; swap if it needs to feel native.
        _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/qlmanage"), arguments: ["-p", path(n)])
    }

    func copyPath(_ n: NodeInfo) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path(n), forType: .string)
    }

    // MARK: - Cleaning

    func requestClean(_ nodes: [NodeInfo]) {
        do {
            let plan = try cleaner.plan(nodes.map { (store.path(of: $0.id), $0.totalBytes) })
            cleanRunningTools = RunningTools.running(Array(Set(plan.flatMap { $0.rule.runningTools ?? [] })).sorted())
            cleanMessage = nil
            cleanPlan = plan
        } catch {
            cleanMessage = "Not cleanable: \(error)"
        }
    }

    /// Runs the plan, then removes cleaned nodes from the tree right away (FSEvents confirms later).
    func performClean() {
        guard let plan = cleanPlan else { return }
        let results = cleaner.execute(plan)
        var freed: UInt64 = 0
        var failed: [String] = []
        for r in results {
            if let e = r.error { failed.append("\((r.item.path as NSString).lastPathComponent): \(e)"); continue }
            freed += r.item.bytes
            // Tool commands clean inside the folder; the folder itself may stay, so only quarantined items vanish now.
            if r.quarantined != nil, let id = store.find(path: r.item.path) { store.remove(id) }
        }
        cleanPlan = nil
        cleanMessage = failed.isEmpty ? "Cleaned \(formatBytes(freed))." : "Cleaned \(formatBytes(freed)). Failed: " + failed.joined(separator: "; ")
        refresh(force: true)
        reloadQuarantine()
    }

    func quitTool(_ name: String) {
        if let cmd = RunningTools.stopCommands[name] {
            cleaner.runner.run(cmd)
        } else {
            let ids = ["Xcode": "com.apple.dt.Xcode", "Simulator": "com.apple.iphonesimulator", "Docker": "com.docker.docker"]
            if let id = ids[name] { NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { $0.terminate() } }
        }
        cleanRunningTools.removeAll { $0 == name }
    }

    func reloadQuarantine() { quarantineItems = cleaner.quarantine.items() }

    func restore(_ item: QuarantineItem) {
        do {
            try cleaner.quarantine.restore(item)
            cleanMessage = "Restored \((item.originalPath as NSString).lastPathComponent)."
            // Rescan the parent so the box comes back.
            let parent = (item.originalPath as NSString).deletingLastPathComponent
            if let id = store.find(path: parent) {
                let scanner = self.scanner
                Task.detached { await scanner.rescan([id]); await MainActor.run { self.refresh(force: true) } }
            }
        } catch {
            cleanMessage = "Restore failed: \(error)"
        }
        reloadQuarantine()
    }

    func emptyQuarantine() {
        cleaner.quarantine.purge(everything: true)
        reloadQuarantine()
    }

    func moveToTrash(_ n: NodeInfo) {
        let url = URL(fileURLWithPath: path(n))
        if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil {
            store.remove(n.id)
            refresh(force: true)
        }
    }
}

enum Shell {
    /// Runs a tool and returns stdout, or nil on failure. Read-only uses only.
    static func output(_ tool: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
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
