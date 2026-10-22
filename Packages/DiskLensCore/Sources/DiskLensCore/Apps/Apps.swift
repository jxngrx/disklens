import Darwin
import Foundation

public struct InstalledApp: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public var path: String
    public var name: String
    /// Folder-name candidates used to match `~/Library/<dir>/<name>` leftovers.
    public var aliases: [String]
    public var bundleID: String?
    public var version: String?
    public var bytes: UInt64
    public var isUser: Bool
}

public struct Leftover: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public var path: String
    public var bytes: UInt64
}

public enum Apps {
    /// Real allocated size of a file or folder tree.
    public static func diskSize(_ path: String) -> UInt64 {
        var st = stat()
        guard lstat(path, &st) == 0 else { return 0 }
        if (st.st_mode & S_IFMT) != S_IFDIR { return UInt64(st.st_blocks) * 512 }
        guard let en = FileManager.default.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
                                                      options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: UInt64 = 0
        for case let u as URL in en {
            if let s = try? u.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize { total += UInt64(s) }
        }
        return total
    }

    /// Apps in /Applications (one subfolder level deep, e.g. Utilities) and ~/Applications. Apple's own
    /// read-only apps live in /System/Applications and are never listed.
    public static func installed(home: String = NSHomeDirectory(), roots: [String]? = nil,
                                 size: (String) -> UInt64 = Apps.diskSize) -> [InstalledApp] {
        let fm = FileManager.default
        var out: [InstalledApp] = []
        for root in roots ?? ["/Applications", home + "/Applications"] {
            let isUser = root.hasPrefix(home + "/")
            for e in (try? fm.contentsOfDirectory(atPath: root)) ?? [] where !e.hasPrefix(".") {
                let p = root + "/" + e
                if e.hasSuffix(".app") { if !isSystemLink(p) { out.append(app(at: p, isUser: isUser, size: size)) }; continue }
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue else { continue }
                for s in (try? fm.contentsOfDirectory(atPath: p)) ?? [] where s.hasSuffix(".app") && !isSystemLink(p + "/" + s) {
                    out.append(app(at: p + "/" + s, isUser: isUser, size: size))
                }
            }
        }
        return out
    }

    /// Apple's built-in apps appear in /Applications as links into the sealed system volume; they cannot be removed.
    static func isSystemLink(_ path: String) -> Bool {
        var st = stat()
        if lstat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFLNK { return true }
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().path.hasPrefix("/System/")
    }

    static func app(at path: String, isUser: Bool, size: (String) -> UInt64) -> InstalledApp {
        let info = NSDictionary(contentsOfFile: path + "/Contents/Info.plist") as? [String: Any] ?? [:]
        let stem = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let display = info["CFBundleDisplayName"] as? String
        let short = info["CFBundleName"] as? String
        let aliases = Array(Set([stem, display, short].compactMap { $0 }))
        return InstalledApp(path: path, name: display ?? stem, aliases: aliases, bundleID: info["CFBundleIdentifier"] as? String,
                            version: info["CFBundleShortVersionString"] as? String, bytes: size(path), isUser: isUser)
    }

    static func userCacheDirs() -> [String] {
        // confstr: /private/var/folders/xx/yyyy/C and /T hold per-app caches keyed by bundle ID.
        func dir(_ name: Int32) -> String? {
            var buf = [Int8](repeating: 0, count: 1024)
            return confstr(name, &buf, buf.count) > 0 ? String(cString: buf) : nil
        }
        return [dir(_CS_DARWIN_USER_CACHE_DIR), dir(_CS_DARWIN_USER_TEMP_DIR)].compactMap { $0 }
    }

