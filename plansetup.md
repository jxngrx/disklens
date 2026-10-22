# DiskLens — build plan and log

## Status
- **Current phase:** done
- **Current task:** all phases complete — awaiting review
- **Last updated:** 2026-10-10 23:53 IST

## Plan

### Phase 0 — setup
- [x] 0.1 Read SPEC.md, create plansetup.md, `git init`

### Phase 1 — Core scanner (no UI)
- [x] 1.1 Project skeleton: `Packages/DiskLensCore` (Swift 6 package), `.gitignore`, `CLAUDE.md`
- [x] 1.2 `getattrlistbulk` directory reader + FileManager fallback
- [x] 1.3 `TreeStore` (parallel arrays, `Int32` ids, roll-up, states, top-50/1 MB file folding)
- [x] 1.4 Scanner (workers, volume boundary, skip list, hard-link dedupe, restricted, bundles)
- [x] 1.5 Fixture generator (`$TMPDIR/disklens-fixtures/`)
- [x] 1.6 Test CLI printing the 20 biggest folders
- [x] 1.7 Check: fixture totals match `du -sk` within 1%
- [x] 1.8 Check: 10 hard links to one 100 MB file count 100 MB once
- [x] 1.9 Check: permission-denied folder shows Restricted, scan continues
- [x] 1.10 Perf: real-disk read-only scan, time + file count + RSS logged
- [x] 1.11 Tag `phase-1-done`

