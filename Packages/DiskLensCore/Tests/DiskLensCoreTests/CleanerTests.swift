import CryptoKit
import Darwin
import Foundation
import Testing
@testable import DiskLensCore

/// A fake home folder with developer junk, projects and source files. Everything lives in the fixture root.
struct FakeHome {
    let root: URL
    var home: String { root.appendingPathComponent("home").path }
    var tmp: String { root.appendingPathComponent("tmp").path }
    let rules: RuleSet

    init() throws {
        root = try Fixtures.makeRoot("cleaner")
        let h = root.appendingPathComponent("home")
        let files: [(String, Int)] = [
            ("Library/Developer/Xcode/DerivedData/App-abc/Build/x.o", 300_000),
            ("Library/Developer/Xcode/DerivedData/App-abc/info.plist", 1_000),
            ("Library/Developer/Xcode/Archives/2026-01-01/App.xcarchive/Info.plist", 5_000),
            ("Library/Caches/CocoaPods/Pods/a.tar", 50_000),
            (".npm/_cacache/x", 20_000),
            (".gradle/caches/modules-2/a.jar", 80_000),
            ("Projects/web/package.json", 100), ("Projects/web/src/index.js", 2_000),
            ("Projects/web/node_modules/react/index.js", 40_000), ("Projects/web/node_modules/react/node_modules/x/y.js", 4_000),
            ("Projects/web/dist/bundle.js", 9_000),
            ("Projects/rn/package.json", 100), ("Projects/rn/ios/Pods/Firebase/lib.a", 60_000),
            ("Projects/rn/android/app/build/out.apk", 70_000), ("Projects/rn/App.tsx", 500),
            ("NotAProject/node_modules/lib.js", 5_000), ("NotAProject/dist/x.js", 1_000),
            ("Documents/thesis.docx", 30_000),
        ]
        for (rel, size) in files { try Fixtures.writeFile(h.appendingPathComponent(rel), bytes: size) }
        for (i, v) in ["16.0", "17.0", "17.5", "18.0"].enumerated() {
            let d = h.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport/\(v)")
            try Fixtures.writeFile(d.appendingPathComponent("Symbols/dyld"), bytes: 10_000)
            utimes(d.path, [timeval(tv_sec: 1_700_000_000 + i * 1000, tv_usec: 0), timeval(tv_sec: 1_700_000_000 + i * 1000, tv_usec: 0)])
        }
        try FileManager.default.createSymbolicLink(atPath: h.path + "/Library/Developer/Xcode/DerivedData/link-to-docs",
                                                   withDestinationPath: h.path + "/Documents")
        try FileManager.default.createDirectory(atPath: root.path + "/tmp/metro-cache-1", withIntermediateDirectories: true)
        rules = try RuleSet(home: root.appendingPathComponent("home").path, tmpDir: root.path + "/tmp/", androidHome: root.path + "/android")
    }

    func p(_ rel: String) -> String { home + "/" + rel }
}

/// sha256 of every file (relative path → hash), plus file modes, for byte-identical checks.
func treeDigest(_ path: String) -> [String: String] {
    var out: [String: String] = [:]
    let e = FileManager.default.enumerator(atPath: path)!
    for case let rel as String in e {
        var st = stat()
        lstat(path + "/" + rel, &st)
        if (st.st_mode & S_IFMT) == S_IFREG {
            let d = SHA256.hash(data: FileManager.default.contents(atPath: path + "/" + rel)!)
            out[rel] = d.map { String(format: "%02x", $0) }.joined() + " \(st.st_mode)"
        } else {
            out[rel] = "dir \(st.st_mode)"
        }
    }
    return out
}

