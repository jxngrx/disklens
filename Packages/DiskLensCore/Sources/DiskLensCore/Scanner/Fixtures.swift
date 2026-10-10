import Foundation

/// Generates test folders under `$TMPDIR/disklens-fixtures/`. All destructive tests run only here.
public enum Fixtures {
    public static var base: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath()
            .appendingPathComponent("disklens-fixtures")
    }

    /// Fresh empty folder `base/<name>-<uuid>`.
    public static func makeRoot(_ name: String) throws -> URL {
        let url = base.appendingPathComponent("\(name)-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes `bytes` of non-zero data (so nothing is sparse).
    public static func writeFile(_ url: URL, bytes: Int) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let chunk = Data(repeating: 0xA5, count: min(bytes, 1 << 20))
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let h = try FileHandle(forWritingTo: url)
        defer { try? h.close() }
        var left = bytes
        while left > 0 {
            let n = min(left, chunk.count)
            try h.write(contentsOf: chunk.prefix(n))
            left -= n
        }
    }

    /// Deterministic tree: `dirs` folders spread over a few levels with mixed file sizes.
    public static func makeTree(at root: URL, dirs: Int, filesPerDir: Int, seed: UInt64 = 42) throws {
        var rng = SplitMix(seed: seed)
        var folders = [root]
        for i in 0..<dirs {
            let parent = folders[Int(rng.next() % UInt64(folders.count))]
            let d = parent.appendingPathComponent("dir\(i)")
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            folders.append(d)
            for f in 0..<filesPerDir {
                let size = [10, 900, 5_000, 40_000, 300_000, 1_500_000][Int(rng.next() % 6)]
                try writeFile(d.appendingPathComponent("f\(f).bin"), bytes: size)
            }
        }
    }

    /// Developer-machine-like tree for screenshots and UI tests (sizes in KB so it is quick to write).
    public static func makeShowcase(at root: URL, scale: Int = 1024) throws {
        let layout: [(String, Int)] = [
            ("Projects/web-shop/node_modules/react/index.js", 9000), ("Projects/web-shop/node_modules/next/dist.js", 14000),
            ("Projects/web-shop/node_modules/typescript/lib.js", 7000), ("Projects/web-shop/src/app.tsx", 40),
            ("Projects/web-shop/package.json", 2), ("Projects/web-shop/.next/cache.bin", 6000),
            ("Projects/MobileApp/ios/Pods/Firebase/lib.a", 12000), ("Projects/MobileApp/ios/build/app.o", 5000),
            ("Projects/MobileApp/android/app/build/out.apk", 8000), ("Projects/MobileApp/android/.gradle/state.bin", 3000),
            ("Projects/MobileApp/package.json", 2), ("Projects/MobileApp/ios/Podfile", 1), ("Projects/MobileApp/src/App.tsx", 30),
            ("Projects/rust-tool/target/debug/tool", 11000), ("Projects/rust-tool/Cargo.toml", 1), ("Projects/rust-tool/src/main.rs", 20),
            ("Library/Developer/Xcode/DerivedData/MobileApp-abc/Build.db", 22000),
            ("Library/Developer/Xcode/DerivedData/Other-def/Index.db", 9000),
            ("Library/Developer/Xcode/Archives/2026-01-01/App.xcarchive/bin", 6000),
            ("Library/Caches/CocoaPods/pods.tar", 4000), ("Library/Caches/Homebrew/pkg.tar", 3000),
            (".gradle/caches/modules/jar.bin", 15000), (".npm/_cacache/blob.bin", 5000),
            ("Movies/holiday.mov", 26000), ("Movies/talk.mp4", 9000), ("Pictures/raw/img1.dng", 4000),
            ("Pictures/raw/img2.dng", 4000), ("Music/album.flac", 6000),
            ("Documents/report.pdf", 1500), ("Documents/notes/todo.txt", 10), ("Downloads/installer.dmg", 11000),
            ("Applications/Editor.app/Contents/MacOS/Editor", 7000),
        ]
        for (rel, kb) in layout { try writeFile(root.appendingPathComponent(rel), bytes: kb * scale) }
        for i in 0..<40 { try writeFile(root.appendingPathComponent("Documents/notes/n\(i).md"), bytes: (i + 1) * 3000) }
    }

    /// Removes a fixture folder. Refuses anything outside `base`.
    public static func remove(_ url: URL) {
        let path = url.resolvingSymlinksInPath().path
        guard path.hasPrefix(base.path + "/") else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        if let e = FileManager.default.enumerator(atPath: path) {
            for case let rel as String in e {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path + "/" + rel)
            }
        }
        try? FileManager.default.removeItem(atPath: path)
    }

    /// `du -sk` of a path, in bytes.
    public static func duBytes(_ path: String) -> UInt64 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        p.arguments = ["-sk", path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (UInt64(out.split(separator: "\t").first ?? "0") ?? 0) * 1024
    }
}

struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
