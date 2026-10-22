import DiskLensCore
import SwiftUI

/// Confirm sheet: what will be cleaned, how, and whether it can be undone.
struct CleanSheet: View {
    @Bindable var model: AppModel
    let plan: [CleanItem]

    var total: UInt64 { plan.reduce(0) { $0 + $1.bytes } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Clean \(plan.count == 1 ? "“\((plan[0].path as NSString).lastPathComponent)”" : "\(plan.count) items")?").font(.title2.bold())
                .accessibilityIdentifier("clean-title")
            ForEach(model.cleanRunningTools, id: \.self) { tool in
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("\(tool) is running. Quit it first so it does not recreate or lock these files.")
                    Spacer()
                    Button("Quit \(tool)") { model.quitTool(tool) }
                }
                .padding(8)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
            List(plan) { item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text((item.path as NSString).lastPathComponent).fontWeight(.semibold)
                        SafetyBadge(safety: item.rule.safety)
                        Spacer()
                        Text(formatBytes(item.bytes)).monospacedDigit()
                    }
                    Text(item.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    if let cmd = item.command {
                        Label("Runs `\(cmd.joined(separator: " "))`. Cannot be restored.", systemImage: "terminal")
                            .font(.caption).foregroundStyle(.orange)
                    } else {
                        Label("Deleted permanently. Cannot be restored.", systemImage: "trash")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if let note = item.rule.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                }
                .padding(.vertical, 2)
                .accessibilityIdentifier("clean-item-\((item.path as NSString).lastPathComponent)")
            }
            .frame(minHeight: 160)
            if model.cleaner.runner.dryRun {
                Text("Dry run: tool commands are only logged.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("Total: \(formatBytes(total))").font(.headline).accessibilityIdentifier("clean-total")
                Spacer()
                Button("Cancel") { model.cleanPlan = nil }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("clean-cancel")
                Button("Clean \(formatBytes(total))") { model.performClean() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("clean-confirm")
            }
        }
        .padding(20)
        .frame(width: 560, height: 440)
    }
}

struct SafetyBadge: View {
    let safety: Safety
    var body: some View {
        Text(safety.label.uppercased())
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(TreemapRenderer.badgeColor(safety), in: Capsule())
    }
}

/// Projects by reclaimable size with "last worked on"; default filter: untouched for 30+ days.
struct ProjectsView: View {
    @Bindable var model: AppModel
    @State private var projects: [ProjectInfo] = []
    @State private var lastWorked: [String: Date] = [:]
    @State private var staleOnly = true
    @State private var selection = Set<String>()
    @AppStorage("boxesMode") private var boxesMode = true

