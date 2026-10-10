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
