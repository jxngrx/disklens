# DiskLens — build plan and log

## Status
- **Current phase:** 6
- **Current task:** 6.1 restore buttons
- **Last updated:** 2026-10-10 23:40 IST

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
- [ ] 6.1 Restore buttons (npm ci / yarn / pnpm / pod install) — dry-run tested
- [ ] 6.2 Mobile pack: AVDs, system images/NDKs, simulator runtimes, unavailable simulators
- [ ] 6.3 Menu bar free-space display + low-disk alert
- [ ] 6.4 `disklens` CLI (scan, top, rules, clean --dry-run, quarantine list/restore/purge)
- [ ] 6.5 Daemon mode with "keep N GB free" policy (dry-run tested)
- [ ] 6.6 Growth timeline (history file + Swift Charts)
- [ ] 6.7 Screenshots `docs/screenshots/phase-6/`
- [ ] 6.8 Tag `phase-6-done`

### Wrap-up
- [ ] 7.1 Final review section

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

## Deviations from spec

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

## Blockers & workarounds
- **XCUITest automation mode** (phase 2+): `xcodebuild test` fails with "The test runner failed to initialize for UI testing. (Underlying Error: Timed out while enabling automation mode.)". macOS wants an admin to authorise UI automation, and I may not use sudo. **You need to:** run `sudo automationmodetool enable-automationmode-without-authentication` once (or approve the prompt when running the tests from Xcode), then rerun the test command. Workaround: `DiskLens -selftest` drives the same model calls (hit test → activate, breadcrumb, back, parent) headlessly.
- Update (phase 4): XCUITest automation mode started working on a later run (approved/enabled outside this session, or the first-run timeout was transient). All UI tests now run; the `-selftest` fallback stays as a fast headless check.
- Screenshot runs launch the app in front of whatever you are doing; one capture ended up drilled into your home folder (a click landed on the window). No files were touched; noted so you know why the app may have flashed on screen.

## Questions for review

## Final review
