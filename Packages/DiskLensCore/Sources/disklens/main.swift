import DiskLensCore
import Foundation

func formatBytes(_ b: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file)
}

func usage() -> Never {
    print("""
    usage: disklens top [path] [--count N]     scan (read-only) and print the biggest folders
    """)
    exit(2)
}

var args = Array(CommandLine.arguments.dropFirst())
let command = args.isEmpty ? "top" : args.removeFirst()

switch command {
case "top":
    var count = 20
    if let i = args.firstIndex(of: "--count"), i + 1 < args.count { count = Int(args[i + 1]) ?? 20; args.removeSubrange(i...i + 1) }
    let root = args.first ?? "/"
    let scanner = Scanner(rootPath: root, options: root == "/" ? .startupVolume : ScanOptions())
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
default:
    usage()
}
