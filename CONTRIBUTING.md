# Contributing to DiskLens

Thanks for helping. Small, focused pull requests are easiest to review.

## Setup

```sh
brew install xcodegen
xcodegen generate            # the .xcodeproj is generated from project.yml
cd Packages/DiskLensCore && swift test
```

Open `DiskLens.xcodeproj` in Xcode 16+ (macOS 14+ target) to run the app.

## Before you open a pull request

- `swift test` in `Packages/DiskLensCore` passes.
- `xcodebuild -project DiskLens.xcodeproj -scheme DiskLens test` passes (UI tests need Automation permission the first time).
- New logic has a test. New cleanup rules have a fixture-based test.
- Edit `project.yml`, not the generated `.xcodeproj`, then run `xcodegen generate`.

## Safety rules for cleanup code

DiskLens deletes files, so these are not negotiable:

- Never require root, and never touch source files.
- Every deletion must be recoverable (quarantine) unless the user explicitly picks permanent delete.
- Re-check the rule at clean time; do not trust stale scan data.
- Tests may only create or delete inside `$TMPDIR/disklens-fixtures/`.

## Adding a cleanup rule

Rules live in `Packages/DiskLensCore/Sources/DiskLensCore/Rules/rules.json`. Add the rule, a fixture that matches it, and a test that proves it cleans and restores.

## Commits and PRs

- Write clear, imperative commit messages ("Add Gradle cache rule").
- Describe what changed and why in the PR, and attach a screenshot for UI changes.
- Do not commit certificates, keys or `.env` files. The release secrets live in GitHub Actions only.

## Reporting bugs

Open an issue with your macOS version, DiskLens version, and steps to reproduce. For crashes, attach the report from `~/Library/Logs/DiagnosticReports`.
