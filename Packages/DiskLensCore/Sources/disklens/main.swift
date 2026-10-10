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
           disklens projects [path] [--rules-home H]       projects by reclaimable size
           disklens mobile                               AVDs, system images, NDKs, simulator runtimes
           disklens history [--file F]                   disk growth samples
           disklens daemon --keep-free GB [--root P] [--interval S] [--once] [--dry-run]
                           [--rules-home H] [--quarantine-root Q] [--index F] [--history F]
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
case "projects":
    // disklens projects [path] [--rules-home H] : projects by reclaimable size with last worked on
    let rules = try ruleSet(&args)
    let scanner = DiskScanner(rootPath: args.first ?? NSHomeDirectory(), hook: rules.listingHook())
    await scanner.run()
    for p in Projects.collect(store: scanner.store, rules: rules) {
        let last = Projects.lastWorkedOn(p.path, rules: rules).map { RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: Date()) } ?? "?"
        print(formatBytes(p.reclaimable).padding(toLength: 10, withPad: " ", startingAt: 0), last.padding(toLength: 16, withPad: " ", startingAt: 0), p.path)
    }
case "mobile":
    // disklens mobile : AVDs, system images, NDKs, simulator runtimes (read-only listing)
    for i in MobilePack().items() {
        print(formatBytes(i.bytes).padding(toLength: 10, withPad: " ", startingAt: 0),
              i.kind.rawValue.padding(toLength: 22, withPad: " ", startingAt: 0),
              (i.inUse ? "in use (\(i.usedBy.joined(separator: ", ")))" : "no known use").padding(toLength: 28, withPad: " ", startingAt: 0),
              i.name, "  →", i.command.joined(separator: " "))
    }
case "history":
    for h in History.load(from: take(&args, "--file").map { URL(fileURLWithPath: $0) } ?? History.defaultURL) {
        print(h.date, "used", formatBytes(h.usedBytes), "free", formatBytes(h.freeBytes))
    }
case "daemon":
    // disklens daemon --keep-free GB [--root P] [--interval S] [--once] [--dry-run] [--rules-home H] [--quarantine-root Q] [--index FILE]
    guard let gb = take(&args, "--keep-free").flatMap(Double.init) else { usage() }
    let root = take(&args, "--root") ?? "/"
    let interval = take(&args, "--interval").flatMap(Double.init) ?? 300
    let indexFile = take(&args, "--index").map { URL(fileURLWithPath: $0) }
    let historyFile = take(&args, "--history").map { URL(fileURLWithPath: $0) } ?? History.defaultURL
    let once = take(&args, flag: "--once")
    let dry = take(&args, flag: "--dry-run") || ProcessInfo.processInfo.environment["DISKLENS_DRY_RUN"] == "1"
    let rules = try ruleSet(&args)
    let cleaner = Cleaner(rules: rules, quarantine: quarantine(&args), runner: CommandRunner(dryRun: dry))
    let index = LiveIndex(rootPath: root, options: root == "/" ? .startupVolume : ScanOptions(), hook: rules.listingHook(),
                          snapshotURL: indexFile, ignore: [cleaner.quarantine.root.path])
    await index.start(watch: !once)
    let policy = KeepFreePolicy(keepFreeBytes: UInt64(gb * 1e9))
    while true {
        cleaner.quarantine.purge()
        History.record(store: index.store, to: historyFile, minInterval: once ? 0 : 3600)
        let free = UInt64(max(0, (try? URL(fileURLWithPath: root).resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity) ?? 0))
        let steps = policy.plan(freeBytes: free, quarantine: cleaner.quarantine.items(), store: index.store, rules: rules)
        print("\(Date()) free \(formatBytes(free)), keep \(formatBytes(policy.keepFreeBytes)): \(steps.isEmpty ? "ok" : "\(steps.count) steps")")
        policy.apply(steps, cleaner: cleaner, dryRun: dry).forEach { print("  " + $0) }
        try? index.save()
        if once { break }
        try await Task.sleep(for: .seconds(interval))
    }
case "make-fixture":
    let root = try Fixtures.makeRoot(args.first ?? "showcase")
    try Fixtures.makeShowcase(at: root)
    print(root.path)
default:
    usage()
}
