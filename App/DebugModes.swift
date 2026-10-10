import AppKit
import DiskLensCore
import SwiftUI

/// `DiskLens -benchmark`: renders 5,000 boxes through the real Canvas renderer and prints frame times.
@MainActor
enum Benchmark {
    static func run() {
        let size = CGSize(width: 1600, height: 1000)
        let sizes = (0..<5000).map { Double(5000 - $0) * 1000 }
        let clock = ContinuousClock()
        var rects: [TreemapRect] = []
        let layoutTime = clock.measure {
            rects = Squarify.layout(sizes: sizes, in: CGRect(origin: .zero, size: size), minFraction: 0, minSide: 0)
        }
        let cats = Category.allCases
        var boxes: [Box] = []
        for (i, r) in rects.enumerated() {
            let n = NodeInfo(id: NodeID(Int32(i + 1)), name: "item\(i)", kind: .dir, totalBytes: UInt64(sizes[i]))
            boxes.append(Box(node: n, rect: r.rect, category: cats[i % cats.count]))
        }
        let frames = 120
        var worst = Duration.zero
        let total = clock.measure {
            for f in 0..<frames {
                // New renderer and hover target each frame so nothing is cached.
                let view = Canvas { ctx, s in
                    TreemapRenderer.draw(&ctx, size: s, boxes: boxes, hovered: Int32(f + 1), zoom: nil, now: Date())
                }.frame(width: size.width, height: size.height)
                let t = clock.measure { _ = ImageRenderer(content: view).cgImage }
                worst = max(worst, t)
            }
        }
        let totalMs = Double(total.components.seconds) * 1000 + Double(total.components.attoseconds) / 1e15
        let avgMs = totalMs / Double(frames)
        print(String(format: "BENCHMARK boxes=%d layout=%@ avgFrame=%.2fms fps=%.1f worst=%@",
                     boxes.count, "\(layoutTime)", avgMs, 1000 / avgMs, "\(worst)"))
        fflush(stdout)
        exit(0)
    }
}

/// `DiskLens -selftest -scanRoot <fixture>`: drives the same model calls the clicks and keys use
/// (hit test → activate, breadcrumb jump, back, parent) and exits 0 on success.
/// Fallback for machines where XCUITest cannot enable automation mode.
@MainActor
enum SelfTest {
    static func run(_ model: AppModel) {
        model.canvasSize = CGSize(width: 1000, height: 700)
        Task { @MainActor in
            while model.scanning { try? await Task.sleep(for: .milliseconds(50)) }
            var failures: [String] = []
            @MainActor func check(_ ok: Bool, _ what: String) { print(ok ? "PASS" : "FAIL", what); if !ok { failures.append(what) } }
            @MainActor func crumbNames() -> [String] { model.crumbs.map(\.name) }

            // Every box's centre opens that exact folder.
            for b in model.boxes where b.node?.isDirectory == true {
                model.jump(to: .root)
                guard let hit = model.box(at: CGPoint(x: b.rect.midX, y: b.rect.midY)) else { check(false, "hit \(b.node!.name)"); continue }
                model.activate(hit)
                check(crumbNames().last == b.node!.name, "click box \(b.node!.name) opens it")
            }
            model.jump(to: .root)
            let rootName = crumbNames().first ?? ""
            // Drill three levels through the biggest folder each time.
            var path: [String] = []
            for _ in 0..<3 {
                guard let b = model.boxes.first(where: { $0.node?.isDirectory == true }) else { break }
                model.activate(model.box(at: CGPoint(x: b.rect.midX, y: b.rect.midY))!)
                path.append(b.node!.name)
            }
            check(crumbNames() == [rootName] + path, "drill-down breadcrumb \(crumbNames())")
            check(model.zoom != nil, "zoom animation started")
            if path.count >= 2 {
                model.jump(to: model.crumbs[1].id)
                check(crumbNames() == [rootName, path[0]], "breadcrumb jump")
                model.back()
                check(crumbNames() == [rootName] + path, "back returns")
                model.up()
                check(crumbNames() == [rootName] + path.dropLast(), "parent (⌘↑)")
            }
            // Clean + restore flow, only on fixtures with a fixture quarantine.
            let root = model.store.rootPath
            if root.contains("/disklens-fixtures/"), model.cleaner.quarantine.root.path.contains("/disklens-fixtures/"),
               model.cleaner.runner.dryRun,
               let id = model.store.find(path: root + "/Projects/web-shop/node_modules") {
                let n = model.store.node(id)
                check(n.ruleID == model.rules.artifactRule.id, "node_modules tagged as artifact")
                let before = model.store.node(.root).totalBytes
                model.requestClean([n])
                check(model.cleanPlan?.count == 1 && model.cleanPlan?.first?.rule.quarantinable == true, "confirm sheet plan")
                // Something outside the rules is refused.
                model.cleanPlan = nil
                model.requestClean([model.store.node(model.store.find(path: root + "/Projects/web-shop")!)])
                check(model.cleanPlan == nil && model.cleanMessage?.hasPrefix("Not cleanable") == true, "project folder refused")
                model.requestClean([n])
                model.performClean()
                check(!FileManager.default.fileExists(atPath: root + "/Projects/web-shop/node_modules"), "node_modules moved out")
                check(model.store.node(.root).totalBytes == before - n.totalBytes, "tree subtracted instantly")
                check(model.quarantineItems.count == 1, "one quarantine item")
                if let item = model.quarantineItems.first { model.restore(item) }
                check(FileManager.default.fileExists(atPath: root + "/Projects/web-shop/node_modules/react/index.js"), "restored on disk")
                for _ in 0..<40 where model.store.find(path: root + "/Projects/web-shop/node_modules") == nil {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                try? await Task.sleep(for: .milliseconds(200))
                check(model.store.node(.root).totalBytes == before, "tree size back after restore rescan")
            }
            print(failures.isEmpty ? "SELFTEST OK" : "SELFTEST FAILED \(failures.count)")
            fflush(stdout)
            exit(failures.isEmpty ? 0 : 1)
        }
    }
}
