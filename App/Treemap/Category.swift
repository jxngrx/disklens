import DiskLensCore
import SwiftUI

/// Colour category of a box. Dev artifacts are split by ecosystem.
enum Category: String, CaseIterable {
    case node, apple, android, rust, otherDev, media, apps, system, folder, file

    static let nodeNames: Set<String> = ["node_modules", ".npm", ".next", ".yarn", ".pnpm-store", "pnpm", "Yarn", ".nuxt", "bower_components"]
    static let appleNames: Set<String> = ["DerivedData", "Pods", "CocoaPods", "Archives", "iOS DeviceSupport", "CoreSimulator",
                                          "Xcode", "Developer", ".build", "Carthage", "XCPGDevices"]
    static let androidNames: Set<String> = [".gradle", ".android", "Android", ".cxx", "system-images", "ndk", "avd", "caches", ".m2", ".konan"]
    static let rustNames: Set<String> = ["target", ".cargo", ".rustup", ".dart_tool", ".pub-cache", "go", ".go"]
    static let otherDevNames: Set<String> = ["build", "dist", ".cache", "venv", ".venv", "__pycache__", "Homebrew", ".docker", "Docker"]
    static let mediaNames: Set<String> = ["Movies", "Music", "Pictures", "Photos Library.photoslibrary"]
    static let mediaExt: Set<String> = ["mp4", "mov", "mkv", "avi", "m4v", "mp3", "wav", "aac", "flac", "m4a", "jpg", "jpeg",
                                        "png", "heic", "gif", "raw", "cr2", "dng", "psd", "photoslibrary"]
    static let systemNames: Set<String> = ["System", "Library", "usr", "private", "bin", "sbin", "opt", "cores", "var", "etc"]

    static func of(_ n: NodeInfo, ruleEcosystem: String? = nil) -> Category {
        if let eco = ruleEcosystem, let c = Category(rawValue: eco) { return c }
        switch n.kind {
        case .systemOther, .restricted: return .system
        case .otherFiles: return .file
        default: break
        }
        let ext = (n.name as NSString).pathExtension.lowercased()
        if ext == "app" || n.name == "Applications" { return .apps }
        if nodeNames.contains(n.name) { return .node }
        if appleNames.contains(n.name) || ext == "xcarchive" || ext == "simruntime" { return .apple }
        if androidNames.contains(n.name) || ext == "avd" { return .android }
        if rustNames.contains(n.name) { return .rust }
        if otherDevNames.contains(n.name) { return .otherDev }
        if mediaNames.contains(n.name) || mediaExt.contains(ext) { return .media }
        if systemNames.contains(n.name) { return .system }
        return n.kind == .file ? .file : .folder
    }

    var color: Color {
        switch self {
        case .node: Color(red: 0.25, green: 0.62, blue: 0.36)
        case .apple: Color(red: 0.20, green: 0.48, blue: 0.85)
        case .android: Color(red: 0.13, green: 0.60, blue: 0.58)
        case .rust: Color(red: 0.85, green: 0.47, blue: 0.20)
        case .otherDev: Color(red: 0.55, green: 0.45, blue: 0.78)
        case .media: Color(red: 0.80, green: 0.33, blue: 0.53)
        case .apps: Color(red: 0.36, green: 0.36, blue: 0.82)
        case .system: Color(red: 0.42, green: 0.44, blue: 0.48)
        case .folder: Color(red: 0.29, green: 0.40, blue: 0.52)
        case .file: Color(red: 0.45, green: 0.52, blue: 0.60)
        }
    }

    var label: String {
        switch self {
        case .node: "Node / JS"
        case .apple: "Xcode / iOS"
        case .android: "Android / Gradle"
        case .rust: "Rust / Dart / Go"
        case .otherDev: "Other dev"
        case .media: "Media"
        case .apps: "Apps"
        case .system: "System & other"
        case .folder: "Folder"
        case .file: "Files"
        }
    }
}

func formatBytes(_ b: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file)
}

/// "1.8 GB", or "≥ 1.8 GB" while the size is still growing.
func sizeLabel(_ n: NodeInfo) -> String {
    if n.kind == .restricted { return "unknown size" }
    return (n.state == .complete ? "" : "≥ ") + formatBytes(n.totalBytes)
}
