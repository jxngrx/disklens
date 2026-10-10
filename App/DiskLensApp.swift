import AppKit
import DiskLensCore
import SwiftUI

@main
struct DiskLensApp: App {
    @State private var model: AppModel

    init() {
        // `-scanRoot <path>` scans a folder instead of the whole disk (UI tests, fixtures).
        let root = UserDefaults.standard.string(forKey: "scanRoot") ?? "/"
        _model = State(initialValue: AppModel(rootPath: root))
        if CommandLine.arguments.contains("-benchmark") {
            MainActor.assumeIsolated { Benchmark.run() }
        }
    }

    var body: some Scene {
        WindowGroup("DiskLens") {
            ContentView(model: model)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Back") { model.back() }.keyboardShortcut("[", modifiers: .command)
                Button("Enclosing Folder") { model.up() }.keyboardShortcut(.upArrow, modifiers: .command)
            }
        }
        Settings { LicenseSettings() }
    }
}

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var swipeMonitor: Any?
    @State private var columns: NavigationSplitViewVisibility = .all
    @AppStorage("fdaBannerDismissed") private var fdaDismissed = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            SidebarList(model: model)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        } detail: {
            VStack(spacing: 0) {
                if model.restrictedCount > 0 && !fdaDismissed {
                    FullDiskAccessBanner(count: model.restrictedCount) { fdaDismissed = true }
                }
                BreadcrumbBar(model: model)
                Divider()
                TreemapView(model: model)
                    .padding(6)
                Divider()
                HStack {
                    LegendBar()
                    Spacer(minLength: 12)
                    Text(model.statusText).font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("scan-status")
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { model.back() } label: { Image(systemName: "chevron.left") }
                    .help("Back (Esc, ⌘[)")
                    .disabled(model.backStack.isEmpty)
                    .accessibilityIdentifier("back")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.showProjects = true } label: { Label("Projects", systemImage: "folder.badge.gearshape") }
                    .help("Projects by reclaimable size")
                    .accessibilityIdentifier("projects")
                Button { model.reloadQuarantine(); model.showQuarantine = true } label: { Label("Quarantine", systemImage: "arrow.uturn.backward.circle") }
                    .help("Cleaned items you can still restore")
                    .accessibilityIdentifier("quarantine")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let msg = model.cleanMessage {
                HStack {
                    Text(msg).accessibilityIdentifier("clean-message")
                    Spacer()
                    Button("Undo…") { model.reloadQuarantine(); model.showQuarantine = true }
                    Button { model.cleanMessage = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                }
                .padding(10)
                .background(.thickMaterial)
            }
        }
        .onChange(of: model.cleanPlan != nil || model.showProjects || model.showQuarantine || model.smallerItems != nil) { _, sheet in
            if sheet { model.hovered = nil }
        }
        .sheet(isPresented: Binding(get: { model.cleanPlan != nil }, set: { if !$0 { model.cleanPlan = nil } })) {
            CleanSheet(model: model, plan: model.cleanPlan ?? [])
        }
        .sheet(isPresented: $model.showProjects) { ProjectsView(model: model) }
        .sheet(isPresented: $model.showQuarantine) { QuarantineView(model: model) }
        .background {
            // Esc goes back.
            Button("") { model.back() }.keyboardShortcut(.cancelAction).hidden()
        }
        .sheet(isPresented: Binding(get: { model.smallerItems != nil }, set: { if !$0 { model.smallerItems = nil } })) {
            SmallerItemsSheet(model: model, items: model.smallerItems ?? [])
        }
        .confirmationDialog("Move “\(model.trashCandidate?.name ?? "")” to the Trash?",
                            isPresented: Binding(get: { model.trashCandidate != nil }, set: { if !$0 { model.trashCandidate = nil } })) {
            Button("Move to Trash", role: .destructive) {
                if let n = model.trashCandidate { model.moveToTrash(n) }
            }
        } message: {
            Text(model.trashCandidate.map { "\(model.path($0)) · \(sizeLabel($0))" } ?? "")
        }
        .onAppear {
            model.start(openPath: UserDefaults.standard.string(forKey: "openPath"))
            if CommandLine.arguments.contains("-selftest") { SelfTest.run(model) }
            // Two-finger swipe right goes back.
            swipeMonitor = NSEvent.addLocalMonitorForEvents(matching: .swipe) { e in
                if e.deltaX > 0 { MainActor.assumeIsolated { model.back() } }
                return e
            }
        }
    }
}

/// One-time banner shown when folders came back permission-denied.
struct FullDiskAccessBanner: View {
    let count: Int
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill").foregroundStyle(.orange)
            Text("\(count) folders need Full Disk Access to be sized. They show as Restricted.")
                .font(.callout)
            Spacer()
            Button("Open Full Disk Access Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
            }
            Button("Dismiss", action: dismiss).buttonStyle(.borderless)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
        .accessibilityIdentifier("fda-banner")
    }
}
