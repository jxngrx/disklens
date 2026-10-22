import DiskLensCore
import SwiftUI

struct BreadcrumbBar: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.crumbs.enumerated()), id: \.element.id) { i, c in
                if i > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                Button(c.name) { model.jump(to: c.id) }
                    .buttonStyle(.plain)
                    .fontWeight(i == model.crumbs.count - 1 ? .semibold : .regular)
                    .foregroundStyle(i == model.crumbs.count - 1 ? .primary : .secondary)
                    .accessibilityIdentifier("crumb-\(c.name)")
            }
            Spacer()
            if let n = model.crumbs.last {
                Text(sizeLabel(n)).monospacedDigit().foregroundStyle(.secondary)
                    .accessibilityIdentifier("current-size")
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// Same children as the treemap, sorted by size, for keyboard and accessibility users.
struct SidebarList: View {
    @Bindable var model: AppModel

    var body: some View {
        List {
            Section {
                ForEach(AppTab.allCases) { t in
                    Button { model.tab = t; if t == .quarantine { model.reloadQuarantine() } } label: {
                        Label(t.title, systemImage: t.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(model.tab == t ? Color.accentColor.opacity(0.25) : nil)
                    .accessibilityIdentifier("tab-\(t.rawValue)")
                }
            }
            if model.tab == .files {
            Section("Folders") {
            ForEach(model.children.filter { $0.totalBytes > 0 || $0.kind == .restricted }) { n in
                Button { if n.isDirectory { model.open(n.id) } } label: {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3).fill(Category.of(n).color).frame(width: 10, height: 10)
                        Text(n.name).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(sizeLabel(n)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(model.hovered?.node?.id == n.id ? Color.accentColor.opacity(0.2) : nil)
                .accessibilityIdentifier("row-\(n.name)")
            }
            }
            }
        }
        .listStyle(.sidebar)
    }
}

struct SmallerItemsSheet: View {
    let model: AppModel
    let items: [NodeInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(items.count) smaller items").font(.headline).padding()
            List(items) { n in
                Button {
                    model.smallerItems = nil
                    if n.isDirectory { model.open(n.id) }
                } label: {
                    HStack {
                        Text(n.name).lineLimit(1)
                        Spacer()
                        Text(sizeLabel(n)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            HStack { Spacer(); Button("Done") { model.smallerItems = nil }.keyboardShortcut(.defaultAction) }.padding()
        }
        .frame(width: 460, height: 420)
    }
}

struct LegendBar: View {
    static let shown: [Category] = [.node, .apple, .android, .rust, .otherDev, .media, .apps, .system, .folder]

    var body: some View {
        // Full labels when they fit, colour dots with tooltips otherwise.
        ViewThatFits(in: .horizontal) {
            row(labels: true)
            row(labels: false)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    func row(labels: Bool) -> some View {
        HStack(spacing: labels ? 12 : 6) {
            ForEach(Self.shown, id: \.self) { c in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(c.color).frame(width: 9, height: 9)
                    if labels { Text(c.label).fixedSize() }
                }
                .help(c.label)
            }
        }
    }
}
