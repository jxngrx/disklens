import CoreServices
import Foundation
import Testing
@testable import DiskLensCore

func waitUntil(_ timeout: Double, _ cond: () -> Bool) async -> Double? {
    let start = Date()
    while Date().timeIntervalSince(start) < timeout {
        if cond() { return Date().timeIntervalSince(start) }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return nil
}

@Suite(.serialized) struct SnapshotTests {
    @Test func roundTripKeepsTree() async throws {
        let f = try FakeHome()
        defer { Fixtures.remove(f.root) }
        let scanner = DiskScanner(rootPath: f.home, hook: f.rules.listingHook())
        await scanner.run()
        // A removed node must not come back (compaction).
        scanner.store.remove(scanner.store.find(path: f.p("Documents"))!)
        let url = f.root.appendingPathComponent("index.bin")
        try Snapshot.save(scanner.store, to: url, eventID: 42, volumeUUID: "uuid")
        let (loaded, meta) = try Snapshot.load(from: url)
        #expect(meta.eventID == 42 && meta.volumeUUID == "uuid" && meta.rootPath == f.home)
        #expect(loaded.node(.root).totalBytes == scanner.store.node(.root).totalBytes)
        #expect(loaded.node(.root).fileCount == scanner.store.node(.root).fileCount)
        #expect(loaded.find(path: f.p("Documents")) == nil)
        func summary(_ s: TreeStore) -> [String] {
            s.nodes { _ in true }.map { "\(s.path(of: $0.id))|\($0.totalBytes)|\($0.kind)|\($0.ruleID)|\(s.isProject($0.id))" }.sorted()
        }
        #expect(summary(loaded) == summary(scanner.store))
        #expect(loaded.children(of: .root).map(\.name) == scanner.store.children(of: .root).map(\.name))
    }

    @Test func coalescerMergesAndIgnores() {
        let file = UInt32(kFSEventStreamEventFlagItemIsFile), dir = UInt32(kFSEventStreamEventFlagItemIsDir)
        let must = UInt32(kFSEventStreamEventFlagMustScanSubDirs)
        var changes = [
            FileChange(path: "/r/a/x.txt", flags: file, id: 1), FileChange(path: "/r/a/y.txt", flags: file, id: 2),
            FileChange(path: "/r/b/new", flags: dir, id: 3), FileChange(path: "/r/q/item", flags: dir, id: 4),
            FileChange(path: "/r/deep", flags: must, id: 5), FileChange(path: "/r/deep/z/w.txt", flags: file, id: 6),
        ]
        var (dirs, subtrees) = ChangeCoalescer.coalesce(changes, ignore: ["/r/q"])
        #expect(dirs == ["/r/a", "/r/b", "/r/b/new"])
        #expect(subtrees == ["/r/deep"])
        // Many sibling folders changed: rescan the parent once.
        changes = (0..<12).map { FileChange(path: "/r/p/c\($0)/f", flags: file, id: UInt64($0)) }
        (dirs, subtrees) = ChangeCoalescer.coalesce(changes, ignore: [])
        #expect(subtrees == ["/r/p"] && dirs.isEmpty)
    }

    /// Phase 5 check (core half): a saved index of the real disk loads in under 1 s.
    @Test func loadOfLargeIndexIsFast() throws {
        // Synthetic 1 M node tree: 1000 dirs × 1000 files.
        let store = TreeStore(rootPath: "/synthetic", rootName: "synthetic")
        var top = Listing()
        top.dirs = (0..<1000).map { ("dir\($0)", NodeKind.dir, Int64(0)) }
        let dirs = store.apply(top, to: .root)
        for d in dirs {
            var l = Listing()
            l.files = (0..<1000).map { ("file-with-a-longish-name-\($0).bin", UInt64(1 << 20), Int64(0)) }
            l.ownBytes = 1000 << 20
            l.ownFiles = 1000
            _ = store.apply(l, to: d)
        }
        #expect(store.count > 1_000_000)
        let url = Fixtures.base.appendingPathComponent("big-index-\(UUID().uuidString.prefix(6)).bin")
        defer { try? FileManager.default.removeItem(at: url) }
        let clock = ContinuousClock()
        let saveT = clock.measure { try! Snapshot.save(store, to: url, eventID: 1, volumeUUID: "") }
        var loaded: TreeStore?
        let loadT = clock.measure { loaded = try! Snapshot.load(from: url).0 }
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as! NSNumber).intValue
        print("snapshot 1M nodes: save \(saveT), load \(loadT), \(size / 1_000_000) MB")
        #expect(loaded!.node(.root).totalBytes == store.node(.root).totalBytes)
        // Debug builds are ~3x slower than release; the release number is what the target is about.
        #expect(loadT < .seconds(_isDebugAssertConfiguration() ? 3 : 1))
    }
}

