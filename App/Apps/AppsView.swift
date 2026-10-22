import DiskLensCore
import SwiftUI

/// State of the Apps tab: installed apps, the selected app's leftovers, and the uninstall run.
@MainActor @Observable
final class AppsState {
    var apps: [InstalledApp]?
    var selected: InstalledApp?
    var leftovers: [Leftover]?
    var picked = Set<String>()
    var search = ""
    var bySize = true
    var working = false
    var message: String?

    func load(_ model: AppModel, force: Bool = false) {
        guard force || apps == nil else { return }
        let store = model.store
        Task.detached(priority: .userInitiated) {
            // The scanned tree already knows bundle sizes; only measure on disk when it does not.
            let list = Apps.installed(size: { p in
                if let id = store.find(path: p) { let n = store.node(id); if n.state == .complete, n.totalBytes > 0 { return n.totalBytes } }
                return Apps.diskSize(p)
            })
            await MainActor.run {
                self.apps = list
                if let s = self.selected { self.selected = list.first { $0.id == s.id } }
            }
        }
    }

    func select(_ app: InstalledApp, model: AppModel) {
        selected = app
        leftovers = nil
        picked = []
        message = nil
        let store = model.store
        Task.detached(priority: .userInitiated) {
            // Wider search: any folder or file on the disk index named after the bundle ID.
            var extra: [String] = []
            if let b = app.bundleID?.lowercased(), b.contains("."), b.count >= 8 {
                extra = store.paths(nameMatching: { n in let l = n.lowercased(); return l == b || l.hasPrefix(b + ".") })
            }
            let left = Apps.leftovers(for: app, extra: extra)
            await MainActor.run {
                guard self.selected?.id == app.id else { return }
                self.leftovers = left
                self.picked = Set(left.map(\.path))
            }
        }
    }

    var pickedBytes: UInt64 { (selected?.bytes ?? 0) + (leftovers ?? []).filter { picked.contains($0.path) }.reduce(0) { $0 + $1.bytes } }

    func uninstall(_ model: AppModel) {
        guard let app = selected, let left = leftovers, !working else { return }
        working = true
        message = nil
        let paths = [app.path] + left.map(\.path).filter { picked.contains($0) }
        let freed = pickedBytes
        if let b = app.bundleID { NSRunningApplication.runningApplications(withBundleIdentifier: b).forEach { $0.terminate() } }
        let store = model.store
        Task.detached(priority: .userInitiated) {
            try? await Task.sleep(nanoseconds: 800_000_000)
            let out = Uninstaller.remove(paths)
            await MainActor.run {
                for p in out.removed { if let id = store.find(path: p) { store.remove(id) } }
                self.working = false
                if out.removed.contains(app.path) {
                    self.apps?.removeAll { $0.id == app.id }
                    self.selected = nil
                    self.leftovers = nil
                }
                self.message = out.failed.isEmpty
                    ? "Uninstalled \(app.name): \(out.removed.count) items, \(formatBytes(freed)) freed."
                    : "Removed \(out.removed.count) items. \(out.failed.count) could not be removed (permission or protected): "
                      + out.failed.prefix(2).map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
                model.refresh(force: true)
                model.refreshDevIndex()
            }
        }
    }
}

struct AppsView: View {
    @Bindable var model: AppModel
    @State private var confirm = false
    var state: AppsState { model.appsState }

    var body: some View {
        HSplitView {
            listPane.frame(minWidth: 420, idealWidth: 560)
            detailPane.frame(minWidth: 380, idealWidth: 460)
        }
        .task { state.load(model) }
        .accessibilityIdentifier("apps-view")
    }

    // MARK: Left: grid of apps

