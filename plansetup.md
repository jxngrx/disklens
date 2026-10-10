# DiskLens — build plan and log

## Status
- **Current phase:** 2
- **Current task:** 2.1 XcodeGen project
- **Last updated:** 2026-10-10 22:58 IST

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
- [ ] 2.1 XcodeGen `project.yml`, app target + UI test target, builds with `xcodebuild`
- [x] 2.2 Squarified layout + "N smaller items" merge + second-level preview
- [ ] 2.3 `Canvas` renderer: category colours, labels, badges, 2 pt gaps, 6 pt radius, partial shimmer
- [ ] 2.4 Hit testing, click-to-drill with ~250 ms zoom animation
- [ ] 2.5 Breadcrumb, back (Esc, ⌘[, swipe), ⌘↑ parent
- [ ] 2.6 Hover tooltip (path, size, count, modified, git date), right-click menu
- [ ] 2.7 Sidebar list in sync; smaller-items list sheet
- [ ] 2.8 Check: 5,000 boxes redraw at 60 fps (measured)
- [ ] 2.9 Check: clicking any box opens the right folder (hit-test unit test + XCUITest)
- [ ] 2.10 XCUITest: drill-down, breadcrumb, back navigation
- [ ] 2.11 Screenshots `docs/screenshots/phase-2/`, fix layout issues
- [ ] 2.12 Tag `phase-2-done`

### Phase 3 — Progressive + priority scan
- [ ] 3.1 Priority queue actor (focus subtree first), re-prioritise on drill-in
- [ ] 3.2 Streaming UI updates ≤10/s, stable order, "at least" labels for partial
- [ ] 3.3 System & other box from volume capacity
- [ ] 3.4 Full Disk Access banner for Restricted
- [ ] 3.5 Check: first boxes in < 1 s (measured)
- [ ] 3.6 Check: folder focused mid-scan finishes before unrelated folders
- [ ] 3.7 Check: root total within 2% of Finder used space
- [ ] 3.8 Screenshots `docs/screenshots/phase-3/`
- [ ] 3.9 Tag `phase-3-done`

### Phase 4 — Rules, projects, quarantine
- [ ] 4.1 `rules.json` (bundled resource) + loader + matcher
- [ ] 4.2 Project detection (markers), artifact folders, staleness
- [ ] 4.3 Cleanable tags + badges in treemap
- [ ] 4.4 Quarantine (rename into `~/.disklens-quarantine/<date>/`), restore, purge after N days, empty now
- [ ] 4.5 Tool commands with dry-run mode; running-tool checks
- [ ] 4.6 Projects view (reclaimable, last worked on, 30+ day filter)
- [ ] 4.7 Clean confirm sheet (tool-command items marked non-quarantinable)
- [ ] 4.8 License + trial (stub)
- [ ] 4.9 Check: clean then restore is byte-identical
- [ ] 4.10 Check: nothing outside a rule's paths can be selected for cleaning
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

## Decisions
- No C shim target: `getattrlistbulk`, `statfs`, FSEvents are all callable from Swift via Darwin/CoreServices; one less target.
- Root walk allows two device ids: `/` (sealed system snapshot) and `/System/Volumes/Data`. A strict "same device as `/`" check would skip `/Users` etc., because firmlinks resolve to the Data volume's device.
- Queue is LIFO (depth-first) inside each priority tier: subtrees finish sooner and the queue stays small. Root is still listed first, so top-level boxes appear immediately.
- File folding: a file gets its own node only if it is ≥ 1 MB and in the folder's top 50; everything else folds into "N other files". Keeps memory down (spec wording "over 1 MB, or the top 50" was ambiguous).
- Hard links: first directory that sees a (device, inode) owns its bytes; rescans of that same directory keep counting it. Duplicates inside one listing are counted once.
- One `NSLock` around the whole TreeStore (simple, measured fine for 8 workers).
- Detached nodes (deleted folders) stay in the arrays as garbage until the next snapshot save.
- Squarify + hit testing live in DiskLensCore (`Layout/`) instead of `App/Treemap` so `swift test` covers them without an app test bundle.

## Deviations from spec

## Test results
### Phase 1
- `cd Packages/DiskLensCore && swift test` — 6 passed, 0 failed (du within 1%, 10 hard links = 100 MB once, restricted + scan continues, symlinks not followed, small-file folding, rescan diff).
- `swift build -c release && /usr/bin/time -l .build/release/disklens top /` — 1.80 M files in 12.07 s (target: 1 M files < 30 s ✔), 174 MB max RSS for 1.8 M files (extrapolates to ~290 MB at 3 M; target < 300 MB, tight). 457 restricted folders (Terminal lacks Full Disk Access).

## Blockers & workarounds

## Questions for review

## Final review