@Suite(.serialized) struct LiveUpdateTests {
    /// Phase 5 check: creating a 1 GB file in a watched folder updates its box within 3 s.
    @Test func oneGigabyteFileShowsUpWithin3s() async throws {
        let root = try Fixtures.makeRoot("live")
        defer { Fixtures.remove(root) }
        try Fixtures.writeFile(root.appendingPathComponent("watched/seed.bin"), bytes: 1 << 20)
        let index = LiveIndex(rootPath: root.path, options: ScanOptions(), hook: nil,
                              snapshotURL: root.appendingPathComponent("index/index.bin"))
        await index.start()
        let before = index.store.node(.root).totalBytes
        try await Task.sleep(for: .milliseconds(300))
        let created = Date()
        try Fixtures.writeFile(root.appendingPathComponent("watched/big.bin"), bytes: 1 << 30)
        let writeTime = Date().timeIntervalSince(created)
        let t = await waitUntil(10) { index.store.node(.root).totalBytes >= before + (1 << 30) }
        print("1 GB write took \(String(format: "%.2f", writeTime)) s; tree updated \(t.map { String(format: "%.2f", $0) } ?? "never") s after the write finished")
        #expect(t != nil)
        if let t { #expect(t < 3) }
        let watched = index.store.find(path: root.path + "/watched")!
        #expect(index.store.node(watched).totalBytes >= 1 << 30)
        // Deleting it shrinks the box again.
        try FileManager.default.removeItem(at: root.appendingPathComponent("watched/big.bin"))
        #expect(await waitUntil(10) { index.store.node(.root).totalBytes < before + (1 << 20) } != nil)
        index.stop()
    }

    @Test func catchUpFromSnapshot() async throws {
        let root = try Fixtures.makeRoot("catchup")
        defer { Fixtures.remove(root) }
        try Fixtures.makeTree(at: root, dirs: 30, filesPerDir: 3)
        let url = root.appendingPathComponent(".index/index.bin")
        let first = LiveIndex(rootPath: root.path, options: ScanOptions(), hook: nil, snapshotURL: url)
        await first.start(watch: false)
        #expect(first.loaded == nil)
        // Changes while "the app is closed".
        try Fixtures.writeFile(root.appendingPathComponent("dir3/added.bin"), bytes: 5 << 20)
        try Fixtures.writeFile(root.appendingPathComponent("brand-new/deeper/x.bin"), bytes: 2 << 20)
        try FileManager.default.removeItem(at: root.appendingPathComponent("dir1"))
        try await Task.sleep(for: .seconds(1.5)) // let fseventsd flush to its history
        let second = LiveIndex(rootPath: root.path, options: ScanOptions(), hook: nil, snapshotURL: url)
        #expect(second.loaded != nil)
        await second.start()
        let du = Double(Fixtures.duBytes(root.path)) - Double(Fixtures.duBytes(url.deletingLastPathComponent().path))
        let ok = await waitUntil(10) {
            second.caughtUp && abs(Double(second.store.node(.root).totalBytes) - du) / du < 0.01
        }
        #expect(ok != nil, "tree \(second.store.node(.root).totalBytes) vs du \(du)")
        #expect(second.store.find(path: root.path + "/dir1") == nil)
        #expect(second.store.find(path: root.path + "/brand-new/deeper") != nil)
        second.stop()
    }
}
