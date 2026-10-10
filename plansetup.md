# DiskLens — build plan and log

## Status
- **Current phase:** 4
- **Current task:** 4.3 cleanable tags in app
- **Last updated:** 2026-10-10 23:25 IST

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
- [ ] 4.3 Cleanable tags + badges in treemap
- [x] 4.4 Quarantine (rename into `~/.disklens-quarantine/<date>/`), restore, purge after N days, empty now
- [x] 4.5 Tool commands with dry-run mode; running-tool checks
- [ ] 4.6 Projects view (reclaimable, last worked on, 30+ day filter)
- [ ] 4.7 Clean confirm sheet (tool-command items marked non-quarantinable)
- [ ] 4.8 License + trial (stub)
- [x] 4.9 Check: clean then restore is byte-identical
- [x] 4.10 Check: nothing outside a rule's paths can be selected for cleaning
- [ ] 4.11 XCUITest: clean confirm sheet
- [ ] 4.12 Screenshots `docs/screenshots/phase-4/`
- [ ] 4.13 Tag `phase-4-done`

### Phase 5 — Live updates + saved index
- [ ] 5.1 Binary snapshot write/read (memory-mapped) with FSEvents id + volume UUID
- [ ] 5.2 Launch from snapshot with "updated X ago" label
- [ ] 5.3 FSEvents catch-up since saved id; full rescan fallback
- [ ] 5.4 Live FSEventStream, coalescing, directory rescan with diff roll-up, MustScanSubDirs
- [ ] 5.5 Ignore own writes; instant subtract after clean
- [ ] 5.6 Check: relaunch shows map in < 1 s
- [ ] 5.7 Check: 1 GB file in watched folder updates within 3 s
- [ ] 5.8 Screenshots `docs/screenshots/phase-5/`
- [ ] 5.9 Tag `phase-5-done`

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

## Blockers & workarounds
- **XCUITest automation mode** (phase 2+): `xcodebuild test` fails with "The test runner failed to initialize for UI testing. (Underlying Error: Timed out while enabling automation mode.)". macOS wants an admin to authorise UI automation, and I may not use sudo. **You need to:** run `sudo automationmodetool enable-automationmode-without-authentication` once (or approve the prompt when running the tests from Xcode), then rerun the test command. Workaround: `DiskLens -selftest` drives the same model calls (hit test → activate, breadcrumb, back, parent) headlessly.

## Questions for review

## Final review