    /// Everything the app left behind in the known per-app locations, matched by bundle ID (prefix) or exact
    /// folder name. `extra` are paths found by a wider search; they are kept only if their own name carries the bundle ID.
    public static func leftovers(for app: InstalledApp, home: String = NSHomeDirectory(), cacheDirs: [String]? = nil,
                                 extra: [String] = [], size: (String) -> UInt64 = Apps.diskSize) -> [Leftover] {
        let fm = FileManager.default
        let b = app.bundleID?.lowercased()
        let names = Set(app.aliases.filter { $0.count >= 3 }.map { $0.lowercased() })
        func idMatch(_ e: String) -> Bool {
            guard let b else { return false }
            let l = e.lowercased()
            return l == b || l.hasPrefix(b + ".")
        }
        var found: [String] = []
        func scan(_ dir: String, byName: Bool, contains: Bool = false) {
            for e in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] {
                let l = e.lowercased()
                if idMatch(e) || (byName && names.contains(l)) || (contains && b.map { l.contains($0) } == true) {
                    found.append(dir + "/" + e)
                }
            }
        }
        let lib = home + "/Library"
        for (d, byName) in [("Application Support", true), ("Caches", true), ("Logs", true), ("Containers", false), ("Preferences", false),
                            ("Preferences/ByHost", false), ("Saved Application State", false), ("HTTPStorages", false), ("WebKit", false),
                            ("Cookies", false), ("Application Scripts", false), ("LaunchAgents", false)] {
            scan(lib + "/" + d, byName: byName)
        }
        scan(lib + "/Group Containers", byName: false, contains: true)
        for (d, byName) in [("Application Support", true), ("Caches", true), ("Logs", true), ("Preferences", false), ("LaunchAgents", false),
                            ("LaunchDaemons", false), ("PrivilegedHelperTools", false)] {
            scan("/Library/" + d, byName: byName)
        }
        for d in cacheDirs ?? userCacheDirs() { scan(d, byName: false) }
        for p in extra where idMatch((p as NSString).lastPathComponent) { found.append(p) }

        // Drop duplicates, anything inside the app itself, and children of an already-listed folder.
        let sorted = Set(found).filter { !$0.hasPrefix(app.path) }.sorted()
        var kept: [String] = []
        for p in sorted where !kept.contains(where: { p.hasPrefix($0 + "/") }) { kept.append(p) }
        return kept.map { Leftover(path: $0, bytes: size($0)) }.sorted { $0.bytes > $1.bytes }
    }
}

public enum Uninstaller {
    /// The only places an uninstall may delete from: the app bundle roots, plus per-app entries inside a Library
    /// folder (never the Library folder or a category folder itself) and the per-user cache folders.
    public static func isAllowed(_ path: String, home: String = NSHomeDirectory(), appRoots: [String]? = nil,
                                 cacheDirs: [String]? = nil) -> Bool {
        guard path.hasPrefix("/"), !path.contains("/../"), !path.hasSuffix("/..") else { return false }
        if path.contains("/Mobile Documents/") || path.contains("/CloudStorage/") { return false }
        func depth(below root: String) -> Int? {
            guard path.hasPrefix(root + "/") else { return nil }
            return path.dropFirst(root.count + 1).split(separator: "/").count
        }
        for r in appRoots ?? ["/Applications", home + "/Applications"] {
            if path.hasSuffix(".app"), let d = depth(below: r), d <= 2 { return true }
        }
        for r in [home + "/Library", "/Library"] { if let d = depth(below: r), d >= 2 { return true } }
        for r in cacheDirs ?? Apps.userCacheDirs() { if let d = depth(below: r.hasSuffix("/") ? String(r.dropLast()) : r), d >= 1 { return true } }
        return false
    }

    public struct Outcome: Sendable {
        public var removed: [String] = []
        public var failed: [String] = []
    }

    /// Deletes each allowed path. Permission failures are retried once as root through one admin prompt.
    public static func remove(_ paths: [String], home: String = NSHomeDirectory(), appRoots: [String]? = nil, cacheDirs: [String]? = nil,
                              admin: ([String]) -> Bool = Uninstaller.runAsAdmin) -> Outcome {
        let fm = FileManager.default
        var out = Outcome()
        var needAdmin: [String] = []
        for p in paths {
            guard isAllowed(p, home: home, appRoots: appRoots, cacheDirs: cacheDirs) else { out.failed.append(p); continue }
            if !fm.fileExists(atPath: p) && (try? fm.destinationOfSymbolicLink(atPath: p)) == nil { out.removed.append(p); continue }
            if p.contains("/LaunchAgents/"), p.hasSuffix(".plist") {
                _ = CommandRunner.query(["launchctl", "bootout", "gui/\(getuid())", p])
            }
            if (try? fm.removeItem(atPath: p)) != nil { out.removed.append(p); continue }
            _ = CommandRunner.query(["chmod", "-R", "u+w", p])
            if (try? fm.removeItem(atPath: p)) != nil { out.removed.append(p) } else { needAdmin.append(p) }
        }
        if !needAdmin.isEmpty {
            if admin(needAdmin) {
                for p in needAdmin { if fm.fileExists(atPath: p) { out.failed.append(p) } else { out.removed.append(p) } }
            } else {
                out.failed += needAdmin
            }
        }
        return out
    }

    /// One macOS admin password prompt for the whole batch. Paths were already validated by `isAllowed`.
    public static func runAsAdmin(_ paths: [String]) -> Bool {
        let shell = "/bin/rm -rf " + paths.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
        let script = "do shell script \"" + shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            + "\" with administrator privileges"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
