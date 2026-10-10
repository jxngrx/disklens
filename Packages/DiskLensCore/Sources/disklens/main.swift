import DiskLensCore
import Foundation

func formatBytes(_ b: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file)
}

func usage() -> Never {
    print("""
    usage: disklens top [path] [--count N]     scan (read-only) and print the biggest folders
           disklens rules <path>... [--rules-home H]      show which rule allows cleaning each path
           disklens clean <path>... [--dry-run] [--rules-home H] [--quarantine-root Q]
           disklens quarantine [list|restore <id|all>|purge|empty] [--quarantine-root Q]
           disklens make-fixture [name]         create a demo tree under $TMPDIR/disklens-fixtures
    """)
    exit(2)
}

/// Removes `--flag value` from args and returns the value.
func take(_ args: inout [String], _ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    defer { args.removeSubrange(i...i + 1) }
    return args[i + 1]
}

func take(_ args: inout [String], flag: String) -> Bool {
    guard let i = args.firstIndex(of: flag) else { return false }
    args.remove(at: i)
    return true
}

/// `--rules-home` points `~` in rules.json somewhere else (fixtures).
func ruleSet(_ args: inout [String]) throws -> RuleSet {
    try RuleSet(home: take(&args, "--rules-home") ?? NSHomeDirectory())
}

func quarantine(_ args: inout [String]) -> Quarantine {
    Quarantine(root: take(&args, "--quarantine-root").map { URL(fileURLWithPath: $0) } ?? Quarantine.defaultRoot)
}

var args = Array(CommandLine.arguments.dropFirst())
let command = args.isEmpty ? "top" : args.removeFirst()

switch command {
case "top":
    var count = 20
    if let i = args.firstIndex(of: "--count"), i + 1 < args.count { count = Int(args[i + 1]) ?? 20; args.removeSubrange(i...i + 1) }
    let root = args.first ?? "/"
    let scanner = DiskScanner(rootPath: root, options: root == "/" ? .startupVolume : ScanOptions())
    let start = Date()
    await scanner.run()
    scanner.updateSystemOther()
    let elapsed = Date().timeIntervalSince(start)
    let rootInfo = scanner.store.node(.root)
    for (path, bytes) in scanner.store.largestDirectories(limit: count) {
        print(formatBytes(bytes).padding(toLength: 12, withPad: " ", startingAt: 0), path)
    }
    let restricted = scanner.store.nodes { $0.kind == .restricted }.count
    print(String(format: "\nscanned %@ files, %@ total, %d nodes, %d restricted, %.2f s",
                 "\(rootInfo.fileCount)", formatBytes(rootInfo.totalBytes), scanner.store.count, restricted, elapsed))
case "rules":
    // disklens rules <path>... : which rule (if any) allows cleaning each path
    let rules = try ruleSet(&args)
    for path in args {
        if let m = rules.match(path) {
            print("\(path)\t\(m.rule.name)\t\(m.rule.safety.rawValue)\t\(m.rule.command?.joined(separator: " ") ?? "quarantine")")
        } else {
            print("\(path)\tnot cleanable")
        }
    }
case "clean":
    // disklens clean <path>... [--dry-run] : quarantine (or run the tool command for) rule-matched paths
    let dry = take(&args, flag: "--dry-run")
    let cleaner = Cleaner(rules: try ruleSet(&args), quarantine: quarantine(&args), runner: CommandRunner(dryRun: dry || ProcessInfo.processInfo.environment["DISKLENS_DRY_RUN"] == "1"))
    let plan = try cleaner.plan(args.map { ($0, Fixtures.duBytes($0)) })
    for r in cleaner.execute(plan) {
        print(r.error.map { "FAILED \(r.item.path): \($0)" } ?? "cleaned \(r.item.path) (\(formatBytes(r.item.bytes)))\(r.quarantined != nil ? " -> quarantine" : "")")
    }
    cleaner.runner.log.forEach { print($0) }
case "quarantine":
    // disklens quarantine list|restore <id|all>|purge|empty
    let q = quarantine(&args)
    switch args.first ?? "list" {
    case "restore":
        for item in q.items() where args.count > 1 && (args[1] == "all" || args[1] == item.id.uuidString) {
            do { try q.restore(item); print("restored \(item.originalPath)") } catch { print("FAILED \(item.originalPath): \(error)") }
        }
    case "purge": q.purge().forEach { print("deleted \($0.originalPath)") }
    case "empty": q.purge(everything: true).forEach { print("deleted \($0.originalPath)") }
    default:
        for i in q.items() { print("\(i.id.uuidString)  \(formatBytes(i.bytes))  \(i.date)  \(i.originalPath)") }
    }
case "make-fixture":
    let root = try Fixtures.makeRoot(args.first ?? "showcase")
    try Fixtures.makeShowcase(at: root)
    print(root.path)
default:
    usage()
}
