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
    }
}

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var swipeMonitor: Any?

    var body: some View {
        NavigationSplitView {
            SidebarList(model: model)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        } detail: {
            VStack(spacing: 0) {
                BreadcrumbBar(model: model)
                Divider()
                TreemapView(model: model)
                    .padding(6)
                Divider()
                HStack {
                    LegendBar()
                    Spacer(minLength: 12)
                    Text(model.scanning ? "Scanning…" : "Scan complete").font(.caption).foregroundStyle(.secondary)
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
        }
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