### Phase 2 — Treemap UI
- [x] 2.1 XcodeGen `project.yml`, app target + UI test target, builds with `xcodebuild`
- [x] 2.2 Squarified layout + "N smaller items" merge + second-level preview
- [x] 2.3 `Canvas` renderer: category colours, labels, badges, 2 pt gaps, 6 pt radius, partial shimmer
- [x] 2.4 Hit testing, click-to-drill with ~250 ms zoom animation
- [x] 2.5 Breadcrumb, back (Esc, ⌘[, swipe), ⌘↑ parent
- [x] 2.6 Hover tooltip (path, size, count, modified, git date), right-click menu
- [x] 2.7 Sidebar list in sync; smaller-items list sheet
- [x] 2.8 Check: 5,000 boxes redraw at 60 fps (measured)
- [x] 2.9 Check: clicking any box opens the right folder (hit-test unit test + XCUITest)
- [x] 2.10 XCUITest: drill-down, breadcrumb, back navigation — written; run blocked (automation mode), covered by `-selftest`
- [x] 2.11 Screenshots `docs/screenshots/phase-2/`, fix layout issues
- [x] 2.12 Tag `phase-2-done`

### Phase 3 — Progressive + priority scan
- [x] 3.1 Priority queue actor (focus subtree first), re-prioritise on drill-in
- [x] 3.2 Streaming UI updates ≤10/s, stable order, "at least" labels for partial
- [x] 3.3 System & other box from volume capacity
- [x] 3.4 Full Disk Access banner for Restricted
- [x] 3.5 Check: first boxes in < 1 s (measured)
- [x] 3.6 Check: folder focused mid-scan finishes before unrelated folders
- [x] 3.7 Check: root total within 2% of Finder used space
- [x] 3.8 Screenshots `docs/screenshots/phase-3/`
- [x] 3.9 Tag `phase-3-done`

### Phase 4 — Rules, projects, quarantine
- [x] 4.1 `rules.json` (bundled resource) + loader + matcher
- [x] 4.2 Project detection (markers), artifact folders, staleness
- [x] 4.3 Cleanable tags + badges in treemap
- [x] 4.4 Quarantine (rename into `~/.disklens-quarantine/<date>/`), restore, purge after N days, empty now
- [x] 4.5 Tool commands with dry-run mode; running-tool checks
- [x] 4.6 Projects view (reclaimable, last worked on, 30+ day filter)
- [x] 4.7 Clean confirm sheet (tool-command items marked non-quarantinable)
- [x] 4.8 License + trial (stub)
- [x] 4.9 Check: clean then restore is byte-identical
- [x] 4.10 Check: nothing outside a rule's paths can be selected for cleaning
- [x] 4.11 XCUITest: clean confirm sheet
- [x] 4.12 Screenshots `docs/screenshots/phase-4/`
- [x] 4.13 Tag `phase-4-done`

### Phase 5 — Live updates + saved index
- [x] 5.1 Binary snapshot write/read (memory-mapped) with FSEvents id + volume UUID
- [x] 5.2 Launch from snapshot with "updated X ago" label
- [x] 5.3 FSEvents catch-up since saved id; full rescan fallback
- [x] 5.4 Live FSEventStream, coalescing, directory rescan with diff roll-up, MustScanSubDirs
- [x] 5.5 Ignore own writes; instant subtract after clean
- [x] 5.6 Check: relaunch shows map in < 1 s
- [x] 5.7 Check: 1 GB file in watched folder updates within 3 s
- [x] 5.8 Screenshots `docs/screenshots/phase-5/`
- [x] 5.9 Tag `phase-5-done`

### Phase 6 — Pro and CLI
- [x] 6.1 Restore buttons (npm ci / yarn / pnpm / pod install) — dry-run tested
- [x] 6.2 Mobile pack: AVDs, system images/NDKs, simulator runtimes, unavailable simulators
- [x] 6.3 Menu bar free-space display + low-disk alert
- [x] 6.4 `disklens` CLI (scan, top, rules, clean --dry-run, quarantine list/restore/purge)
- [x] 6.5 Daemon mode with "keep N GB free" policy (dry-run tested)
- [x] 6.6 Growth timeline (history file + Swift Charts)
- [x] 6.7 Screenshots `docs/screenshots/phase-6/`
- [x] 6.8 Tag `phase-6-done`

### Wrap-up
- [x] 7.1 Final review section

## Progress log
- 2026-10-10 22:52 — 0.1 Read SPEC.md (renamed `spec.md` → `SPEC.md` to match the docs), created plansetup.md, `git init`, started `brew install xcodegen`. Files: plansetup.md. Result: ok.

- 2026-10-10 22:53 — 1.1 Package skeleton `Packages/DiskLensCore` (library + `disklens` exe + tests), `.gitignore`, `CLAUDE.md`. Result: ok.
- 2026-10-10 22:54 — 1.2 `Scanner/DirectoryReader.swift`: `getattrlistbulk` reader (name, devid, objtype, modtime, fileid, linkcount, allocsize) with `lstat` fallback. Result: builds.
- 2026-10-10 22:54 — 1.3 `Tree/TreeStore.swift`: parallel arrays, `Int32` ids, roll-up, pending/partial/complete, rescan diff, remove, System & other. Result: builds.
- 2026-10-10 22:55 — 1.4 `Scanner/Scanner.swift`: queue actor + 8 workers, device check, skip list, hard-link table, restricted, bundles, file folding. Result: builds.
- 2026-10-10 22:55 — 1.5 `Scanner/Fixtures.swift`: fixture generator under `$TMPDIR/disklens-fixtures/` (remove refuses paths outside it). Result: ok.
- 2026-10-10 22:56 — 1.6 `Sources/disklens/main.swift`: `disklens top [path] [--count N]`. Result: ok.
- 2026-10-10 22:56 — 1.7–1.9 `Tests/DiskLensCoreTests/ScannerTests.swift`: du match, hard links, restricted, symlinks, folding, rescan diff. Result: 6/6 pass.
- 2026-10-10 22:58 — 1.10 Real-disk read-only scan (release): 1,801,917 files, 831,243 nodes, 12.07 s, 174 MB max RSS. Result: ok (see Test results).
- 2026-10-10 22:56 IST — 1.11 Tagged phase-1-done. Result: ok.
- 2026-10-10 22:58 IST — 2.2 Squarified layout + smaller-items merge + hit test in `DiskLensCore/Layout/Squarify.swift`, tests in `SquarifyTests.swift`. First version was O(n²) (1.45 s for 5,000 items); fixed with O(1) worst-ratio and jump-ahead merge retry: 3.7 ms. Result: 6/6 pass.
- 2026-10-10 23:18 IST — 2.1–2.11 App target via XcodeGen (`project.yml`, `App/`, `UITests/`), Canvas renderer, zoom, breadcrumb, back/parent keys + swipe, tooltip, context menu, sidebar, smaller-items sheet, legend, benchmark + self-test debug modes. Screenshots in docs/screenshots/phase-2/. Fixed after looking at screenshots: legend wrapping into 3-line labels (now ViewThatFits with dot fallback), second-level preview overlapping the label (now starts below it, tinted by child category), default window size. 2.10 XCUITest blocked (automation mode), see Blockers.
- 2026-10-10 23:19 IST — 2.12 Tagged phase-2-done.
- 2026-10-10 23:22 IST — 3.1–3.9 Priority queue (focus subtree tier, re-partition on drill-in) + test; bucketed stable order during scans; size changes ease between layouts (200 ms); System & other added on scan completion; Full Disk Access banner with restricted count. Screenshots in docs/screenshots/phase-3/. Bugs found from screenshots and fixed: (1) stable order fed unsorted sizes to a layout that assumed descending order, so one '8 smaller items' box swallowed the map — layout is now order-agnostic and the model only swaps items across ~41% size buckets; (2) the Canvas TimelineView paused mid-resize animation, freezing overlapping boxes — now a `resizing` flag keeps it running until the ease ends. Tagged phase-3-done.
- 2026-10-10 23:25 IST — 4.1/4.2/4.4/4.5/4.9/4.10 Core: `Rules/rules.json` (15 rules + project markers + artifact folders), `Rules/Rules.swift` (RuleSet loader, fnmatch matcher that re-checks the file system, keep-newest-N, project ownership, scanner hook), `Rules/Projects.swift` (collect, last-worked-on, restore command), `Cleaner/Quarantine.swift` (same-volume rename + JSON manifest, restore, purge, empty now), `Cleaner/Cleaner.swift` (CommandRunner with dry-run, running-tool probes, plan/execute with re-check). Tests `CleanerTests.swift`: 6 new, all pass (20/20 total).
- 2026-10-10 23:33 IST — 4.3–4.13 App: cleanable outline + safety badges, Clean… context item, confirm sheet (quarantine vs tool command, running-tool warnings with Quit), Projects sheet (reclaimable, last worked on, 30+ day filter, Clean Selected), Quarantine sheet (Restore, Empty Now), purge on launch, license/trial stub in Settings, clean message bar with Undo. CLI: `rules`, `clean`, `quarantine`. UI tests now run (automation mode became available) — all 3 pass after forcing the sidebar visible. Screenshot fixes: tooltip lingering under sheets (hover ignored while a sheet is up), sheet title, artifact names relative to project, '1 files', badge hiding the label on narrow boxes. Tagged phase-4-done.
- 2026-10-10 23:40 IST — 5.1–5.9 `Tree/Snapshot.swift` (compacting BFS binary format, mmap load), `Watcher/Watcher.swift` (FSEventStream file events 1 s latency, coalescer), `Watcher/LiveIndex.swift` (open from snapshot if root + FSEvents volume UUID match, replay since saved event id, live updates, subtree relist, ignore own index/quarantine, save after scan / every 5 min / on quit). App: status 'Index from X ago · catching up…' → 'Live · index saved X ago'. Bugs found from screenshots and fixed: (1) relisting '/' dropped the System & other node; (2) Canvas redrew with the paused timeline's stale date, freezing boxes mid-animation (now wall clock); (3) MustScanSubDirs reset whole subtrees to pending, so the map fell to '≥ 60 GB' — now subtrees are relisted in place and the old map stays visible; (4) restricted count double-counted after resets. Tagged phase-5-done.
- 2026-10-10 23:52 IST — 6.1–6.8 Core: `Cleaner/MobilePack.swift` (AVDs, system images with AVD usage, NDKs with project ndkVersion usage, simctl runtimes with device usage, unavailable simulators; simctl injectable), `Cleaner/Policy.swift` (KeepFreePolicy: oldest quarantine → tool commands → Safe/Rebuildable quarantine, never Caution; dry-run apply; History JSON lines). CLI: `projects`, `mobile`, `history`, `daemon --keep-free`. App: Reinstall button (npm ci / yarn / pnpm / pod install) in Quarantine, Mobile pack sheet, Growth chart (Swift Charts), MenuBarExtra free space + low-disk notification + threshold menu, login item toggle (SMAppService) in Settings. Bug found by UI tests: with the menu bar extra, restored window state could launch with **no main window**; fixed by ignoring persisted window state. Tagged phase-6-done.
- 2026-10-10 23:53 IST — 7.1 Final review written. Result: all 6 phases tagged (phase-1-done … phase-6-done).

## Decisions
- No C shim target: `getattrlistbulk`, `statfs`, FSEvents are all callable from Swift via Darwin/CoreServices; one less target.
- Root walk allows two device ids: `/` (sealed system snapshot) and `/System/Volumes/Data`. A strict "same device as `/`" check would skip `/Users` etc., because firmlinks resolve to the Data volume's device.
- Queue is LIFO (depth-first) inside each priority tier: subtrees finish sooner and the queue stays small. Root is still listed first, so top-level boxes appear immediately.
- File folding: a file gets its own node only if it is ≥ 1 MB and in the folder's top 50; everything else folds into "N other files". Keeps memory down (spec wording "over 1 MB, or the top 50" was ambiguous).
- Hard links: first directory that sees a (device, inode) owns its bytes; rescans of that same directory keep counting it. Duplicates inside one listing are counted once.
- One `NSLock` around the whole TreeStore (simple, measured fine for 8 workers).
- Detached nodes (deleted folders) stay in the arrays as garbage until the next snapshot save.
- Squarify + hit testing live in DiskLensCore (`Layout/`) instead of `App/Treemap` so `swift test` covers them without an app test bundle.
- Debug launch modes instead of extra test bundles: `-benchmark` (5,000-box render timing), `-selftest` (navigation checks), `-scanRoot`, `-openPath`, `-hoverName` (screenshot helpers). All read-only.
- Store changes reach the UI by a 10 Hz poll of `TreeStore.version` (spec: layout at most ~10/s) instead of notifications from worker threads.
- Quick Look uses `qlmanage -p` rather than a `QLPreviewPanel` controller.
- UI test target compiles in Swift 5 mode (XCTest's non-isolated overrides fight Swift 6 strict concurrency); app and core use Swift 6.
- Core type is `DiskScanner` (not `Scanner`) to avoid clashing with `Foundation.Scanner`.
- System & other is computed once the scan completes. Updating it mid-scan made it a 185 GB box that shrank as the scan progressed, which reads as wrong; the root shows '≥ X' until then.
- Stable order uses log-size buckets (two per doubling): siblings only swap when one outgrows the other by ~41%.
- Matching always re-reads the file system (lstat, marker files) instead of trusting tree tags, and refuses symlinks, `..`, `/`; the cleaner re-matches right before acting.
- Added plain `Pods` (with a Podfile marker) to the artifact list for native iOS projects; spec only listed `ios/Pods`.
- Unavailable simulators / simulator runtimes have no path, so they live in the Mobile pack (phase 6), not in rules.json path rules.
- Quarantine refuses cross-volume moves (no copy fallback): a copy of a 2 GB node_modules is not 'instant' and could fill the disk.
- `CommandRunner` runs tools via `/usr/bin/env` with Homebrew/Android paths appended; `DISKLENS_DRY_RUN=1` forces dry-run everywhere.
- License/trial is a local stub (14-day trial in UserDefaults, `DL-XXXX-XXXX-CCCC` checksum keys). Pro gating applies to phase 6 features.
- Projects / Quarantine / Clean are sheets on the main window, not separate windows (fewer scenes, simpler state).
- Snapshot stores only complete trees and is compacted (detached nodes dropped, BFS order). Hard-link ownership is not persisted: after a relaunch, a rescanned folder may count a hard link already counted elsewhere (ponytail note in LiveIndex era; acceptable drift until the next full scan).
- Index lost detection uses the FSEvents volume UUID + `EventIdsWrapped`/`RootChanged` flags; then all folders are relisted in place while the old map stays visible.
- Fixture scans keep their index in `$TMPDIR/disklens-fixtures/.indexes/`; `-indexDir` overrides.
- Daemon is a foreground `disklens daemon` loop (launchd plist not generated); the app's background mode is a login item via SMAppService.
- Mobile-pack items in use are shown but their Remove button is disabled; no override in the UI.
- Low-disk alert threshold defaults to 10 GB and asks for notification permission only when first crossed.

## Deviations from spec
- `swift-argument-parser` not used for the CLI: argv is parsed by hand (≈30 lines) to avoid a network dependency and a new package for 8 subcommands.
- Growth timeline uses a JSON-lines file instead of SQLite/GRDB.
- Sparkle updates, Developer ID signing/notarization and Paddle/Lemon Squeezy licensing are not integrated (ad-hoc signing, local license stub).
- Squarify/hit testing live in DiskLensCore/Layout rather than App/Treemap (testable with `swift test`).
- No separate C shim target (Swift calls getattrlistbulk/FSEvents directly).
- Restricted folders are drawn with a dashed outline and 'unknown size'; with zero bytes they get no area, so they mostly show in the sidebar, tooltips and the banner count.

## Test results
### Phase 1
- `cd Packages/DiskLensCore && swift test` — 6 passed, 0 failed (du within 1%, 10 hard links = 100 MB once, restricted + scan continues, symlinks not followed, small-file folding, rescan diff).
- `swift build -c release && /usr/bin/time -l .build/release/disklens top /` — 1.80 M files in 12.07 s (target: 1 M files < 30 s ✔), 174 MB max RSS for 1.8 M files (extrapolates to ~290 MB at 3 M; target < 300 MB, tight). 457 restricted folders (Terminal lacks Full Disk Access).
### Phase 2
- `swift test --filter Squarify` — 6 passed: proportional areas, aspect ratio < 4, merge by fraction, merge by 24 pt side, hit test of every box centre (5,000 items), layout of 5,000 items 3.7 ms (debug).
- `DiskLens -benchmark` (Release): 5,000 boxes through the real `TreemapRenderer`, fresh `ImageRenderer` each frame: avg 2.66 ms/frame (≈375 fps; worst 32 ms = first frame warm-up). Target 60 fps ✔.
- `DiskLens -scanRoot <showcase fixture> -selftest` — 15/15 PASS: every folder box centre opens that folder, 3-level drill-down breadcrumb, zoom started, breadcrumb jump, back, parent.
- `xcodebuild -project DiskLens.xcodeproj -scheme DiskLens -derivedDataPath build/dd test` — XCUITests written (`UITests/NavigationUITests.swift`: click box drill-down, breadcrumb, Esc, ⌘[, ⌘↑, back button) but could not run: runner fails with "Timed out while enabling automation mode".
### Phase 3
- `swift test` — 14 passed (adds `PriorityTests.focusedFolderFinishesFirst`: 1 worker, two 160-folder trees; control run finds which tree finishes last, second run focuses it after 20 listings, and it then finishes first; `UnsortedLayoutTests`).
- Real disk, Release app: first boxes after **0.100 s** (14 boxes) — target < 1 s ✔. Full app scan finishes in ~20 s.
- Root total 230.33 GB vs volume used (total − available) 230.34 GB and Finder-style used (total − availableForImportantUsage) 230.06 GB → **0.12%** — target 2% ✔. Note: earlier I thought the scan over-counted by 7%; that was GiB (du) vs GB (ByteCountFormatter). Per-folder sizes match `du -sk`.
- 458 folders restricted without Full Disk Access (banner shown).
### Phase 4
- `swift test` — 20 passed: rule matching (incl. keep newest 2 DeviceSupport), **nothing outside rules is cleanable** (walks every fixture path; explicit negatives for sources, project roots, home, non-project node_modules, symlinks, `..`, `/`; `plan` throws), **clean then restore byte-identical** (SHA-256 + file mode of every file), command rules only log in dry-run, purge only expired, scanner hook tags + Projects.collect.
- `DiskLens -scanRoot <fixture> -rulesHome <fixture> -quarantineRoot <fixture>/q -dryRun YES -selftest` — 26/26 PASS (adds: artifact tagged, confirm plan, project folder refused, moved out, instant subtract, quarantine item, restored, size back after rescan).
- `xcodebuild -project DiskLens.xcodeproj -scheme DiskLens -derivedDataPath build/dd test` — **3/3 UI tests pass**: NavigationUITests.testClickBoxDrillsIntoRightFolder, testBreadcrumbAndBack (breadcrumb, Esc, ⌘[, ⌘↑, back button), CleanSheetUITests.testConfirmSheetCancelThenClean (right-click → Clean… → sheet → Cancel keeps files → Clean quarantines; dry-run env, fixture quarantine).
- CLI on fixture: `disklens clean <DerivedData/Other-def> <rust-tool/target> <.npm> --dry-run --rules-home F --quarantine-root Q` → 2 quarantined, npm command only logged.
### Phase 5
- `swift test` — 26 passed (adds snapshot round trip incl. compaction, coalescer, 1 M-node load, 1 GB live update, catch-up from snapshot, System & other kept on relist).
- `swift test -c release -Xswiftc -enable-testing --filter 'SnapshotTests|LiveUpdateTests'`: 1 M-node snapshot save 0.57 s, **load 0.108 s**, 83 MB file; **1 GB file reflected 0.17 s after the write finished** (write itself 0.53 s; FSEvents latency 1 s from first event) — target 3 s ✔.
- Real disk relaunch (Release app, 54.5 MB `index-root.bin`, ~830 k nodes): **first boxes 0.349 s after process start** (0.027 s after model start) — target 1 s ✔. Fresh launch without index: first boxes 0.788 s after process start (0.101 s after scan start).
- Catch-up after relaunch kept the map stable (no subtree reset, 458 restricted, root total unchanged).
### Phase 6
- `swift test` — **30 passed** (adds mobile pack in-use detection with injected simctl JSON, keep-free policy order + dry-run touches nothing (SHA-256 of the whole fake home), history round trip, lockfile → restore command).
- `disklens daemon --keep-free 50 --root <fixture> --once --dry-run ...` → 12 planned steps, all `[dry-run]`, fixture unchanged.
- `disklens mobile` on this Mac (read-only): 1 AVD 5.31 GB, 6 system images (1 in use by the AVD), 3 NDKs, 1 simulator runtime 8.49 GB (in use).
- `xcodebuild ... test` — **3/3 UI tests pass** (after the no-window fix).
- `DiskLens -selftest` on a fresh showcase fixture — SELFTEST OK (26 checks). `DiskLens -benchmark` — 5,000 boxes 2.37 ms/frame.

## Blockers & workarounds
- **XCUITest automation mode** (phase 2+): `xcodebuild test` fails with "The test runner failed to initialize for UI testing. (Underlying Error: Timed out while enabling automation mode.)". macOS wants an admin to authorise UI automation, and I may not use sudo. **You need to:** run `sudo automationmodetool enable-automationmode-without-authentication` once (or approve the prompt when running the tests from Xcode), then rerun the test command. Workaround: `DiskLens -selftest` drives the same model calls (hit test → activate, breadcrumb, back, parent) headlessly.
- Update (phase 4): XCUITest automation mode started working on a later run (approved/enabled outside this session, or the first-run timeout was transient). All UI tests now run; the `-selftest` fallback stays as a fast headless check.
- Screenshot runs launch the app in front of whatever you are doing; one capture ended up drilled into your home folder (a click landed on the window). No files were touched; noted so you know why the app may have flashed on screen.

## Questions for review
1. File folding: a file gets its own box only if it is ≥ 1 MB and in its folder's top 50; everything else is one 'N other files' box. OK, or keep the top 50 regardless of size?
2. System & other is added only when a scan completes (not mid-scan). OK?
3. `Pods` (native iOS, with a Podfile) counts as a project artifact in addition to the spec's `ios/Pods`. Keep?
4. Daemon policy order: oldest quarantine first, then tool-command caches, then Safe/Rebuildable folders into quarantine; Caution never automatic. Right priorities?
5. Quarantine never copies across volumes (refuses instead). OK for external-drive projects?
6. Trial length 14 days and which features are Pro (reinstall buttons, mobile pack removal) — guesses.
7. I renamed `spec.md` to `SPEC.md` to match your instructions and the repo layout.
8. The real-disk index is saved at `~/Library/Application Support/DiskLens/index-root.bin` (54 MB) from my test launches; delete it if you want a cold first launch.

## Final review
### What works
- **Core (DiskLensCore):** getattrlistbulk scanner (8 workers, two-tier focus queue, volume/firmlink handling, hard-link dedupe, restricted folders, bundles, file folding), TreeStore (parallel Int32-indexed arrays, roll-up, pending/partial/complete, diff rescans), squarified layout + hit testing, rules.json matcher with file-system re-checks, project detection + staleness, quarantine/restore/purge, tool commands with dry-run, running-tool probes, binary snapshot, FSEvents catch-up + live updates, mobile pack, keep-free policy, growth history.
- **App:** Canvas treemap with category colours, labels, safety badges, cleanable outline, second-level preview, partial shimmer and '≥' sizes, 250 ms zoom in/out, eased size changes, breadcrumb, Esc/⌘[/swipe back, ⌘↑ parent, tooltip (path, size, items, modified, last commit), right-click menu (Clean, Reveal, Quick Look, Copy path, Move to Trash with confirm), synced sidebar, smaller-items sheet, Full Disk Access banner, clean confirm sheet, Projects, Quarantine (Restore, Reinstall, Empty now), Mobile pack, Growth chart, menu bar free space + low-disk alert, Settings (license, login item), instant launch from saved index with 'Index from X ago · catching up…' → 'Live'.
- **CLI `disklens`:** top, rules, clean, quarantine, projects, mobile, history, daemon --keep-free, make-fixture.

### Partial
- Running-tool checks: detection via pgrep; 'Quit' asks GUI apps to terminate and runs `gradle --stop` / `pkill metro`; Docker/Emulator have no stop action.
- Hard-link ownership is not saved in the snapshot, so after relaunch a rescan can double-count a hard link until the next full scan.
- Restricted folders have no area (unknown size); they show in sidebar/tooltip/banner, not as visible boxes at root.
- NDK 'in use' only checks projects the scan found (Gradle `ndkVersion` text match).
- APFS clone 'up to' labelling is not implemented (no cheap detection).

### Stubbed
- Licensing (local checksum keys, 14-day trial), Sparkle, notarization/Developer ID, Paddle/Lemon Squeezy.
- No launchd plist for the daemon; run `disklens daemon` yourself or use the app's login item.

### Build, run, test
```
# core
cd Packages/DiskLensCore && swift build && swift test
swift test -c release -Xswiftc -enable-testing --filter 'SnapshotTests|LiveUpdateTests'   # perf numbers
swift build -c release && .build/release/disklens top /          # read-only real-disk scan
# app
brew install xcodegen   # if missing
xcodegen generate
xcodebuild -project DiskLens.xcodeproj -scheme DiskLens -configuration Release -derivedDataPath build/dd build
open build/dd/Build/Products/Release/DiskLens.app
xcodebuild -project DiskLens.xcodeproj -scheme DiskLens -derivedDataPath build/dd test          # UI tests
# headless checks
F=$(Packages/DiskLensCore/.build/debug/disklens make-fixture showcase)
build/dd/Build/Products/Release/DiskLens.app/Contents/MacOS/DiskLens -scanRoot $F -rulesHome $F -quarantineRoot $F-q -dryRun YES -selftest
build/dd/Build/Products/Release/DiskLens.app/Contents/MacOS/DiskLens -benchmark
```
Safety switches: `DISKLENS_DRY_RUN=1` or `-dryRun YES` (tool commands only logged), `-quarantineRoot`, `-rulesHome`, `-indexDir`.

### Performance vs targets (Apple Silicon, internal SSD)
| Metric | Target | Measured |
| --- | --- | --- |
| First boxes on screen | < 1 s | 0.10 s after scan start (0.79 s after process start, cold) |
| Full scan ~1 M files | < 30 s | 1.80 M files in 12.1 s (CLI, release) |
| Memory ~3 M files | < 300 MB | 174 MB max RSS at 1.8 M files → ~290 MB extrapolated (tight) |
| Launch from saved index | < 1 s | 0.35 s process start → map (830 k nodes); 1 M-node load 0.108 s |
| Live change reflected | < 3 s | 1 GB file: 0.17 s after write finished |
| 5,000 boxes redraw | 60 fps | 2.4–2.7 ms/frame (≈400 fps) |
| Root total vs Finder | within 2% | 0.12% |

### Tests
- `swift test`: 30 passed. UI tests: 3 passed. Self-test: 26 checks OK.

### Known bugs and rough edges
- XCUITest needed automation-mode approval the first time ('Timed out while enabling automation mode'); it worked on later runs.
- Screenshot/test launches put the window in front of whatever you were doing.
- Labels are clipped, not ellipsised, on narrow boxes; long names can cut mid-word.
- Zoom-out animation scales text too (brief blur).
- Detached nodes stay in memory until the next snapshot save (long sessions with heavy churn grow memory).
- Projects 'last worked on' walks up to 50 k entries per project on first open of the Projects sheet (can take a few seconds on big monorepos).
- Category colours are name heuristics; a folder called 'target' outside a Rust project is coloured as Rust.

### Screenshots
- Phase 2: [root](docs/screenshots/phase-2/01-root.png), [drill-down](docs/screenshots/phase-2/02-drill-projects.png), [tooltip](docs/screenshots/phase-2/03-hover-tooltip.png)
- Phase 3: [real disk mid-scan](docs/screenshots/phase-3/01-root-mid-scan.png), [complete](docs/screenshots/phase-3/02-root-complete.png)
- Phase 4: [cleanable](docs/screenshots/phase-4/01-root-cleanable.png), [DerivedData](docs/screenshots/phase-4/02-deriveddata.png), [clean sheet](docs/screenshots/phase-4/03-clean-sheet.png), [projects](docs/screenshots/phase-4/04-projects.png), [quarantine](docs/screenshots/phase-4/05-quarantine.png)
- Phase 5: [relaunch from index](docs/screenshots/phase-5/01-relaunch-from-index.png), [live](docs/screenshots/phase-5/02-live.png)
- Phase 6: [mobile pack](docs/screenshots/phase-6/01-mobile-pack.png), [growth](docs/screenshots/phase-6/02-growth.png), [quarantine + reinstall](docs/screenshots/phase-6/03-quarantine-reinstall.png), [menu bar](docs/screenshots/phase-6/04-menubar.png)

### Top 10 suggested improvements (by impact)
1. **Developer ID signing + notarization + Sparkle**: required to ship at all outside the App Store.
2. **'Contains cleanable' roll-up**: show reclaimable bytes on ancestor boxes (e.g. Library → 32 GB cleanable) so users find junk from the root without drilling.
3. **Full Disk Access onboarding**: detect FDA, guide the grant, auto-rescan restricted folders after it is granted (458 folders restricted here).
4. **Persist hard-link ownership** (or rescan hard-linked dirs on catch-up) to remove the pnpm double-count after relaunch.
5. **Memory headroom**: intern names / store them in one UTF-8 blob, drop per-node String; target 3 M files at < 200 MB.
6. **Real licensing** (Paddle/Lemon Squeezy) and Pro gating UX.
7. **launchd agent for `disklens daemon`** with a config file (keep-free GB, allowed rules), plus a CI mode that fails builds when free space is low.
8. **Better labels**: ellipsis truncation, contrast-aware text colour, file-type icons for big files.
9. **Docker integration**: show `docker system df` breakdown (images, build cache, volumes) as boxes inside the Docker VM box.
10. **Growth timeline per folder**: store top-N folder sizes per sample and chart which folders grew this week.

## Launch setup (2026-10-22)
- Sparkle 2 auto-update (feed on GitHub Pages, EdDSA public key in project.yml), Check for Updates menu item.
- CI: .github/workflows ci.yml, release.yml (tag vX.Y.Z -> signed DMG + appcast), pages.yml; scripts/sign.sh, scripts/appcast.sh; site/ landing page.
- Notarization needs repo secrets (see README). Selftest needs a foreground GUI session; UI tests 3/3 and swift test 32/32 pass.
