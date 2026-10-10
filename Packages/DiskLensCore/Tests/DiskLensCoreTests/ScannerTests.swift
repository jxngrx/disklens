import Darwin
import Foundation
import Testing
@testable import DiskLensCore

@Suite(.serialized) struct ScannerTests {
    @Test func totalsMatchDu() async throws {
        let root = try Fixtures.makeRoot("du")
        defer { Fixtures.remove(root) }
        try Fixtures.makeTree(at: root, dirs: 120, filesPerDir: 8)
        let scanner = DiskScanner(rootPath: root.path)
        await scanner.run()
        let ours = Double(scanner.store.node(.root).totalBytes)
        let du = Double(Fixtures.duBytes(root.path))
        #expect(abs(ours - du) / du < 0.01, "scanner \(ours) vs du \(du)")
        #expect(scanner.store.node(.root).state == .complete)
        // Every directory total also matches du.
        for dir in ["dir0", "dir1", "dir5"] {
            guard let id = scanner.store.find(path: root.path + "/" + dir) else { continue }
            let d = Double(Fixtures.duBytes(root.path + "/" + dir))
            #expect(abs(Double(scanner.store.node(id).totalBytes) - d) / max(d, 1) < 0.01)
        }
    }

    @Test func hardLinksCountedOnce() async throws {
        let root = try Fixtures.makeRoot("hardlinks")
        defer { Fixtures.remove(root) }
        let target = root.appendingPathComponent("links/original.bin")
        try Fixtures.writeFile(target, bytes: 100 << 20)
        for i in 1..<10 {
            try FileManager.default.linkItem(at: target, to: root.appendingPathComponent("links/link\(i).bin"))
        }
        // Links in a second folder too.
        try Fixtures.writeFile(root.appendingPathComponent("other/x.bin"), bytes: 4096)
        try FileManager.default.linkItem(at: target, to: root.appendingPathComponent("other/link-elsewhere.bin"))
        let scanner = DiskScanner(rootPath: root.path)
        await scanner.run()
        let total = scanner.store.node(.root).totalBytes
        let mb = Double(total) / Double(1 << 20)
        #expect(mb > 99.9 && mb < 100.5, "got \(mb) MB")
        #expect(scanner.store.node(.root).fileCount == 12)
    }

    @Test func restrictedFolderDoesNotStopScan() async throws {
        let root = try Fixtures.makeRoot("restricted")
        defer { Fixtures.remove(root) }
        try Fixtures.writeFile(root.appendingPathComponent("locked/secret.bin"), bytes: 50_000)
        try Fixtures.writeFile(root.appendingPathComponent("open/a.bin"), bytes: 2 << 20)
        try Fixtures.writeFile(root.appendingPathComponent("open/deeper/b.bin"), bytes: 10_000)
        chmod(root.appendingPathComponent("locked").path, 0o000)
        let scanner = DiskScanner(rootPath: root.path)
        await scanner.run()
        let kids = scanner.store.children(of: .root)
        #expect(kids.first { $0.name == "locked" }?.kind == .restricted)
        let open = try #require(kids.first { $0.name == "open" })
        #expect(open.state == .complete && open.totalBytes >= 2 << 20)
        #expect(scanner.store.node(.root).state == .complete)
    }

    @Test func symlinksNotFollowed() async throws {
        let root = try Fixtures.makeRoot("symlink")
        defer { Fixtures.remove(root) }
        try Fixtures.writeFile(root.appendingPathComponent("real/big.bin"), bytes: 5 << 20)
        try FileManager.default.createSymbolicLink(atPath: root.path + "/alias", withDestinationPath: root.path + "/real")
        let scanner = DiskScanner(rootPath: root.path)
        await scanner.run()
        let total = Double(scanner.store.node(.root).totalBytes)
        #expect(total < Double(6 << 20))
    }

    @Test func smallFilesFoldIntoOtherFiles() async throws {
        let root = try Fixtures.makeRoot("fold")
        defer { Fixtures.remove(root) }
        for i in 0..<60 { try Fixtures.writeFile(root.appendingPathComponent("s\(i).txt"), bytes: 100) }
        for i in 0..<3 { try Fixtures.writeFile(root.appendingPathComponent("big\(i).bin"), bytes: 2 << 20) }
        let scanner = DiskScanner(rootPath: root.path)
        await scanner.run()
        let kids = scanner.store.children(of: .root)
        #expect(kids.filter { $0.kind == .file }.count == 3)
        let other = try #require(kids.first { $0.kind == .otherFiles })
        #expect(other.fileCount == 60)
        #expect(scanner.store.node(.root).fileCount == 63)
    }