    var shown: [ProjectInfo] {
        guard staleOnly else { return projects }
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        return projects.filter { p in lastWorked[p.path].map { $0 < cutoff } ?? false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Projects").font(.title2.bold())
                Spacer()
                ViewModePicker()
                Toggle("Untouched for 30+ days", isOn: $staleOnly).toggleStyle(.checkbox)
                    .accessibilityIdentifier("stale-filter")
            }
            if boxesMode {
                BoxesView(items: shown.map { p in
                    BoxItem(id: p.path, title: p.name, subtitle: "", bytes: p.reclaimable, color: .orange, path: p.path,
                            clean: { model.requestClean(p.artifacts.map { model.store.node($0.id) }) })
                })
            } else {
            Table(shown, selection: $selection) {
                TableColumn("Project") { p in
                    VStack(alignment: .leading) {
                        Text(p.name).fontWeight(.medium)
                        Text(p.artifacts.map { String($0.path.dropFirst(p.path.count + 1)) }.sorted().joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                TableColumn("Reclaimable") { p in Text(formatBytes(p.reclaimable)).monospacedDigit() }.width(100)
                TableColumn("Last worked on") { p in
                    Text(lastWorked[p.path].map { $0.formatted(.relative(presentation: .named)) } ?? "…")
                }.width(130)
            }
            }
            HStack {
                Text("\(shown.count) projects · \(formatBytes(shown.reduce(0) { $0 + $1.reclaimable })) reclaimable")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clean Selected…") {
                    let nodes = shown.filter { selection.contains($0.path) }.flatMap(\.artifacts).map { model.store.node($0.id) }
                                        model.requestClean(nodes)
                }
                .disabled(selection.isEmpty)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            projects = Projects.collect(store: model.store, rules: model.rules)
            let rules = model.rules
            for p in projects {
                let path = p.path
                let d = await Task.detached { Projects.lastWorkedOn(path, rules: rules) }.value
                lastWorked[path] = d ?? .distantPast
            }
        }
    }
}

/// Every known dev-tool cache (DerivedData, Gradle, npm, CocoaPods, Homebrew, Docker, …) on one
/// screen, grouped by tool, so a developer doesn't have to hunt each one down by hand.
struct DeveloperGroup: Identifiable, Sendable {
    var rule: Rule
    var nodes: [NodeInfo]
    var id: UInt16 { rule.id }
    var total: UInt64 { nodes.reduce(0) { $0 + $1.totalBytes } }
}

struct DeveloperView: View {
    @Bindable var model: AppModel
    @State private var expanded = Set<String>()
    @AppStorage("boxesMode") private var boxesMode = true

    var boxItems: [BoxItem] {
        let projects = projectGroups.map { p in
            BoxItem(id: "p:" + p.path, title: p.name, subtitle: "\(p.artifacts.count) cleanable", bytes: p.reclaimable,
                    color: .orange, path: p.path,
                    clean: { model.requestClean(p.artifacts.map { model.store.node($0.id) }) })
        }
        let tools = toolGroups.map { g in
            BoxItem(id: "t:\(g.id)", title: g.rule.name, subtitle: "\(g.nodes.count) items", bytes: g.total,
                    color: (Category(rawValue: g.rule.ecosystem) ?? .folder).color, path: g.nodes.first.map { model.path($0) },
                    clean: { model.requestClean(g.nodes) })
        }
        return projects + tools
    }

    var toolGroups: [DeveloperGroup] { model.devIndex?.tools ?? [] }
    var projectGroups: [ProjectInfo] { model.devIndex?.projects ?? [] }

    var grandTotal: UInt64 {
        toolGroups.reduce(0) { $0 + $1.total } + projectGroups.reduce(0) { $0 + $1.reclaimable }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Developer").font(.title2.bold())
                    Text("Every tool cache DiskLens knows about, one screen, nothing to dig for.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ViewModePicker()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(formatBytes(grandTotal)).font(.title2.bold().monospacedDigit())
                    Text("reclaimable").font(.caption).foregroundStyle(.secondary)
                }
            }
            if model.devIndex == nil {
                VStack(spacing: 12) {
                    IconLoader(size: 56)
                    Text("Tracing developer caches…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("developer-loading")
            } else if toolGroups.isEmpty, projectGroups.isEmpty {
                Text("Nothing cleanable found yet. The scan may still be running.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if boxesMode {
                BoxesView(items: boxItems)
            } else {
                List {
                    if !projectGroups.isEmpty {
                        Section("Projects") {
                            treeRows(PathNode.build(projectGroups.map { ($0.path, $0, nil) }), scope: "proj")
                        }
                    }
                    Section("Tools & caches") {
                        ForEach(toolGroups) { g in toolRow(g) }
                    }
                }
                .listStyle(.inset)
            }
            HStack {
                let itemCount = toolGroups.reduce(0) { $0 + $1.nodes.count } + projectGroups.reduce(0) { $0 + $1.artifacts.count }
                Text("\(itemCount) items · \(projectGroups.count) projects · \(toolGroups.count) tools")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("developer-view")
        .task { model.refreshDevIndex() }
    }

    func open(_ id: String) -> Binding<Bool> {
        Binding(get: { expanded.contains(id) },
                set: { if $0 { expanded.insert(id) } else { expanded.remove(id) } })
    }

    func treeRows(_ ns: [PathNode], scope: String) -> AnyView {
        AnyView(ForEach(ns) { n in treeRow(n, scope: scope) })
    }

    func cleanables(_ n: PathNode) -> [NodeInfo] {
        (n.node.map { [$0] } ?? []) + (n.project?.artifacts.map { model.store.node($0.id) } ?? [])
            + n.children.flatMap(cleanables)
    }

    func treeRow(_ n: PathNode, scope: String) -> AnyView {
        if n.children.isEmpty {
            if let p = n.project { return AnyView(projectRow(p, title: n.name)) }
            if let node = n.node { return AnyView(row(node, title: n.name)) }
        }
        let all = cleanables(n)
        let total = all.reduce(0) { $0 + $1.totalBytes }
        let key = scope + ":" + n.path
        return AnyView(DisclosureGroup(isExpanded: open(key)) {
            if let p = n.project { projectArtifacts(p) }
            if let node = n.node { row(node, title: node.name) }
            treeRows(n.children, scope: scope)
        } label: {
            HStack {
                Image(systemName: n.project == nil ? "folder" : "folder.fill")
                    .foregroundStyle(n.project == nil ? Color.secondary : Color.orange)
                Text(n.name).fontWeight(n.project == nil ? .regular : .semibold).lineLimit(1).truncationMode(.middle)
                Text("\(all.count) cleanable").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(formatBytes(total)).monospacedDigit()
                Button("Clean All") { model.requestClean(all) }.controlSize(.small)
            }
        })
    }

    func toolRow(_ g: DeveloperGroup) -> some View {
        DisclosureGroup(isExpanded: open("tool:\(g.id)")) {
            treeRows(PathNode.build(g.nodes.map { (model.path($0), nil, $0) }), scope: "tool:\(g.id)")
        } label: {
            HStack {
                Image(systemName: Self.icon(for: g.rule.ecosystem)).foregroundStyle(.blue)
                Text(g.rule.name).fontWeight(.semibold)
                SafetyBadge(safety: g.rule.safety)
                if let note = g.rule.note { Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                Spacer()
                Text("\(g.nodes.count) · \(formatBytes(g.total))").monospacedDigit()
                Button("Clean All") { model.requestClean(g.nodes) }.controlSize(.small)
            }
        }
    }

    func projectArtifacts(_ p: ProjectInfo) -> some View {
        ForEach(p.artifacts) { a in
            HStack {
                Text(String(a.path.dropFirst(p.path.count + 1))).font(.callout)
                Spacer()
                Text(formatBytes(a.bytes)).monospacedDigit().foregroundStyle(.secondary)
                Button { model.requestClean([model.store.node(a.id)]) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Clean just this one")
            }
        }
    }

    func projectRow(_ p: ProjectInfo, title: String) -> some View {
        DisclosureGroup(isExpanded: open("projrow:" + p.path)) {
            projectArtifacts(p)
        } label: {
            HStack {
                Image(systemName: "folder.fill").foregroundStyle(.orange)
                Text(title).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
                Text("\(p.artifacts.count) cleanable").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(formatBytes(p.reclaimable)).monospacedDigit()
                Button("Clean All") { model.requestClean(p.artifacts.map { model.store.node($0.id) }) }
                    .controlSize(.small)
            }
        }
        .accessibilityIdentifier("developer-project-\(p.name)")
    }

    func row(_ n: NodeInfo, title: String) -> some View {
        HStack {
            Text(title).fontWeight(.medium).lineLimit(1).truncationMode(.middle)
            Spacer()
            Text(sizeLabel(n)).monospacedDigit().foregroundStyle(.secondary)
            Button { model.requestClean([n]) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Clean just this one")
        }
    }

    static func icon(for ecosystem: String) -> String {
        switch ecosystem {
        case "apple": "hammer.fill"
        case "android": "shippingbox.fill"
        case "node": "cube.fill"
        case "otherDev": "wrench.and.screwdriver.fill"
        default: "folder.fill"
        }
    }
}

struct QuarantineView: View {
    @Bindable var model: AppModel
    @AppStorage("boxesMode") private var boxesMode = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("Quarantine").font(.title2.bold()); Spacer(); ViewModePicker() }
            let total = model.quarantineItems.reduce(0) { $0 + $1.bytes }
            Text("\(formatBytes(total)) is freed for good after \(model.cleaner.quarantine.retentionDays) days, or empty it now.")
                .foregroundStyle(.secondary)
            if boxesMode {
                BoxesView(items: model.quarantineItems.map { i in
                    BoxItem(id: i.id.uuidString, title: (i.originalPath as NSString).lastPathComponent, subtitle: "", bytes: i.bytes,
                            color: Category.system.color, path: nil, clean: nil)
                })
            } else {
            List(model.quarantineItems) { item in
                HStack {
                    VStack(alignment: .leading) {
                        Text((item.originalPath as NSString).lastPathComponent).fontWeight(.medium)
                        Text(item.originalPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Text("Cleaned \(item.date.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(formatBytes(item.bytes)).monospacedDigit()
                    // Pro: one-button reinstall from the project's lockfile.
                    if item.ruleID == model.rules.artifactRule.id,
                       let project = model.rules.projectOwning(artifact: item.originalPath) ?? Optional((item.originalPath as NSString).deletingLastPathComponent),
                       let cmd = Projects.restoreCommand(project) {
                        Button(cmd.joined(separator: " ")) { model.reinstall(project: project) }
                            .help("Reinstall dependencies from the lockfile instead of restoring the old copy")
                            .disabled(!License.proEnabled)
                    }
                    Button("Restore") { model.restore(item) }.accessibilityIdentifier("restore-\((item.originalPath as NSString).lastPathComponent)")
                }
            }
            .overlay { if model.quarantineItems.isEmpty { Text("Nothing in quarantine.").foregroundStyle(.secondary) } }
            }
            HStack {
                Button("Empty Now", role: .destructive) { model.emptyQuarantine() }.disabled(model.quarantineItems.isEmpty)
                Spacer()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { model.reloadQuarantine() }
    }
}

/// App-icon-shaped spinner: the ring with a rotating wedge.
struct IconLoader: View {
    var size: CGFloat = 44
    @State private var spin = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(LinearGradient(colors: [Color(red: 0.20, green: 0.47, blue: 0.95), Color(red: 0.09, green: 0.22, blue: 0.55)],
                                     startPoint: .top, endPoint: .bottom))
            Circle().stroke(.white.opacity(0.95), lineWidth: size * 0.075).frame(width: size * 0.6, height: size * 0.6)
            Wedge().fill(.white).frame(width: size * 0.6, height: size * 0.6)
                .rotationEffect(.degrees(spin ? 360 : 0))
        }
        .frame(width: size, height: size)
        .onAppear { withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { spin = true } }
    }
}

private struct Wedge: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY)
        p.move(to: c)
        p.addArc(center: c, radius: r.width / 2, startAngle: .degrees(-70), endAngle: .degrees(5), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// One tile in a `BoxesView`.
struct BoxItem: Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var bytes: UInt64
    var color: Color
    var path: String?
    var clean: (() -> Void)?
}

/// Treemap-style boxes for any list of sized items (Projects, Developer, Mobile, Quarantine), same
/// squarified layout as the main map. Click reveals in Finder; right-click offers Clean.
struct BoxesView: View {
    let items: [BoxItem]

    var body: some View {
        GeometryReader { geo in
            let sorted = items.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
            let rects = Squarify.layout(sizes: sorted.map { Double($0.bytes) }, in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(rects.enumerated()), id: \.offset) { _, r in
                    let box = r.rect.insetBy(dx: 1.5, dy: 1.5)
                    if let i = r.index { tile(sorted[i], box) } else { merged(r, sorted, box) }
                }
            }
        }
        .overlay { if items.allSatisfy({ $0.bytes == 0 }) { Text("Nothing to show.").foregroundStyle(.secondary) } }
    }

    func tile(_ item: BoxItem, _ r: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [item.color.opacity(0.95), item.color.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if r.width > 46, r.height > 18 {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    if r.height > 36 { Text("\(formatBytes(item.bytes))\(item.subtitle.isEmpty ? "" : " · " + item.subtitle)").font(.system(size: 11)).opacity(0.85).lineLimit(1) }
                }
                .foregroundStyle(.white).padding(6)
            }
        }
        .frame(width: max(r.width, 0), height: max(r.height, 0))
        .offset(x: r.minX, y: r.minY)
        .contentShape(Rectangle())
        .onTapGesture { if let p = item.path { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) } }
        .contextMenu {
            if let c = item.clean { Button("Clean…", action: c) }
            if let p = item.path { Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) } }
        }
        .help("\(item.title) · \(formatBytes(item.bytes))\(item.path.map { "\n" + ($0 as NSString).abbreviatingWithTildeInPath } ?? "")")
    }

    func merged(_ r: TreemapRect, _ sorted: [BoxItem], _ box: CGRect) -> some View {
        let total = r.merged.reduce(UInt64(0)) { $0 + sorted[$1].bytes }
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.55))
            if box.width > 46, box.height > 18 {
                Text("\(r.merged.count) smaller · \(formatBytes(total))").font(.system(size: 11)).foregroundStyle(.white).padding(6).lineLimit(1)
            }
        }
        .frame(width: max(box.width, 0), height: max(box.height, 0))
        .offset(x: box.minX, y: box.minY)
    }
}

/// List | Boxes switch shared by every tab (remembered).
struct ViewModePicker: View {
    @AppStorage("boxesMode") private var boxes = true
    var body: some View {
        Picker("View", selection: $boxes) {
            Label("List", systemImage: "list.bullet").tag(false)
            Label("Boxes", systemImage: "square.grid.2x2").tag(true)
        }
        .pickerStyle(.segmented).labelsHidden().frame(width: 120)
        .help("Show as a list or as boxes")
    }
}