    var filtered: [InstalledApp] {
        let q = state.search.lowercased()
        let list = (state.apps ?? []).filter { q.isEmpty || $0.name.lowercased().contains(q) }
        return state.bySize ? list.sorted { $0.bytes > $1.bytes }
                            : list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var listPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Apps").font(.title2.bold())
                if let apps = state.apps {
                    Text("\(apps.count) · \(formatBytes(apps.reduce(0) { $0 + $1.bytes }))").foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Sort", selection: Binding(get: { state.bySize }, set: { state.bySize = $0 })) {
                    Text("Size").tag(true)
                    Text("Name").tag(false)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 110)
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search apps", text: Binding(get: { state.search }, set: { state.search = $0 })).textFieldStyle(.plain)
                if !state.search.isEmpty {
                    Button { state.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))

            if state.apps == nil {
                VStack(spacing: 12) {
                    IconLoader(size: 56)
                    Text("Finding your apps…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                Text("No apps found.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        section("User", filtered.filter(\.isUser))
                        section("Applications", filtered.filter { !$0.isUser })
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .padding(16)
    }

    @ViewBuilder func section(_ title: String, _ apps: [InstalledApp]) -> some View {
        if !apps.isEmpty {
            let maxBytes = max(1, (state.apps ?? []).map(\.bytes).max() ?? 1)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Text("\(apps.count)").font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 10)], spacing: 10) {
                    ForEach(apps) { app in
                        AppTile(app: app, maxBytes: maxBytes, selected: state.selected?.id == app.id)
                            .onTapGesture { state.select(app, model: model) }
                            .accessibilityIdentifier("app-\(app.name)")
                    }
                }
            }
        }
    }

    // MARK: Right: disk card or selected app

    @ViewBuilder var detailPane: some View {
        if let app = state.selected {
            appDetail(app)
        } else {
            VStack(spacing: 24) {
                Spacer()
                DiskCard()
                if let m = state.message { Text(m).font(.callout).foregroundStyle(.green).multilineTextAlignment(.center).padding(.horizontal) }
                Spacer()
                Text("Select an app to see everything it leaves on your Mac")
                    .font(.caption).foregroundStyle(.secondary).padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity)
        }
    }

    func appDetail(_ app: InstalledApp) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.title2.bold())
                    Text([app.version.map { "v\($0)" }, app.bundleID].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                    Text((app.path as NSString).abbreviatingWithTildeInPath).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Text(formatBytes(app.bytes)).font(.title3.bold().monospacedDigit())
            }
            Divider()
            if let left = state.leftovers {
                HStack {
                    Text("App and \(left.count) related \(left.count == 1 ? "item" : "items")").font(.headline)
                    Spacer()
                    if !left.isEmpty {
                        Button(state.picked.count == left.count ? "Deselect all" : "Select all") {
                            state.picked = state.picked.count == left.count ? [] : Set(left.map(\.path))
                        }.buttonStyle(.link)
                    }
                }
                List {
                    HStack {
                        Image(systemName: "app.fill").foregroundStyle(.blue)
                        VStack(alignment: .leading) { Text("\(app.name).app").fontWeight(.medium); Text("The app itself").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Text(formatBytes(app.bytes)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    ForEach(left) { l in
                        HStack {
                            Toggle("", isOn: Binding(get: { state.picked.contains(l.path) },
                                                     set: { if $0 { state.picked.insert(l.path) } else { state.picked.remove(l.path) } }))
                                .labelsHidden()
                            VStack(alignment: .leading, spacing: 1) {
                                Text((l.path as NSString).lastPathComponent).fontWeight(.medium).lineLimit(1)
                                Text((l.path as NSString).abbreviatingWithTildeInPath).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            Text(formatBytes(l.bytes)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.inset)
            } else {
                VStack(spacing: 12) {
                    IconLoader(size: 48)
                    Text("Searching everywhere for \(app.name) files…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let m = state.message { Text(m).font(.callout).foregroundStyle(.orange) }
            HStack {
                Text("\(formatBytes(state.pickedBytes)) will be freed").foregroundStyle(.secondary)
                Spacer()
                if state.working { ProgressView().controlSize(.small) }
                Button("Uninstall Completely…", role: .destructive) { confirm = true }
                    .buttonStyle(.borderedProminent).tint(.red)
                    .disabled(state.leftovers == nil || state.working)
                    .accessibilityIdentifier("uninstall")
            }
        }
        .padding(16)
        .confirmationDialog("Uninstall \(app.name)?", isPresented: $confirm) {
            Button("Uninstall and delete \(state.picked.count + 1) items (\(formatBytes(state.pickedBytes)))", role: .destructive) {
                state.uninstall(model)
            }
        } message: {
            Text("The app and the selected files are permanently deleted. Protected items will ask for your admin password.")
        }
    }
}

struct AppTile: View {
    let app: InstalledApp
    let maxBytes: UInt64
    let selected: Bool

    var body: some View {
        VStack(spacing: 5) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 48, height: 48)
            Text(app.name).font(.system(size: 12, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
            Text(formatBytes(app.bytes)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            GeometryReader { g in
                Capsule().fill(.quaternary)
                    .overlay(alignment: .leading) {
                        Capsule().fill(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(3, g.size.width * CGFloat(Double(app.bytes) / Double(maxBytes))))
                    }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 8).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(selected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Color.accentColor : .clear, lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// Startup volume summary: name, free space, purgeable and how full it is.
struct DiskCard: View {
    @State private var info: (name: String, total: Int, avail: Int, important: Int)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: "internaldrive.fill").font(.system(size: 40)).foregroundStyle(.secondary)
                if let i = info {
                    let used = i.total - i.avail
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(i.name).font(.title3.bold())
                            Spacer()
                            Text("\(Int(Double(used) / Double(max(i.total, 1)) * 100))% full").font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Available: \(formatBytes(UInt64(i.avail)))").font(.caption)
                        Text("Purgeable: \(formatBytes(UInt64(max(0, i.important - i.avail))))").font(.caption)
                    }
                }
            }
            if let i = info {
                let used = i.total - i.avail
                HStack {
                    Text(formatBytes(UInt64(used))).font(.caption2).foregroundStyle(.secondary)
                    ProgressView(value: Double(used), total: Double(max(i.total, 1)))
                    Text(formatBytes(UInt64(i.total))).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .frame(width: 380)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        .onAppear {
            let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
            if let v { info = (v.volumeName ?? "Macintosh HD", v.volumeTotalCapacity ?? 0, v.volumeAvailableCapacity ?? 0,
                               Int(v.volumeAvailableCapacityForImportantUsage ?? 0)) }
        }
    }
}
