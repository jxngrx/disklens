# CLAUDE.md

Read `SPEC.md` first, then `plansetup.md` (status, plan, decisions, log).
Build one phase at a time from SPEC.md's "Build phases" section and run the
acceptance checks before moving on. Continue from the first unchecked task in
plansetup.md.

- Core: `cd Packages/DiskLensCore && swift build && swift test`
- App: `xcodegen generate && xcodebuild -project DiskLens.xcodeproj -scheme DiskLens build`
- Never delete or clean anything outside `$TMPDIR/disklens-fixtures/` in tests.
