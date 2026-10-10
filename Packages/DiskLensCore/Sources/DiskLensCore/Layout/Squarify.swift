import CoreGraphics

/// One laid-out box. `index` points into the input items; `nil` means the merged "N smaller items" box.
public struct TreemapRect: Sendable, Equatable {
    public var index: Int?
    public var rect: CGRect
    public var merged: [Int] = []
}

/// Squarified treemap (Bruls, Huizing, van Wijk 2000).
public enum Squarify {
    /// Lays out `sizes` in the given order (best when sorted descending). Returns one rect per kept item plus an
    /// optional merged box. Items under `minFraction` of the total, or whose box would be under `minSide` points, are merged.
    public static func layout(sizes: [Double], in bounds: CGRect,
                              minFraction: Double = 0.005, minSide: CGFloat = 24) -> [TreemapRect] {
        let total = sizes.reduce(0, +)
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return [] }
        var kept = sizes.indices.filter { sizes[$0] > 0 && sizes[$0] / total >= minFraction }
        while true {
            let keptSet = Set(kept)
            let merged = sizes.indices.filter { sizes[$0] > 0 && !keptSet.contains($0) }
            let mergedSize = merged.reduce(0) { $0 + sizes[$1] }
            var values = kept.map { sizes[$0] }
            if mergedSize > 0 { values.append(mergedSize) }
            let rects = squarify(values, in: bounds)
            // Too-small boxes: fold them (and anything no bigger) into the merged box and retry.
            let bad = kept.indices.filter { rects[$0].width < minSide || rects[$0].height < minSide }
            if let limit = bad.map({ sizes[kept[$0]] }).max() {
                kept.removeAll { sizes[$0] <= limit }
                continue
            }
            var out = kept.enumerated().map { TreemapRect(index: $1, rect: rects[$0]) }
            if mergedSize > 0, let r = rects.last { out.append(TreemapRect(index: nil, rect: r, merged: merged)) }
            return out
        }
    }

    /// Plain squarify of positive values (sorted descending) into `bounds`, same order as input.
    public static func squarify(_ values: [Double], in bounds: CGRect) -> [CGRect] {
        let total = values.reduce(0, +)
        guard total > 0 else { return values.map { _ in .zero } }
        let scale = Double(bounds.width * bounds.height) / total
        let areas = values.map { $0 * scale }
        var out: [CGRect] = []
        out.reserveCapacity(areas.count)
        var free = bounds
        var i = 0
        while i < areas.count {
            let side = Double(min(free.width, free.height))
            // Sorted descending: row max is its first item, min its last.
            var sum = areas[i]
            var j = i + 1
            while j < areas.count,
                  worst(sum + areas[j], areas[i], areas[j], side) <= worst(sum, areas[i], areas[j - 1], side) {
                sum += areas[j]; j += 1
            }
            free = place(areas[i..<j], sum: sum, in: free, into: &out)
            i = j
        }
        return out
    }

    static func worst(_ s: Double, _ mx: Double, _ mn: Double, _ side: Double) -> Double {
        guard s > 0, side > 0, mn > 0 else { return .infinity }
        return max(side * side * mx / (s * s), (s * s) / (side * side * mn))
    }

    /// Lays a row along the shorter side of `free`, returns the remaining space.
    static func place(_ row: ArraySlice<Double>, sum s: Double, in free: CGRect, into out: inout [CGRect]) -> CGRect {
        if free.width >= free.height {
            let w = CGFloat(s) / free.height
            var y = free.minY
            for a in row {
                let h = CGFloat(a) / w
                out.append(CGRect(x: free.minX, y: y, width: w, height: h))
                y += h
            }
            return CGRect(x: free.minX + w, y: free.minY, width: max(0, free.width - w), height: free.height)
        } else {
            let h = CGFloat(s) / free.width
            var x = free.minX
            for a in row {
                let w = CGFloat(a) / h
                out.append(CGRect(x: x, y: free.minY, width: w, height: h))
                x += w
            }
            return CGRect(x: free.minX, y: free.minY + h, width: free.width, height: max(0, free.height - h))
        }
    }

    /// Index into `rects` of the box containing `point`, if any.
    public static func hitTest(_ rects: [TreemapRect], _ point: CGPoint) -> Int? {
        rects.firstIndex { $0.rect.contains(point) }
    }
}
