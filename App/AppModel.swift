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

/// Main-window sections; everything except Files replaces the treemap instead of opening a popup.
enum AppTab: String, CaseIterable, Identifiable {
    case apps, files, developer, projects, mobile, quarantine, growth
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .apps: "square.grid.3x3"
        case .files: "square.grid.2x2"
        case .developer: "hammer"
        case .projects: "folder.badge.gearshape"
        case .mobile: "iphone.gen3"
        case .quarantine: "arrow.uturn.backward.circle"
        case .growth: "chart.xyaxis.line"
        }
    }
}

struct DevIndex: Sendable {
    var version: UInt64
    var tools: [DeveloperGroup]
    var projects: [ProjectInfo]
}

/// Zoom animation: content drawn so `bounds` maps to `from`, easing to identity.
struct Zoom {
    var from: CGRect
    var start: Date
    static let duration = 0.25
}

@MainActor @Observable
final class AppModel {
    let index: LiveIndex
    var scanner: DiskScanner { index.scanner }
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
    /// True when the last message reports a permission failure; the bar then offers Full Disk Access settings.
    var cleanNeedsPermission: Bool {
        guard let m = cleanMessage?.lowercased() else { return false }
        return m.contains("permission") || m.contains("not permitted")
    }
    var tab: AppTab = UserDefaults.standard.string(forKey: "scanRoot") == nil ? .apps : .files
    let appsState = AppsState()
    private(set) var devIndex: DevIndex?
    private(set) var devLoading = false
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
        // Fixture scans keep their index next to the fixtures instead of in Application Support.
        let indexURL: URL? = d.string(forKey: "indexDir").map { URL(fileURLWithPath: $0).appendingPathComponent("index.bin") }
            ?? (rootPath.contains("/disklens-fixtures/")
                ? Fixtures.base.appendingPathComponent(".indexes/\(LiveIndex.defaultSnapshotURL(for: rootPath).lastPathComponent)") : nil)
        index = LiveIndex(rootPath: rootPath, options: rootPath == "/" ? .startupVolume : ScanOptions(), hook: rules.listingHook(),
                          snapshotURL: indexURL, ignore: [qRoot.path])
    }

    /// "Index from 2 h ago · catching up…", "Live", "Scanning…", "Scan complete".
    var statusText: String {
        if refreshing { return "Refreshing…" }
        if let meta = index.loaded {
            let age = meta.savedAt.formatted(.relative(presentation: .named))
            return caughtUp ? "Live · index saved \(age)" : "Index from \(age) · catching up…"
        }
        if refreshing { return "Refreshing…" }
        return scanning ? "Scanning…" : "Scan complete"
    }
    private(set) var caughtUp = false
    private var lastSave = Date()

    /// `openPath` (launch argument `-openPath`) drills into that folder once it has been listed.
    func start(openPath: String? = nil) {
        let index = self.index
        scanStarted = Date()
        if index.loaded != nil { scanning = false }
        let quarantine = cleaner.quarantine
        Task.detached(priority: .utility) {
            // Items past the retention window are deleted for real (only inside the quarantine folder).
            quarantine.purge()
        }
        Task.detached(priority: .userInitiated) {
            // ponytail: no continuous FSEvents live-watch (it's what kept the whole-disk tree churning
            // in memory). Refresh instead happens on user actions (navigate/clean) or the manual button.
            await index.start(watch: false)
            // Growth timeline sample for the startup volume (at most hourly).
            if index.store.rootPath == "/" { History.record(store: index.store) }
            await MainActor.run {
                self.scanning = false
                self.caughtUp = true
                self.timer?.invalidate()
                self.timer = nil
                self.refreshDevIndex()
                if let p = openPath, let id = self.store.find(path: p) { self.jump(to: id) }
                self.refresh(force: true)
                // Screenshot helper: `-hoverName <child name>` shows that box's tooltip.
                if let c = UserDefaults.standard.string(forKey: "cleanName"), let n = self.children.first(where: { $0.name == c }) {
                    self.requestClean([n])
                }
                for t in AppTab.allCases where t != .files && UserDefaults.standard.bool(forKey: "show" + t.rawValue.capitalized) {
                    self.tab = t
                    if t == .quarantine { self.reloadQuarantine() }
                }
                if let h = UserDefaults.standard.string(forKey: "hoverName"), let b = self.boxes.first(where: { $0.node?.name == h }) {
                    self.hovered = b
                    self.hoverPoint = CGPoint(x: b.rect.midX, y: b.rect.midY)
                    if let n = b.node { self.loadGitDate(n) }
                }
            }
        }
        // ponytail: 10 Hz poll of the store version instead of change notifications from workers.
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated {
                self.refresh()
                if !self.caughtUp, self.index.caughtUp { self.caughtUp = true }
                // Keep the saved index fresh while live (cheap: a few hundred ms for a million nodes).
                if !self.scanning, Date().timeIntervalSince(self.lastSave) > 300 {
                    self.lastSave = Date()
                    let index = self.index
                    Task.detached(priority: .background) { try? index.save() }
                }
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            try? index.save()
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

    var refreshing = false

    /// Developer tab data. Built off the main thread and cached against `store.version`; cleaning patches it in
    /// place, so reopening the tab is instant and only a real tree change (rescan) triggers a rebuild.
    func refreshDevIndex() {
        let store = self.store, rules = self.rules
        guard !devLoading, devIndex?.version != store.version else { return }
        devLoading = true
        Task.detached(priority: .userInitiated) {
            let v = store.version
            let artifactID = rules.artifactRule.id
            let tagged = store.ruleTaggedNodes().filter { $0.ruleID != artifactID }
            let tools = Dictionary(grouping: tagged, by: \.ruleID).compactMap { id, nodes in
                rules.rule(id: id).map { DeveloperGroup(rule: $0, nodes: nodes.sorted { $0.totalBytes > $1.totalBytes }) }
            }.sorted { $0.total > $1.total }
            let projects = Projects.collect(store: store, rules: rules)
            await MainActor.run {
                self.devIndex = DevIndex(version: v, tools: tools, projects: projects)
                self.devLoading = false
                if v != store.version { self.refreshDevIndex() }
            }
        }
    }

    /// Deletion half of the index: drop cleaned nodes without rescanning the tree.
    private func dropFromDevIndex(_ ids: Set<NodeID>, allRemoved: Bool) {
        guard var d = devIndex, !ids.isEmpty else { return }
        d.tools = d.tools.compactMap { g in
            var g = g; g.nodes.removeAll { ids.contains($0.id) }
            return g.nodes.isEmpty ? nil : g
        }
        d.projects = d.projects.compactMap { p in
            var p = p; p.artifacts.removeAll { ids.contains($0.id) }
            return p.artifacts.isEmpty ? nil : p
        }
        if allRemoved { d.version = store.version }
        devIndex = d
    }

    /// Manual refresh button: relist every folder in scope in place (sizes stay on screen, only real differences
    /// apply). Files tab: the folder you are looking at and everything below it. Other tabs: every cleanable
    /// item and the folder holding it, so deletions and new caches show up. No FSEvents watching, so this is the
    /// only way outside changes get picked up.
    func manualRefresh() {
        if tab == .apps {
            appsState.load(self, force: true)
            if let a = appsState.selected { appsState.select(a, model: self) }
            return
        }
        guard !refreshing else { return }
        refreshing = true
        let (scanner, index, store) = (self.scanner, self.index, self.store)
        let roots: [NodeID]
        if tab == .files {
            roots = [current]
        } else {
            let tagged = store.ruleTaggedNodes().map(\.id)
            roots = tagged + tagged.compactMap { store.parent(of: $0) }
        }
        let ownsTimer = timer == nil
        if ownsTimer { timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in MainActor.assumeIsolated { self.refresh() } } }
        Task.detached(priority: .userInitiated) {
            var seen = Set<Int32>()
            var ids: [NodeID] = []
            for r in roots { for d in store.directories(in: r) where seen.insert(d.raw).inserted { ids.append(d) } }
            await scanner.rescan(ids)
            scanner.updateSystemOther()
            try? index.save()
            await MainActor.run {
                if ownsTimer { self.timer?.invalidate(); self.timer = nil }
                self.refreshing = false
                self.refresh(force: true)
                self.refreshDevIndex()
                if self.tab == .quarantine { self.reloadQuarantine() }
            }
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
            NSLog("DiskLens first boxes after %.3f s (%d boxes, %.3f s since process start, from snapshot: %@)",
                  firstBoxesAt!, kids.count, Date().timeIntervalSince(processStart), index.loaded == nil ? "no" : "yes")
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

    var sheetOpen: Bool {
        cleanPlan != nil || smallerItems != nil || trashCandidate != nil
    }

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
        var plan: [CleanItem] = []
        var gone = Set<NodeID>()
        var skipped: [String] = []
        for n in nodes {
            let p = store.path(of: n.id)
            if p.isEmpty || !FileManager.default.fileExists(atPath: p) { gone.insert(n.id); continue }
            if let item = (try? cleaner.plan([(p, n.totalBytes)]))?.first { plan.append(item) } else { skipped.append(n.name) }
        }
        // Items that vanished outside the app (or were already cleaned): drop them from the tree and Developer index.
        for id in gone { store.remove(id) }
        if !gone.isEmpty { dropFromDevIndex(gone, allRemoved: false); refresh(force: true) }
        var notes: [String] = []
        if !gone.isEmpty { notes.append("\(gone.count) already gone") }
        if !skipped.isEmpty { notes.append("skipped \(skipped.count) not cleanable (\(skipped.prefix(3).joined(separator: ", "))\(skipped.count > 3 ? "…" : ""))") }
        guard !plan.isEmpty else {
            cleanMessage = notes.isEmpty ? "Nothing to clean." : "Nothing to clean: " + notes.joined(separator: ", ") + "."
            return
        }
        cleanRunningTools = RunningTools.running(Array(Set(plan.flatMap { $0.rule.runningTools ?? [] })).sorted())
        cleanMessage = notes.isEmpty ? nil : notes.joined(separator: ", ").prefix(1).uppercased() + notes.joined(separator: ", ").dropFirst() + "."
        cleanPlan = plan
    }

    /// Runs the plan, then removes cleaned nodes from the tree right away (FSEvents confirms later).
    func performClean() {
        guard let plan = cleanPlan else { return }
        let results = cleaner.execute(plan)
        var freed: UInt64 = 0
        var failed: [String] = []
        var removed = Set<NodeID>()
        for r in results {
            if let e = r.error { failed.append("\((r.item.path as NSString).lastPathComponent): \(e.message)"); continue }
            freed += r.item.bytes
            // Tool commands clean inside the folder; the folder itself may stay, so only deleted items vanish now.
            if r.removed, let id = store.find(path: r.item.path) { store.remove(id); removed.insert(id) }
        }
        // Tool-command cleans change sizes without removing nodes, so the index only counts as current if every item was removed.
        dropFromDevIndex(removed, allRemoved: removed.count == results.count)
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

    /// Pro: reinstall a cleaned project's dependencies from its lockfile.
    func reinstall(project: String) {
        guard let cmd = Projects.restoreCommand(project) else { return }
        let r = cleaner.runner.run(cmd, in: project)
        cleanMessage = (r.ok ? "Ran " : "Failed: ") + cmd.joined(separator: " ") + " in " + (project as NSString).lastPathComponent
            + (cleaner.runner.dryRun ? " (dry run)" : "")
    }

    func emptyQuarantine() {
        cleaner.quarantine.purge(everything: true)
        reloadQuarantine()
    }

    func moveToTrash(_ n: NodeInfo) {
        let url = URL(fileURLWithPath: path(n))
        do {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
            store.remove(n.id)
            dropFromDevIndex([n.id], allRemoved: false)
            refresh(force: true)
            cleanMessage = "Moved “\(n.name)” to the Trash."
        } catch {
            cleanMessage = "Could not move “\(n.name)” to the Trash: \(error.localizedDescription)"
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

/// Process start time (for launch-to-first-boxes measurements).
let processStart: Date = {
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.size
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    sysctl(&mib, 4, &info, &size, nil, 0)
    let t = info.kp_proc.p_starttime
    return Date(timeIntervalSince1970: Double(t.tv_sec) + Double(t.tv_usec) / 1e6)
}()