@Suite(.serialized) struct RulesTests {
    @Test func matchesRulesAndArtifacts() throws {
        let f = try FakeHome()
        defer { Fixtures.remove(f.root) }
        #expect(f.rules.match(f.p("Library/Developer/Xcode/DerivedData/App-abc"))?.rule.name == "Xcode DerivedData")
        #expect(f.rules.match(f.p("Library/Developer/Xcode/Archives/2026-01-01"))?.rule.safety == .caution)
        #expect(f.rules.match(f.p(".npm"))?.rule.command == ["npm", "cache", "clean", "--force"])
        #expect(f.rules.match(f.p("Projects/web/node_modules"))?.projectPath == f.p("Projects/web"))
        #expect(f.rules.match(f.p("Projects/web/dist")) != nil)
        #expect(f.rules.match(f.p("Projects/rn/ios/Pods"))?.projectPath == f.p("Projects/rn"))
        #expect(f.rules.match(f.p("Projects/rn/android/app/build")) != nil)
        #expect(f.rules.match(f.tmp + "/metro-cache-1")?.rule.name == "Metro cache")
        // Keep the newest 2 DeviceSupport versions.
        #expect(f.rules.match(f.p("Library/Developer/Xcode/iOS DeviceSupport/16.0")) != nil)
        #expect(f.rules.match(f.p("Library/Developer/Xcode/iOS DeviceSupport/17.0")) != nil)
        #expect(f.rules.match(f.p("Library/Developer/Xcode/iOS DeviceSupport/17.5")) == nil)
        #expect(f.rules.match(f.p("Library/Developer/Xcode/iOS DeviceSupport/18.0")) == nil)
    }

    /// Phase 4 check: nothing outside a rule's paths can ever be selected for cleaning.
    @Test func nothingOutsideRulesIsCleanable() throws {
        let f = try FakeHome()
        defer { Fixtures.remove(f.root) }
        let allowedPrefixes = [
            "Library/Developer/Xcode/DerivedData/", "Library/Developer/Xcode/Archives/", "Library/Developer/Xcode/iOS DeviceSupport/",
        ].map(f.p)
        let allowedExact = Set([".npm", ".gradle/caches", "Library/Caches/CocoaPods", "Projects/web/node_modules", "Projects/web/dist",
                                "Projects/web/node_modules/react/node_modules", "Projects/rn/ios/Pods", "Projects/rn/android/app/build"].map(f.p))
        var matched: [String] = []
        let e = FileManager.default.enumerator(atPath: f.root.path)!
        for case let rel as String in e {
            let path = f.root.path + "/" + rel
            guard let m = f.rules.match(path) else { continue }
            matched.append(path)
            let ok = allowedExact.contains(path) || m.rule.name == "Metro cache"
                || allowedPrefixes.contains { path.hasPrefix($0) && !path.dropFirst($0.count).contains("/") }
            #expect(ok, "unexpected cleanable path \(path) via \(m.rule.name)")
        }
        // Explicit negatives: source files, project roots, the home, non-project node_modules, symlinks, parents.
        for rel in ["Projects/web/src/index.js", "Projects/web/src", "Projects/web", "Projects/web/package.json", "Documents",
                    "Documents/thesis.docx", "NotAProject/node_modules", "NotAProject/dist", "Library/Developer/Xcode/DerivedData",
                    "Library/Developer/Xcode/DerivedData/link-to-docs", "Library", ""] {
            #expect(f.rules.match(f.p(rel)) == nil, "\(rel) must not be cleanable")
        }
        #expect(f.rules.match("/") == nil)
        #expect(f.rules.match(f.p("Projects/web/node_modules/../src")) == nil)
        #expect(matched.count >= 10)
        let cleaner = Cleaner(rules: f.rules, quarantine: Quarantine(root: f.root.appendingPathComponent("q")), runner: CommandRunner(dryRun: true))
        #expect(throws: CleanError.notCleanable(f.p("Documents"))) { try cleaner.plan([(f.p("Documents"), 1)]) }
    }

    /// Cleaning deletes permanently (no quarantine) and leaves sibling source files alone.
    @Test func cleanDeletesPermanently() throws {
        let f = try FakeHome()
        defer { Fixtures.remove(f.root) }
        let targets = [f.p("Projects/web/node_modules"), f.p("Library/Developer/Xcode/DerivedData/App-abc")]
        let q = Quarantine(root: f.root.appendingPathComponent("home/.disklens-quarantine"))
        let runner = CommandRunner(dryRun: true)
        let cleaner = Cleaner(rules: f.rules, quarantine: q, runner: runner)
        let results = cleaner.execute(try cleaner.plan(targets.map { ($0, 1) }))
        #expect(results.allSatisfy { $0.error == nil && $0.removed && $0.quarantined == nil })
        #expect(targets.allSatisfy { !FileManager.default.fileExists(atPath: $0) })
        #expect(q.items().isEmpty)
        #expect(FileManager.default.fileExists(atPath: f.p("Projects/web/src/index.js")))
        #expect(runner.log.isEmpty)
    }

