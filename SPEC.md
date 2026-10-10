# Dev Disk Cleaner — Build Spec

Oct 10, 2026 · @AGENT

## Overview

Build a native macOS app that maps the whole disk as a drill-down treemap and then cleans developer junk safely. It starts on Macintosh HD with no root or sudo. Working name: **DiskLens** (rename freely).

- **Positioning:** a disk autopilot for mobile developers and always-on Mac build machines. Basic cache cleaning is already free in other tools (CodeCleaner, TidyDisk, ClearDisk, Kondo), so the edge is the treemap, mobile-dev depth, an undo window and automation.
- **Platform:** macOS 14+, Apple Silicon first, universal binary. Distributed outside the Mac App Store (Developer ID + notarization), because it needs Full Disk Access and must call tools like `xcrun` and `docker`.
- **Principle:** never require root, never touch source files, never delete without a recoverable step.

**How to use this doc with Claude CLI:** copy it into the repo as `SPEC.md`. Add a short `CLAUDE.md` that says to read `SPEC.md` first, build one phase at a time from the Build phases section, and run the acceptance checks before moving on. Ask Claude CLI for one phase per session, not the whole app at once.

## Treemap UI

The main screen is a treemap: each child of the current folder is a box whose area is proportional to its allocated size. Clicking a folder box zooms into it and shows its children as new boxes.

**Layout**

- Use the **squarified treemap** algorithm (Bruls, Huizing, van Wijk). It keeps boxes close to square, so labels stay readable.
- Sort children by size, descending, before layout. Keep that order stable while sizes are still growing during a scan, so boxes don't jump around.
- Merge children smaller than about 0.5% of the parent (or under 24×24 pt) into one **"N smaller items"** box. Clicking it shows those items as a list.
- Draw a faint second level inside each folder box (its biggest children) once that data is known. This previews what's inside before the click.
- Leave 2 pt gaps between boxes and use 6 pt corner radius.

**Each box shows**

- Name and size (for example `node_modules · 1.8 GB`), only when the box is big enough to fit the text
- Colour by category: dev artifact (by ecosystem), media, apps, system/other, and "cleanable" with an accent outline
- A small badge for safety level on cleanable items (Safe / Rebuildable / Caution)
- A shimmer or "scanning…" state while its size is still partial

**Navigation**