    @Test func rescanAppliesDiffToAncestors() async throws {
        let root = try Fixtures.makeRoot("rescan")
        defer { Fixtures.remove(root) }
        try Fixtures.writeFile(root.appendingPathComponent("a/b/one.bin"), bytes: 1 << 20)
        let scanner = DiskScanner(rootPath: root.path)
        await scanner.run()
        let before = scanner.store.node(.root).totalBytes
        try Fixtures.writeFile(root.appendingPathComponent("a/b/two.bin"), bytes: 3 << 20)
        try Fixtures.writeFile(root.appendingPathComponent("a/b/new/three.bin"), bytes: 1 << 20)
        let b = try #require(scanner.store.find(path: root.path + "/a/b"))
        await scanner.rescan([b])
        let after = scanner.store.node(.root).totalBytes
        #expect(after - before >= 4 << 20)
        #expect(scanner.store.node(.root).state == .complete)
        #expect(abs(Double(after) - Double(Fixtures.duBytes(root.path))) / Double(after) < 0.01)
        // Removing a folder subtracts it.
        try FileManager.default.removeItem(at: root.appendingPathComponent("a/b/new"))
        await scanner.rescan([b])
        #expect(abs(Double(scanner.store.node(.root).totalBytes) - Double(Fixtures.duBytes(root.path))) < 64 * 1024)
    }
}

/// Records, per run, the listing index at which each top-level folder became complete.
final class CompletionLog: @unchecked Sendable {
    let lock = NSLock()
    var listings = 0
    var completedAt: [String: Int] = [:]
}

@Suite(.serialized) struct PriorityTests {
    func makeTwoTrees() throws -> URL {
        let root = try Fixtures.makeRoot("priority")
        for top in ["A", "B"] {
            for i in 0..<150 {
                let d = root.appendingPathComponent("\(top)/d\(i % 10)/e\(i)")
                try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: d.path + "/f", contents: Data(count: 10))
            }
        }
        return root
    }

    /// Scans with 1 worker; after `switchAfter` listings, focuses `focusName` (if any).
    func run(_ root: URL, focusName: String?, switchAfter: Int = 20) async -> [String: Int] {
        let log = CompletionLog()
        let box = ScannerBox()
        var opts = ScanOptions()
        opts.workers = 1
        let scanner = DiskScanner(rootPath: root.path, options: opts) { store, _, _, _, _ in
            log.lock.withLock {
                log.listings += 1
                for n in store.children(of: .root) where n.state == .complete && log.completedAt[n.name] == nil {
                    log.completedAt[n.name] = log.listings
                }
                if log.listings == switchAfter, let f = focusName, let id = store.children(of: .root).first(where: { $0.name == f })?.id {
                    let sem = DispatchSemaphore(value: 0)
                    Task { await box.scanner?.setFocus(id); sem.signal() }
                    sem.wait()
                }
            }
        }
        box.scanner = scanner
        await scanner.run()
        return log.completedAt
    }

    @Test func focusedFolderFinishesFirst() async throws {
        let root = try makeTwoTrees()
        defer { Fixtures.remove(root) }
        let control = await run(root, focusName: nil)
        let naturalLast = control["A"]! > control["B"]! ? "A" : "B"
        let other = naturalLast == "A" ? "B" : "A"
        // Focus the folder that would naturally finish last, mid-scan.
        let focused = await run(root, focusName: naturalLast)
        #expect(focused[naturalLast]! < focused[other]!, "control \(control), focused \(focused)")
    }
}

final class ScannerBox: @unchecked Sendable { var scanner: DiskScanner? }

struct SystemOtherTests {
    @Test func relistingRootKeepsSystemOther() async throws {
        let root = try Fixtures.makeRoot("sysother")
        defer { Fixtures.remove(root) }
        try Fixtures.writeFile(root.appendingPathComponent("a/x.bin"), bytes: 1 << 20)
        let scanner = DiskScanner(rootPath: root.path)
        await scanner.run()
        scanner.store.setSystemOther(bytes: 5 << 20)
        let total = scanner.store.node(.root).totalBytes
        await scanner.rescan([.root])
        #expect(scanner.store.children(of: .root).contains { $0.kind == .systemOther })
        #expect(scanner.store.node(.root).totalBytes == total)
    }
}
