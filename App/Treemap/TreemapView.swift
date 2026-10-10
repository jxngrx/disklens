import DiskLensCore
import SwiftUI

/// Draws all boxes in one `Canvas`. Hit testing uses the model's flat `boxes` array.
struct TreemapView: View {
    @Bindable var model: AppModel

    var body: some View {
        GeometryReader { geo in
            let animating = model.zoom != nil || model.resizing || model.boxes.contains { $0.node.map { $0.state != .complete } ?? false }
            TimelineView(.animation(minimumInterval: 1 / 60, paused: !animating)) { tl in
                Canvas(rendersAsynchronously: false) { ctx, size in
                    TreemapRenderer.draw(&ctx, size: size, boxes: model.boxes, hovered: model.hovered?.id,
                                         zoom: model.zoom, now: tl.date, layoutAt: model.layoutAt)
                }
                .onChange(of: tl.date) {
                    if let z = model.zoom, tl.date.timeIntervalSince(z.start) > Zoom.duration { model.zoom = nil }
                    if model.resizing, tl.date.timeIntervalSince(model.layoutAt) > TreemapRenderer.resizeDuration { model.resizing = false }
                }
            }
            .onAppear { model.canvasSize = geo.size }
            .onChange(of: geo.size) { model.canvasSize = geo.size }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let p):
                model.hoverPoint = p
                let b = model.box(at: p)
                if b?.id != model.hovered?.id {
                    model.hovered = b
                    if let n = b?.node { model.loadGitDate(n) }
                }
            case .ended:
                model.hovered = nil
            }
        }
        .onTapGesture { p in
            if let b = model.box(at: p) { model.activate(b) }
        }
        .contextMenu { TreemapContextMenu(model: model) }
        .overlay(alignment: .topLeading) { Tooltip(model: model) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("treemap")
        .accessibilityLabel("Treemap of \(model.crumbs.last?.name ?? "")")
        .accessibilityValue(model.boxes.compactMap { $0.node?.name }.prefix(20).joined(separator: ", "))
    }
}

enum TreemapRenderer {
    static let gap: CGFloat = 2
    static let radius: CGFloat = 6

