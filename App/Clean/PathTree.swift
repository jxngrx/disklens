import DiskLensCore
import Foundation

/// Folder tree built from absolute paths. Chains of single-child folders collapse into one row ("Library/Caches").
struct PathNode: Identifiable {
    var name: String
    var path: String
    var children: [PathNode] = []
    var project: ProjectInfo?
    var node: NodeInfo?
    var id: String { path }

    final class Builder {
        var name: String, path: String
        var kids: [String: Builder] = [:]
        var project: ProjectInfo?, node: NodeInfo?
        init(_ name: String, _ path: String) { self.name = name; self.path = path }
    }

    static func build(_ items: [(path: String, project: ProjectInfo?, node: NodeInfo?)]) -> [PathNode] {
        let root = Builder("", "")
        for it in items {
            var parts = (it.path as NSString).abbreviatingWithTildeInPath.split(separator: "/").map(String.init)
            if parts.first == "~" { parts.removeFirst() }
            var cur = root
            for p in parts {
                let next = cur.kids[p] ?? Builder(p, cur.path + "/" + p)
                cur.kids[p] = next
                cur = next
            }
            cur.project = it.project; cur.node = it.node
        }
        return root.kids.values.map(convert).sorted { $0.name < $1.name }
    }

    private static func convert(_ b: Builder) -> PathNode {
        var n = PathNode(name: b.name, path: b.path, children: b.kids.values.map(convert).sorted { $0.name < $1.name },
                         project: b.project, node: b.node)
        while n.project == nil, n.node == nil, n.children.count == 1 {
            let c = n.children[0]
            n = PathNode(name: n.name + "/" + c.name, path: c.path, children: c.children, project: c.project, node: c.node)
        }
        return n
    }
}
