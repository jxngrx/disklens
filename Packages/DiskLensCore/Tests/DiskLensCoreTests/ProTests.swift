import Foundation
import Testing
@testable import DiskLensCore

@Suite(.serialized) struct ProTests {
    @Test func mobilePackListsAndMarksInUse() throws {
        let f = try FakeHome()
        defer { Fixtures.remove(f.root) }
        let android = f.root.path + "/android"
        for rel in ["system-images/android-34/google_apis/arm64-v8a/system.img", "system-images/android-33/default/arm64-v8a/system.img",
                    "ndk/25.1.8937393/source.properties", "ndk/26.1.10909125/source.properties",
                    "home-avd/Pixel_8.avd/userdata.img"] {
            try Fixtures.writeFile(URL(fileURLWithPath: rel.hasPrefix("home-avd") ? f.home + "/.android/avd/" + rel.dropFirst(9) : android + "/" + rel), bytes: 20_000)
        }
        try "image.sysdir.1=system-images/android-34/google_apis/arm64-v8a/\n".write(toFile: f.home + "/.android/avd/Pixel_8.avd/config.ini", atomically: true, encoding: .utf8)
        try "android { ndkVersion \"26.1.10909125\" }".write(toFile: f.p("Projects/rn/android/app/build.gradle"), atomically: true, encoding: .utf8)
        let runtimes = """
        {"A":{"identifier":"A-1","runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-17-5","version":"17.5","platformIdentifier":"com.apple.platform.iphonesimulator","sizeBytes":7000000000},
         "B":{"identifier":"B-2","runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-0","version":"18.0","platformIdentifier":"com.apple.platform.iphonesimulator","sizeBytes":8000000000}}
        """
        let devices = """
        {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[{"name":"iPhone 16","isAvailable":true}],"com.apple.CoreSimulator.SimRuntime.iOS-17-5":[]}}
        """
        let unavailable = """
        {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-16-0":[{"name":"Old","isAvailable":false},{"name":"Older","isAvailable":false}]}}
        """
        let pack = MobilePack(home: f.home, androidHome: android, projectPaths: [f.p("Projects/rn")]) { args in
            if args.starts(with: ["runtime", "list"]) { return runtimes }
            if args.contains("unavailable") { return unavailable }
            return devices
        }
        let items = pack.items()
        func item(_ k: MobileItem.Kind, _ name: String) -> MobileItem? { items.first { $0.kind == k && $0.name.contains(name) } }
        #expect(item(.avd, "Pixel_8")?.command == ["avdmanager", "delete", "avd", "-n", "Pixel_8"])
        #expect(item(.systemImage, "android-34")?.inUse == true)
        #expect(item(.systemImage, "android-34")?.usedBy == ["Pixel_8"])
        #expect(item(.systemImage, "android-33")?.inUse == false)
        #expect(item(.systemImage, "android-33")?.command == ["sdkmanager", "--uninstall", "system-images;android-33;default;arm64-v8a"])
        #expect(item(.ndk, "26.1")?.inUse == true)
        #expect(item(.ndk, "25.1")?.inUse == false)
        #expect(item(.simRuntime, "18.0")?.inUse == true)
        #expect(item(.simRuntime, "17.5")?.inUse == false)
        #expect(item(.simRuntime, "17.5")?.command == ["xcrun", "simctl", "runtime", "delete", "A-1"])
        #expect(item(.unavailableSimulators, "2 unavailable")?.command == ["xcrun", "simctl", "delete", "unavailable"])
    }

    @Test func keepFreePolicyPlansAndDryRunTouchesNothing() async throws {
        let f = try FakeHome()
        defer { Fixtures.remove(f.root) }
        let q = Quarantine(root: f.root.appendingPathComponent("home/.disklens-quarantine"))
        let old = try q.add(path: f.p("Projects/web/dist"), bytes: 9_000, ruleID: 15, now: Date().addingTimeInterval(-2 * 86_400))
        let scanner = DiskScanner(rootPath: f.home, hook: f.rules.listingHook())
        await scanner.run()
        let runner = CommandRunner(dryRun: true)
        let cleaner = Cleaner(rules: f.rules, quarantine: q, runner: runner)
        let policy = KeepFreePolicy(keepFreeBytes: 10_000_000)
        #expect(policy.plan(freeBytes: 20_000_000, quarantine: q.items(), store: scanner.store, rules: f.rules).isEmpty)
        let steps = policy.plan(freeBytes: 9_800_000, quarantine: q.items(), store: scanner.store, rules: f.rules)
        // Oldest quarantine first, then tool commands, never Caution (Archives).
        guard case .purgeQuarantine(let first) = steps.first else { Issue.record("expected quarantine purge first"); return }
        #expect(first.id == old.id)
        guard case .clean(let second) = steps[1] else { Issue.record("expected a clean step"); return }
        #expect(second.command != nil)
        #expect(!steps.contains { if case .clean(let c) = $0 { c.rule.safety == .caution } else { false } })
        // Nested node_modules is not planned separately.
        #expect(!steps.contains { if case .clean(let c) = $0 { c.path.hasSuffix("react/node_modules") } else { false } })
        let before = treeDigest(f.home)
        let log = policy.apply(steps, cleaner: cleaner, dryRun: true)
        #expect(log.allSatisfy { $0.hasPrefix("[dry-run]") })
        #expect(treeDigest(f.home) == before)
        #expect(runner.log.isEmpty)
    }

    @Test func historyRoundTrip() throws {
        let root = try Fixtures.makeRoot("history")
        defer { Fixtures.remove(root) }
        let url = root.appendingPathComponent("history.jsonl")
        for i in 0..<3 {
            try History.append(HistorySample(date: Date(timeIntervalSince1970: Double(i) * 86_400), usedBytes: UInt64(i) * 100,
                                             freeBytes: 5, top: ["Users": UInt64(i)]), to: url)
        }
        let samples = History.load(from: url)
        #expect(samples.map(\.usedBytes) == [0, 100, 200])
        #expect(samples[2].top["Users"] == 2)
    }

    @Test func restoreCommandFromLockfile() throws {
        let root = try Fixtures.makeRoot("restorecmd")
        defer { Fixtures.remove(root) }
        for (dir, lock) in [("a", "package-lock.json"), ("b", "yarn.lock"), ("c", "pnpm-lock.yaml"), ("d", "Podfile.lock")] {
            try Fixtures.writeFile(root.appendingPathComponent("\(dir)/\(lock)"), bytes: 10)
        }
        #expect(Projects.restoreCommand(root.path + "/a") == ["npm", "ci"])
        #expect(Projects.restoreCommand(root.path + "/b") == ["yarn", "install", "--frozen-lockfile"])
        #expect(Projects.restoreCommand(root.path + "/c") == ["pnpm", "install", "--frozen-lockfile"])
        #expect(Projects.restoreCommand(root.path + "/d") == ["pod", "install"])
    }
}
