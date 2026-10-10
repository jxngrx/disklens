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
    var category: Category
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
    var store: TreeStore { scanner.store }

    private(set) var current: NodeID = .root
    private(set) var backStack: [NodeID] = []
    private(set) var children: [NodeInfo] = []
    private(set) var boxes: [Box] = []
    private(set) var crumbs: [NodeInfo] = []
    private(set) var scanning = true
    private(set) var scanStarted = Date()
    private(set) var firstBoxesAt: TimeInterval?
    var canvasSize: CGSize = .zero { didSet { if canvasSize != oldValue { relayout() } } }
    var hovered: Box?
    var hoverPoint: CGPoint = .zero
    var zoom: Zoom?
    var smallerItems: [NodeInfo]?
    var trashCandidate: NodeInfo?
    var gitDates: [NodeID: String] = [:]

    private var seenVersion: UInt64 = .max
    private var order: [NodeID: Int] = [:]
    private var timer: Timer?

    init(rootPath: String) {
        scanner = DiskScanner(rootPath: rootPath, options: rootPath == "/" ? .startupVolume : ScanOptions())
    }

    /// `openPath` (launch argument `-openPath`) drills into that folder once it has been listed.
    func start(openPath: String? = nil) {
        let scanner = self.scanner
        scanStarted = Date()
        Task.detached(priority: .userInitiated) {
            await scanner.run()
            scanner.updateSystemOther()
            await MainActor.run {
                self.scanning = false
                if let p = openPath, let id = self.store.find(path: p) { self.jump(to: id) }
                self.refresh(force: true)
                // Screenshot helper: `-hoverName <child name>` shows that box's tooltip.
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
        // Keep box order stable while sizes are still growing so boxes don't jump around.
        if currentInfo.state != .complete, !order.isEmpty {
            kids.sort { a, b in
                switch (order[a.id], order[b.id]) {
                case let (x?, y?): x < y
                case (_?, nil): true
                case (nil, _?): false
                default: a.totalBytes > b.totalBytes
                }
            }
        }
        order = Dictionary(uniqueKeysWithValues: kids.enumerated().map { ($1.id, $0) })
        children = kids
        crumbs = store.ancestry(of: current).map { store.node($0) }
        if firstBoxesAt == nil, !kids.isEmpty { firstBoxesAt = Date().timeIntervalSince(scanStarted) }
        relayout()
    }

    func relayout() {
        let bounds = CGRect(origin: .zero, size: canvasSize)
        let kids = children.filter { $0.totalBytes > 0 }
        let rects = Squarify.layout(sizes: kids.map { Double($0.totalBytes) }, in: bounds)
        boxes = rects.map { r in
            guard let i = r.index else {
                return Box(node: nil, rect: r.rect, merged: r.merged.map { kids[$0] }, category: .file)
            }
            let n = kids[i]
            var box = Box(node: n, rect: r.rect, category: Category.of(n))
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
        if let h = hovered { hovered = boxes.first { $0.id == h.id } }
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