    static let resizeDuration = 0.2

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, boxes: [Box], hovered: Int32?, zoom: Zoom?, now: Date,
                     layoutAt: Date = .distantPast) {
        let bounds = CGRect(origin: .zero, size: size)
        if let z = zoom {
            let t = min(1, max(0, now.timeIntervalSince(z.start) / Zoom.duration))
            let e = 1 - pow(1 - t, 3) // ease-out cubic
            let r = CGRect(x: z.from.minX * (1 - e), y: z.from.minY * (1 - e),
                           width: z.from.width + (bounds.width - z.from.width) * e,
                           height: z.from.height + (bounds.height - z.from.height) * e)
            ctx.translateBy(x: r.minX, y: r.minY)
            ctx.scaleBy(x: r.width / max(bounds.width, 1), y: r.height / max(bounds.height, 1))
            ctx.opacity = 0.35 + 0.65 * e
        }
        let phase = now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6

        // Size changes between layouts ease from the old rect to the new one.
        let k = min(1, max(0, now.timeIntervalSince(layoutAt) / resizeDuration))
        let ease = 1 - pow(1 - k, 2)

        for box in boxes {
            var full = box.rect
            if let f = box.from, ease < 1 {
                full = CGRect(x: f.minX + (full.minX - f.minX) * ease, y: f.minY + (full.minY - f.minY) * ease,
                              width: f.width + (full.width - f.width) * ease, height: f.height + (full.height - f.height) * ease)
            }
            let r = full.insetBy(dx: gap / 2, dy: gap / 2)
            guard r.width > 0.5, r.height > 0.5 else { continue }
            let corner = min(radius, min(r.width, r.height) / 3)
            let shape = Path(roundedRect: r, cornerRadius: corner)
            var color = box.category.color
            if box.node == nil { color = Color.gray.opacity(0.55) }
            if box.node?.kind == .restricted { color = Color(red: 0.35, green: 0.30, blue: 0.30) }
            ctx.fill(shape, with: .linearGradient(Gradient(colors: [color.opacity(0.95), color.opacity(0.78)]),
                                                  startPoint: r.origin, endPoint: CGPoint(x: r.maxX, y: r.maxY)))
            if box.node?.kind == .restricted {
                ctx.stroke(shape, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }

            // Faint second level.
            for p in box.preview {
                let pr = Path(roundedRect: p.rect.insetBy(dx: 1, dy: 1), cornerRadius: 3)
                if p.category != box.category { ctx.fill(pr, with: .color(p.category.color.opacity(0.45))) }
                ctx.stroke(pr, with: .color(.white.opacity(0.16)), lineWidth: 1)
            }

            // Shimmer while the size is partial.
            if let n = box.node, n.state != .complete, n.isDirectory {
                let x = r.minX - r.width + CGFloat(phase) * r.width * 3
                ctx.drawLayer { l in
                    l.clip(to: shape)
                    l.fill(Path(r), with: .linearGradient(
                        Gradient(colors: [.clear, .white.opacity(0.18), .clear]),
                        startPoint: CGPoint(x: x, y: r.minY), endPoint: CGPoint(x: x + r.width, y: r.maxY)))
                }
            }

            if box.id == hovered {
                ctx.stroke(shape, with: .color(.white.opacity(0.9)), lineWidth: 2)
            }
            drawLabel(&ctx, box: box, rect: r)
        }
    }

    static func drawLabel(_ ctx: inout GraphicsContext, box: Box, rect r: CGRect) {
        guard r.width >= 46, r.height >= 18 else { return }
        let name = box.node?.name ?? "\(box.merged.count) smaller items"
        let size = box.node.map(sizeLabel) ?? formatBytes(box.merged.reduce(0) { $0 + $1.totalBytes })
        let inner = r.insetBy(dx: 6, dy: 3)
        ctx.drawLayer { l in
            l.clip(to: Path(r))
            if r.height >= 36 {
                let title = l.resolve(Text(name).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white))
                let sub = l.resolve(Text(size).font(.system(size: 11)).foregroundStyle(.white.opacity(0.8)))
                l.draw(title, in: CGRect(x: inner.minX, y: inner.minY + 2, width: inner.width, height: 16))
                l.draw(sub, in: CGRect(x: inner.minX, y: inner.minY + 18, width: inner.width, height: 15))
            } else {
                let t = l.resolve(Text("\(name) · \(size)").font(.system(size: 11, weight: .medium)).foregroundStyle(.white))
                l.draw(t, in: CGRect(x: inner.minX, y: r.midY - 7, width: inner.width, height: 14))
            }
        }
    }
}

struct Tooltip: View {
    let model: AppModel

    var body: some View {
        if let box = model.hovered, model.zoom == nil {
            let p = model.hoverPoint
            let w: CGFloat = 300
            let x = min(max(8, p.x + 16), max(8, model.canvasSize.width - w - 8))
            let y = p.y + 130 > model.canvasSize.height ? max(8, p.y - 130) : p.y + 18
            VStack(alignment: .leading, spacing: 3) {
                if let n = box.node {
                    Text(n.name).font(.headline).lineLimit(1)
                    Text(model.path(n)).font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                    Text("Allocated: \(n.state == .complete || n.kind == .restricted ? sizeLabel(n) : "at least " + formatBytes(n.totalBytes))")
                    Text("Items: \(n.fileCount.formatted()) files")
                    if n.modified > 0 {
                        Text("Modified: \(Date(timeIntervalSince1970: TimeInterval(n.modified)).formatted(date: .abbreviated, time: .shortened))")
                    }
                    if let g = model.gitDates[n.id], !g.isEmpty { Text("Last commit: \(g)") }
                    if n.kind == .restricted { Text("No permission. Grant Full Disk Access to size it.").foregroundStyle(.orange) }
                } else {
                    Text("\(box.merged.count) smaller items").font(.headline)
                    Text(formatBytes(box.merged.reduce(0) { $0 + $1.totalBytes }))
                    Text("Click to list them").foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .padding(8)
            .frame(width: w, alignment: .leading)
            .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 4)
            .offset(x: x, y: y)
            .allowsHitTesting(false)
        }
    }
}

struct TreemapContextMenu: View {
    @Bindable var model: AppModel

    var body: some View {
        if let n = model.hovered?.node, n.kind != .systemOther, n.kind != .otherFiles {
            Button("Reveal in Finder") { model.reveal(n) }
            Button("Quick Look") { model.quickLook(n) }
            Button("Copy Path") { model.copyPath(n) }
            Divider()
            Button("Move to Trash…") { model.trashCandidate = n }
        }
    }
}
