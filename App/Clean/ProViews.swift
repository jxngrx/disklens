import Charts
import DiskLensCore
import ServiceManagement
import SwiftUI
import UserNotifications

/// Mobile pack: AVDs, system images, NDKs, simulator runtimes, unavailable simulators.
struct MobilePackView: View {
    @Bindable var model: AppModel
    @State private var items: [MobileItem]?
    @State private var confirm: MobileItem?
    @State private var log: [String] = []
    @AppStorage("boxesMode") private var boxesMode = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Mobile pack").font(.title2.bold())
                Spacer()
                ViewModePicker()
                if !License.proEnabled { Text("PRO").font(.caption.bold()).padding(4).background(.orange, in: Capsule()) }
            }
            Text("Items in use by an AVD, a project or a simulator are not offered for cleaning.")
                .foregroundStyle(.secondary)
            if let items, boxesMode {
                BoxesView(items: items.map { i in
                    BoxItem(id: i.id, title: i.name, subtitle: i.inUse ? "in use" : "", bytes: i.bytes,
                            color: (i.kind == .simRuntime || i.kind == .unavailableSimulators ? Category.apple : .android).color,
                            path: i.path, clean: i.inUse || !License.proEnabled ? nil : { confirm = i })
                })
            } else if let items {
                List {
                    ForEach([MobileItem.Kind.avd, .systemImage, .ndk, .simRuntime, .unavailableSimulators], id: \.self) { kind in
                        let group = items.filter { $0.kind == kind }
                        if !group.isEmpty {
                            Section(Self.title(kind)) {
                                ForEach(group) { i in row(i) }
                            }
                        }
                    }
                }
                .overlay { if items.isEmpty { Text("No Android SDK or simulator data found.").foregroundStyle(.secondary) } }
            } else {
                ProgressView("Reading Android SDK and simulators…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            ForEach(log, id: \.self) { Text($0).font(.caption.monospaced()).foregroundStyle(.secondary) }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            let projects = Projects.collect(store: model.store, rules: model.rules).map(\.path)
            items = await Task.detached { MobilePack(projectPaths: projects).items() }.value
        }
        .alert("Run \(confirm?.command.joined(separator: " ") ?? "")?", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            Button("Run", role: .destructive) {
                if let c = confirm {
                    let r = model.cleaner.runner.run(c.command)
                    log.append((r.ok ? "ok: " : "failed: ") + (model.cleaner.runner.log.last ?? ""))
                    items?.removeAll { $0.id == c.id }
                }
            }
        } message: {
            Text("This uses the tool's own command. It cannot be undone or quarantined.")
        }
    }

    static func title(_ k: MobileItem.Kind) -> String {
        switch k {
        case .avd: "Android emulators (AVDs)"
        case .systemImage: "Android system images"
        case .ndk: "Android NDKs"
        case .simRuntime: "Simulator runtimes"
        case .unavailableSimulators: "Unavailable simulators"
        }
    }

    func row(_ i: MobileItem) -> some View {
        HStack {
            VStack(alignment: .leading) {
                HStack { Text(i.name).fontWeight(.medium); SafetyBadge(safety: i.safety) }
                Text(i.inUse ? "In use by \(i.usedBy.joined(separator: ", "))"
                     : i.kind == .avd ? "Emulator disk and its data" : "No AVD, project or simulator uses it")
                    .font(.caption).foregroundStyle(i.inUse ? .orange : .secondary)
            }
            Spacer()
            Text(formatBytes(i.bytes)).monospacedDigit()
            Button("Remove…") { confirm = i }.disabled(i.inUse || !License.proEnabled)
        }
    }
}

/// Disk growth timeline from `history.jsonl`.
struct GrowthView: View {
    @Bindable var model: AppModel
    // `-historyFile` points at another file (screenshots, fixtures).
    let samples = History.load(from: UserDefaults.standard.string(forKey: "historyFile").map { URL(fileURLWithPath: $0) } ?? History.defaultURL)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Disk growth").font(.title2.bold())
            if samples.count < 2 {
                Text("DiskLens records used space after each scan (at most hourly). The chart fills in over time.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(samples) { s in
                    LineMark(x: .value("Date", s.date), y: .value("Used GB", Double(s.usedBytes) / 1e9))
                        .foregroundStyle(by: .value("Series", "Used"))
                    LineMark(x: .value("Date", s.date), y: .value("Free GB", Double(s.freeBytes) / 1e9))
                        .foregroundStyle(by: .value("Series", "Free"))
                }
                .chartYAxisLabel("GB")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Menu bar free-space display with a low-disk alert.
@MainActor @Observable
final class DiskStatus {
    var freeBytes: UInt64 = 0
    var alerted = false
    @ObservationIgnored @AppStorage("lowDiskGB") var lowDiskGB = 10.0
    private var timer: Timer?

    init() {
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in MainActor.assumeIsolated { self.update() } }
    }

    func update() {
        let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        freeBytes = UInt64(max(0, v?.volumeAvailableCapacityForImportantUsage ?? 0))
        let low = Double(freeBytes) < lowDiskGB * 1e9
        if low && !alerted { notifyLowDisk() }
        alerted = low
    }

    func notifyLowDisk() {
        let center = UNUserNotificationCenter.current()
        let free = formatBytes(freeBytes)
        // async API: the callback form ran a @MainActor-inferred closure on the notification queue and trapped.
        Task {
            guard (try? await center.requestAuthorization(options: [.alert])) == true else { return }
            let c = UNMutableNotificationContent()
            c.title = "Disk almost full"
            c.body = "\(free) free. Open DiskLens to see what is cleanable."
            try? await center.add(UNNotificationRequest(identifier: "low-disk", content: c, trigger: nil))
        }
    }
}

struct MenuBarContent: View {
    let status: DiskStatus
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("\(formatBytes(status.freeBytes)) free on Macintosh HD")
        let cleanable = model.store.ruleTaggedNodes().reduce(UInt64(0)) { $0 + $1.totalBytes }
        if cleanable > 0 { Text("Up to \(formatBytes(cleanable)) cleanable") }
        Divider()
        Button("Open DiskLens") { NSApp.activate(ignoringOtherApps: true); openWindow(id: "main") }
        Menu("Alert when free space is below") {
            ForEach([5.0, 10, 20, 50], id: \.self) { gb in
                Button("\(Int(gb)) GB\(status.lowDiskGB == gb ? " ✓" : "")") { status.lowDiskGB = gb; status.update() }
            }
        }
        Divider()
        Button("Quit DiskLens") { NSApp.terminate(nil) }
    }
}

struct BackgroundSettings: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    @State private var error = ""

    var body: some View {
        Form {
            Toggle("Open at login to keep the index fresh (menu bar only)", isOn: $enabled)
                .onChange(of: enabled) { _, on in
                    do { try on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister(); error = "" }
                    catch { self.error = error.localizedDescription }
                }
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
        }
        .padding(20)
        .frame(width: 420)
    }
}