- Click a folder box to zoom in with a short animation (about 250 ms) from the box's rect to full size.
- A breadcrumb bar at the top (`Macintosh HD › Users › you › Projects`), where every segment is clickable.
- Back with Esc, ⌘\[ or a two-finger swipe; ⌘↑ goes to the parent.
- Hover shows a tooltip: full path, allocated size, item count, last modified, and for projects the last git commit date.
- Right-click menu: Reveal in Finder, Quick Look, Copy path, Clean (when a rule matches), Move to Trash (with confirmation).
- A sidebar list of the same children sorted by size, kept in sync with the treemap, for keyboard and accessibility users.

**Rendering**

- Draw the boxes with SwiftUI `Canvas`, not one SwiftUI view per box. Thousands of views are slow; one Canvas draws thousands of rects smoothly.
- Keep a flat array of laid-out rects for hit testing on click and hover.
- Re-run layout at most about 10 times per second while a scan streams in; animate size changes between layouts.

## Scan engine

One background scan walks the whole volume and streams results into the UI, while a priority queue always scans what the user is looking at first. That is the right version of "pre-scan the next level": a folder's size is only known once its *entire* subtree is walked, so listing one level ahead shows names but not sizes.

**Start point (no root needed)**

- Show the root as **Macintosh HD** but walk from `/` as the normal user. On modern macOS, `/Users`, `/Applications` and others are firmlinks into `/System/Volumes/Data`, so walking `/` reaches user data.
- Never cross a volume boundary: compare each directory's device id with the root's. Skip `/Volumes`, `/dev`, `/System/Volumes/*` (already reached via firmlinks, would double count), `/.fseventsd` and `/.Spotlight-V100`.
- A folder that returns permission denied becomes a **Restricted** box with unknown size. Show a one-time banner offering to open the Full Disk Access settings.
- Add a **System & other** box = volume used space (from `volumeTotalCapacity − volumeAvailableCapacity`) minus everything scanned. This covers the sealed system volume, local Time Machine snapshots and purgeable space, so the treemap total matches Finder.

**Priority scheduling (the pre-scan)**

1. Start breadth-first: list the root's direct children first, so boxes appear within a second with sizes still growing.
2. Every directory to scan goes into one priority queue. Priority, highest first: inside the folder currently on screen; children of the boxes on screen (so the next click is already sized); everything else.
3. When the user drills into a folder, re-prioritise: its unscanned subtree jumps to the front.
4. Run 6–8 worker tasks in parallel (SSD); each takes one directory at a time from the queue.
5. When a directory finishes, add its total to every ancestor. Each node has a state: `pending`, `partial`, `complete`; the UI shows partial sizes as "at least X".

**Fast metadata reads**

- Use `getattrlistbulk(2)`: one syscall returns name, type, inode, link count, allocated size, modified date and device id for many entries at once. It is much faster than `FileManager` resource values per file.
- Fall back to `fts`/`FileManager` only if `getattrlistbulk` fails for a directory.

**Getting sizes right**

- Use **allocated** size (blocks on disk), not logical size. This matches what freeing the space actually gives back.
- Hard links: when link count > 1, count the file only once per (device, inode). pnpm's store relies on hard links and is otherwise double counted.
- Don't follow symlinks.
- iCloud placeholder files (dataless) take almost no space. Read only their metadata, never their contents, because reading triggers a download.
- APFS clones share blocks and can't be detected cheaply. Label sizes from clone-heavy tools as "up to".
- `.app` and other bundles show as one box but stay drillable.

**Memory budget**

- Keep a node for every directory, but only the largest files per directory (files over 1 MB, or the top 50). Fold the rest into one "other files" entry with a count and total.
- Store nodes in flat arrays indexed by `Int32`, not as a class per node. Target: under 300 MB of RAM for a disk with 3 million files.

## Live updates and cached index

The app opens instantly from a saved index, then keeps it current with FSEvents, rescanning only the folders that changed.

**Saved index (instant launch)**

- After a full scan, write the tree to disk as a compact binary snapshot in `~/Library/Application Support/DiskLens/`. Include the FSEvents event id at the moment the scan finished.
- On launch, load the snapshot and show the treemap right away with a small "updated 2 h ago" label.
- Ask FSEvents for all changes since the saved event id. Rescan only those directories. If the history was lost (the event id is too old or the volume was replaced), fall back to a full background rescan while the old map stays visible.

**While the app runs**

- Subscribe to an `FSEventStream` on `/` with a latency of about 1 s and file-level events on.
- Collect changed paths, merge them (when several siblings change, rescan their parent once) and push those directories into the priority queue as high priority.
- Rescan a changed directory, compute the size difference and apply it to every ancestor. Boxes on screen animate to their new size.
- When FSEvents reports `MustScanSubDirs` or dropped events, rescan that whole subtree.
- Ignore the app's own writes (the index file and the quarantine folder) to avoid loops.

**After a clean**

- Don't wait for FSEvents: subtract the cleaned size from the tree immediately so the user sees the result at once, then let the FSEvents rescan confirm it.

**Background (optional, Pro)**

- A login item (`SMAppService`) keeps the index fresh while the main window is closed, which powers the menu bar free-space display and low-disk alerts.

## Dev cleaner layer

A rules file marks which boxes in the treemap are cleanable, how safe they are and how to clean them, so cleaning happens right from the map.

**Rules file** (`rules.json`, bundled and updatable without an app release)

| Target | Path or pattern | Safety | Clean with |
| --- | --- | --- | --- |
| Xcode DerivedData | `~/Library/Developer/Xcode/DerivedData/*` | Safe | quarantine; warn if Xcode is running |
| Old iOS DeviceSupport | `~/Library/Developer/Xcode/iOS DeviceSupport/*` | Safe | quarantine, keep the newest 2 |
| Unavailable simulators | (from `simctl`) | Safe | `xcrun simctl delete unavailable` |
| Old simulator runtimes | (from `simctl runtime list`) | Caution | `xcrun simctl runtime delete <id>` |
| Xcode Archives | `~/Library/Developer/Xcode/Archives/*` | Caution | quarantine; needed to symbolicate old crashes |
| Gradle caches | `~/.gradle/caches` | Rebuildable | `gradle --stop` first, then quarantine |
| Android AVDs | `~/.android/avd/*.avd` | Caution | `avdmanager delete avd -n <name>` |
| Android system images / NDKs | `$ANDROID_HOME/system-images`, `ndk/*` | Caution | `sdkmanager --uninstall`, only versions no project uses |
| CocoaPods cache | `~/Library/Caches/CocoaPods` | Rebuildable | `pod cache clean --all` |
| npm / yarn / pnpm | `~/.npm`, Yarn cache, pnpm store | Rebuildable | `npm cache clean --force`, `yarn cache clean`, `pnpm store prune` |
| Metro / watchman | `$TMPDIR/metro-*`, watchman state | Safe | quarantine; `watchman watch-del-all` |
| Homebrew | `brew --cache` | Safe | `brew cleanup -s` |
| Docker | Docker VM disk | Caution | `docker system df`, then `docker system prune` (never volumes by default) |

**Project discovery**

- During the scan, detect projects by marker files: `package.json`, `Podfile`, `build.gradle(.kts)`, `pubspec.yaml`, `*.xcodeproj`, `Cargo.toml`, `go.mod`.
- Per project, list its artifact folders: `node_modules`, `ios/Pods`, `ios/build`, `android/build`, `android/app/build`, `android/.cxx`, `.gradle`, `.dart_tool`, `target`, `.next`, `dist`.
- Staleness = the later of the last git commit date and the newest modified time of source files (artifact folders excluded). Don't use access time; it is unreliable on macOS.
- A **Projects** view lists projects by reclaimable size with "last worked on". Default filter: untouched for 30+ days.

**Safety rules**

- Only delete paths matched by a rule or a known artifact folder. Never touch source files or anything with uncommitted git changes outside artifact folders.
- Before cleaning, check whether the owning tool is running (Xcode, Simulator, Metro, Gradle daemon, Docker) and offer to quit or stop it.
- Prefer the tool's own command over deleting files when one exists (the table above).

**Quarantine and undo**

- "Clean" renames items into `~/.disklens-quarantine/<date>/` on the same volume. A rename is instant even for a 2 GB `node_modules`.
- Items stay there for 7 days (configurable) with one-click Restore, then are deleted for real. The UI shows space as "freed after 7 days" or offers "empty now".
- Paths cleaned through a tool command can't be quarantined; mark them as such in the confirm dialog.

**Restore (Pro)**

- For a cleaned project, detect the lockfile and package manager and offer one button: `npm ci` / `yarn install --frozen-lockfile` / `pnpm install --frozen-lockfile` / `pod install`.

## Tech stack and architecture

All scanning, sizing and cleaning lives in one Swift package, `DiskLensCore`, used by both the SwiftUI app and a later CLI; the UI only reads the tree store.

&#91;embedded content: module architecture · app layer over a shared core\]

The tree store is the single source of truth: the scanner and watcher write into it, the UI observes it, and the cleaner tags and updates it.

| Layer | Choice | Why |
| --- | --- | --- |
| Language / UI | Swift 6, SwiftUI, macOS 14+, `MenuBarExtra` | Native speed; `Canvas` handles thousands of boxes |
| Concurrency | Swift structured concurrency (`TaskGroup`), an `actor` for the queue | Safe parallel scanning with priority changes |
| File system | `getattrlistbulk`, `FSEventStream`, `statfs` via small C shims | Fastest metadata reads; live change feed |
| Index storage | Custom binary snapshot (`Data` + memory-mapped read) | Loads millions of nodes in well under a second |
| History (later) | SQLite via GRDB | Disk growth timeline |
| Charts | Swift Charts | Growth timeline, project sizes |
| CLI (later) | Same package + `swift-argument-parser` | CI and Mac-mini daemon tier |
| Updates | Sparkle | Outside the App Store |
| Licensing | Paddle or Lemon Squeezy | Trials, tax, regional pricing |
| Tests | Swift Testing + a fixture folder generator | Verifies sizes, hard links, permissions |

**Data model (tree store)**

```
struct NodeID: Hashable { let raw: Int32 }

enum NodeKind: UInt8 { case dir, file, bundle, otherFiles, restricted, systemOther }
enum ScanState: UInt8 { case pending, partial, complete }

// Stored as parallel arrays inside TreeStore, indexed by NodeID.raw
name: [String]            // interned
parent: [Int32]           // -1 for root
firstChild/nextSibling: [Int32]
kind: [NodeKind]
ownBytes: [UInt64]        // allocated bytes of files directly inside
totalBytes: [UInt64]      // ownBytes + all descendants (rolled up)
fileCount: [UInt32]
modified: [Int64]
state: [ScanState]
ruleID: [UInt16]          // 0 = no cleaning rule matched
```

**Suggested repo layout**

```
DiskLens/
  App/                 SwiftUI app target
    Treemap/           layout (squarify), Canvas view, hit testing
    Navigation/        breadcrumb, sidebar, zoom animation
    Clean/             projects view, confirm sheet, quarantine UI
  Packages/DiskLensCore/
    Scanner/           priority queue, workers, getattrlistbulk shim
    Tree/              TreeStore, roll-up, snapshot read/write
    Watcher/           FSEvents wrapper, change coalescing
    Rules/             rules.json loader, matcher, project detector
    Cleaner/           quarantine, tool commands, restore
  CLI/                 disklens command (later phase)
  SPEC.md, CLAUDE.md
```

## Build phases

Build in six phases, each ending with checks Claude CLI must pass before starting the next; phases 1–4 are the sellable MVP.

1. **Core scanner (no UI).** `DiskLensCore` with the `getattrlistbulk` walker, tree store, roll-up and a test CLI that prints the 20 biggest folders.
   - Check: totals for a generated fixture folder match `du -sk` within 1%.
   - Check: a folder with 10 hard links to one 100 MB file counts 100 MB once.
   - Check: permission-denied folders show as Restricted and the scan continues.
2. **Treemap UI.** Squarified layout, `Canvas` rendering, click-to-drill with zoom animation, breadcrumb, back navigation, hover tooltip, "smaller items" box.
   - Check: 5,000 boxes redraw at 60 fps; clicking any box opens the right folder.
3. **Progressive + priority scan.** Breadth-first start, priority queue, re-prioritise on drill-in, partial sizes with "at least" labels, System & other box.
   - Check: first boxes appear in under 1 s; a folder clicked mid-scan finishes before unrelated folders.
   - Check: the root total is within 2% of Finder's used space.
4. **Rules, projects and quarantine.** `rules.json`, cleanable tags and badges, Projects view, running-tool checks, quarantine with 7-day undo, license and trial.
   - Check: clean then restore leaves the folder byte-identical.
   - Check: nothing outside a rule's paths can ever be selected for cleaning.
5. **Live updates and saved index.** Binary snapshot, launch from snapshot, FSEvents catch-up and live subscription, instant subtract after clean.
   - Check: relaunch shows the map in under 1 s; creating a 1 GB file in a watched folder updates its box within 3 s.
6. **Pro and CLI.** Restore buttons, mobile pack (AVDs, system images, simulator runtimes), menu bar alerts, `disklens` CLI and daemon with "keep N GB free" policies, growth timeline.

**Performance targets** (Apple Silicon, internal SSD; measure and adjust after phase 3)

| Metric | Target |
| --- | --- |
| First boxes on screen | under 1 s |
| Full scan, about 1 million files | under 30 s |
| Memory, about 3 million files | under 300 MB |
| Launch from saved index | under 1 s |
| Live change reflected | under 3 s |

**First prompt for Claude CLI**

```
Read SPEC.md. Implement Phase 1 only: the DiskLensCore Swift package
with the getattrlistbulk walker, TreeStore and size roll-up, plus a tiny
test CLI. Write tests for the Phase 1 checks and make them pass.
Don't start any UI yet.
```
