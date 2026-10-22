import Foundation
import Testing
@testable import DiskLensCore

struct AppsTests {
    /// Fake app + leftovers under the fixtures folder: finder lists them, uninstall removes them and nothing else.
    @Test func findsAndRemovesLeftovers() throws {
        let root = try Fixtures.makeRoot("apps")
        defer { Fixtures.remove(root) }
        let home = root.appendingPathComponent("home").path
        let apps = root.appendingPathComponent("Applications").path
        let app = apps + "/Foo.app"
        try FileManager.default.createDirectory(atPath: app + "/Contents", withIntermediateDirectories: true)
        let plist: NSDictionary = ["CFBundleIdentifier": "com.acme.foo", "CFBundleName": "Foo", "CFBundleShortVersionString": "2.0"]
        plist.write(toFile: app + "/Contents/Info.plist", atomically: true)
        try Fixtures.writeFile(URL(fileURLWithPath: app + "/Contents/bin"), bytes: 10_000)
        let mine = ["Library/Application Support/Foo/db", "Library/Caches/com.acme.foo/c", "Library/Preferences/com.acme.foo.plist",
                    "Library/Containers/com.acme.foo/Data/x", "Library/Saved Application State/com.acme.foo.savedState/w"]
        let others = ["Library/Application Support/Foobar/db", "Library/Caches/com.acme.foobar/c", "Documents/keep.txt"]
        for r in mine + others { try Fixtures.writeFile(URL(fileURLWithPath: home + "/" + r), bytes: 2_000) }

        let list = Apps.installed(home: home, roots: [apps])
        #expect(list.map(\.name) == ["Foo"] && list[0].bundleID == "com.acme.foo" && list[0].bytes > 0)
        let left = Apps.leftovers(for: list[0], home: home, cacheDirs: [])
        #expect(Set(left.map(\.path)) == Set(["Library/Application Support/Foo", "Library/Caches/com.acme.foo", "Library/Preferences/com.acme.foo.plist",
                                              "Library/Containers/com.acme.foo", "Library/Saved Application State/com.acme.foo.savedState"].map { home + "/" + $0 }))

        // Guard: category folders and unrelated places are never deletable.
        #expect(!Uninstaller.isAllowed(home + "/Library/Caches", home: home, appRoots: [apps], cacheDirs: []))
        #expect(!Uninstaller.isAllowed(home + "/Documents/keep.txt", home: home, appRoots: [apps], cacheDirs: []))
        #expect(!Uninstaller.isAllowed("/System/Applications/Safari.app", home: home, appRoots: [apps], cacheDirs: []))

        let out = Uninstaller.remove([app] + left.map(\.path), home: home, appRoots: [apps], cacheDirs: [], admin: { _ in false })
        #expect(out.failed.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: app))
        #expect(left.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        for r in others { #expect(FileManager.default.fileExists(atPath: home + "/" + r)) }
    }
}
