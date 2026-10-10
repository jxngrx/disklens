import CoreGraphics
import Foundation
import Testing
@testable import DiskLensCore

struct SquarifyTests {
    let bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)

    @Test func areasProportionalAndInside() {
        let sizes: [Double] = [600, 300, 200, 100, 80, 50, 40, 20, 10].map { $0 * 1000 }
        let rects = Squarify.squarify(sizes, in: bounds)
        let total = sizes.reduce(0, +)
        for (r, s) in zip(rects, sizes) {
            let expected = Double(bounds.width * bounds.height) * s / total
            #expect(abs(Double(r.width * r.height) - expected) / expected < 0.001)
            #expect(bounds.insetBy(dx: -0.01, dy: -0.01).contains(r))
        }
        // No overlaps.
        for i in rects.indices { for j in rects.indices where i < j {
            let x = rects[i].intersection(rects[j])
            #expect(x.isNull || x.width * x.height < 0.01)
        } }
    }

    @Test func squarishAspectRatios() {
        let sizes = (1...40).map { Double(41 - $0) }
        let rects = Squarify.squarify(sizes, in: bounds)
        let worst = rects.map { max($0.width / $0.height, $0.height / $0.width) }.max()!
        #expect(worst < 4)
    }

    @Test func smallItemsMerged() {
        let sizes: [Double] = [1000, 500, 300] + Array(repeating: 1, count: 200)
        let rects = Squarify.layout(sizes: sizes, in: bounds)
        #expect(rects.count == 4)
        #expect(rects.last?.index == nil && rects.last?.merged.count == 200)
    }

    @Test func tinyBoxesMergedBySide() {
        let sizes = Array(repeating: 1.0, count: 5000)
        let rects = Squarify.layout(sizes: sizes, in: CGRect(x: 0, y: 0, width: 300, height: 200), minFraction: 0)
        #expect(rects.allSatisfy { $0.index == nil || ($0.rect.width >= 24 && $0.rect.height >= 24) })
        let mergedCount = rects.last?.merged.count ?? 0
        #expect(rects.count - 1 + mergedCount == 5000)
    }

    /// "Clicking any box opens the right folder": the centre of every box hits that box.
    @Test func hitTestEveryBox() {
        let sizes = (0..<5000).map { Double(5000 - $0) }
        let rects = Squarify.layout(sizes: sizes, in: CGRect(x: 0, y: 0, width: 2400, height: 1600), minFraction: 0, minSide: 4)
        #expect(rects.count > 1000)
        for (i, r) in rects.enumerated() {
            #expect(Squarify.hitTest(rects, CGPoint(x: r.rect.midX, y: r.rect.midY)) == i)
        }
    }

    @Test func layoutOf5000IsFast() {
        let sizes = (0..<5000).map { Double(5000 - $0) }
        let clock = ContinuousClock()
        let t = clock.measure {
            _ = Squarify.layout(sizes: sizes, in: CGRect(x: 0, y: 0, width: 2400, height: 1600), minFraction: 0, minSide: 4)
        }
        print("squarify 5000 items:", t)
        #expect(t < .milliseconds(100))
    }
}
