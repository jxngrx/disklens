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
                        Label("Runs `\(cmd.joined(separator: " "))`. Not quarantined, cannot be restored.", systemImage: "terminal")
                            .font(.caption).foregroundStyle(.orange)
                    } else {
                        Label("Moved to quarantine. Restorable for \(model.cleaner.quarantine.retentionDays) days.",
                              systemImage: "arrow.uturn.backward.circle")
                            .font(.caption).foregroundStyle(.secondary)
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
                Toggle("Untouched for 30+ days", isOn: $staleOnly).toggleStyle(.checkbox)
                    .accessibilityIdentifier("stale-filter")
            }
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
            HStack {
                Text("\(shown.count) projects · \(formatBytes(shown.reduce(0) { $0 + $1.reclaimable })) reclaimable")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Close") { model.showProjects = false }.keyboardShortcut(.cancelAction)
                Button("Clean Selected…") {
                    let nodes = shown.filter { selection.contains($0.path) }.flatMap(\.artifacts).map { model.store.node($0.id) }
                    model.showProjects = false
                    model.requestClean(nodes)
                }
                .disabled(selection.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 720, height: 480)
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

struct QuarantineView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quarantine").font(.title2.bold())
            let total = model.quarantineItems.reduce(0) { $0 + $1.bytes }
            Text("\(formatBytes(total)) is freed for good after \(model.cleaner.quarantine.retentionDays) days, or empty it now.")
                .foregroundStyle(.secondary)
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
            HStack {
                Button("Empty Now", role: .destructive) { model.emptyQuarantine() }.disabled(model.quarantineItems.isEmpty)
                Spacer()
                Button("Done") { model.showQuarantine = false }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 600, height: 420)
        .onAppear { model.reloadQuarantine() }
    }
}