    /// A read-only folder inside the target must not make the clean fail.
    @Test func cleanHandlesReadOnlyFolders() throws {
        let f = try FakeHome()
        defer { Fixtures.remove(f.root) }
        let target = f.p("Library/Developer/Xcode/DerivedData/App-abc")
        let inner = target + "/ro"
        try FileManager.default.createDirectory(atPath: inner, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: inner + "/x", contents: Data("x".utf8))
        chmod(inner, 0o555)
        let cleaner = Cleaner(rules: f.rules, quarantine: Quarantine(root: f.root.appendingPathComponent("q")), runner: CommandRunner(dryRun: true))
        let r = cleaner.execute(try cleaner.plan([(target, 1)]))
        #expect(r.allSatisfy { $0.error == nil && $0.removed })
        #expect(!FileManager.default.fileExists(atPath: target))
    }

    @Test func commandRulesOnlyLogInDryRun() throws {
        let f = try FakeHome()
        defer { Fixtures.remove(f.root) }
        let runner = CommandRunner(dryRun: true)
        let cleaner = Cleaner(rules: f.rules, quarantine: Quarantine(root: f.root.appendingPathComponent("q")), runner: runner)
        let results = cleaner.execute(try cleaner.plan([(f.p(".npm"), 1), (f.p(".gradle/caches"), 1)]))
        #expect(results.allSatisfy { $0.error == nil })
        #expect(runner.log == ["[dry-run] npm cache clean --force", "[dry-run] gradle --stop"])
        #expect(FileManager.default.fileExists(atPath: f.p(".npm/_cacache/x")))
        // Gradle caches is quarantined after `gradle --stop`.
        #expect(!FileManager.default.fileExists(atPath: f.p(".gradle/caches")))
        #expect(plan(f, cleaner, ".npm").rule.quarantinable == false)
    }

    func plan(_ f: FakeHome, _ c: Cleaner, _ rel: String) -> CleanItem { try! c.plan([(f.p(rel), 1)]).first! }

    @Test func purgeDeletesOnlyExpiredItems() throws {
        let f = try FakeHome()
        defer { Fixtures.remove(f.root) }
        let q = Quarantine(root: f.root.appendingPathComponent("home/.disklens-quarantine"), retentionDays: 7)
        let old = try q.add(path: f.p("Projects/web/dist"), bytes: 1, ruleID: 15, now: Date().addingTimeInterval(-8 * 86_400))
        let fresh = try q.add(path: f.p("Projects/web/node_modules"), bytes: 1, ruleID: 15)
        let purged = q.purge()
        #expect(purged.map(\.id) == [old.id])
        #expect(!FileManager.default.fileExists(atPath: old.storedPath))
        #expect(q.items().map(\.id) == [fresh.id])
        #expect(q.purge(everything: true).count == 1)
        #expect(q.items().isEmpty)
    }

    @Test func scannerHookTagsNodesAndProjects() async throws {
        let f = try FakeHome()
        defer { Fixtures.remove(f.root) }
        let scanner = DiskScanner(rootPath: f.home, hook: f.rules.listingHook())
        await scanner.run()
        let s = scanner.store
        #expect(s.node(s.find(path: f.p("Library/Developer/Xcode/DerivedData/App-abc"))!).ruleID == 1)
        #expect(s.node(s.find(path: f.p("Projects/web/node_modules"))!).ruleID == f.rules.artifactRule.id)
        #expect(s.node(s.find(path: f.p("NotAProject/node_modules"))!).ruleID == 0)
        #expect(s.node(s.find(path: f.p("Projects/web/src"))!).ruleID == 0)
        #expect(s.isProject(s.find(path: f.p("Projects/web"))!))
        let projects = Projects.collect(store: s, rules: f.rules)
        #expect(Set(projects.map(\.name)) == ["web", "rn"])
        let web = projects.first { $0.name == "web" }!
        #expect(Set(web.artifacts.map { ($0.path as NSString).lastPathComponent }) == ["node_modules", "dist"])
        #expect(Projects.lastWorkedOn(f.p("Projects/web"), rules: f.rules) != nil)
    }
}
