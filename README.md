# DiskLens

Native macOS treemap disk map that safely cleans developer junk (Xcode, node_modules, Docker, Gradle, Pods…) with an undo quarantine.

- Download: [latest release](https://github.com/shubhamjangra/disklens/releases/latest) · site: https://shubhamjangra.github.io/disklens/
- Build: `xcodegen generate && xcodebuild -project DiskLens.xcodeproj -scheme DiskLens build`
- Core tests: `cd Packages/DiskLensCore && swift test`

## Releasing
1. Add repo secrets: `DEVID_P12` (base64 Developer ID Application .p12), `DEVID_P12_PASSWORD`, `SPARKLE_PRIVATE_KEY` (`generate_keys -x key.txt`), optional `APPLE_ID`, `APPLE_APP_PASSWORD`, `APPLE_TEAM_ID` for notarization.
2. Enable Pages (Settings → Pages → Source: GitHub Actions).
3. `git tag v0.1.0 && git push --tags` — CI builds, signs, publishes the DMG and updates `appcast.xml`; installed apps auto-update.
