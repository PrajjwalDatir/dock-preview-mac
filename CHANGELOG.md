# Changelog

All notable changes to DockPeek are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] — 2026-07-29

### Added
- **In-app auto-updates via Sparkle.** A "Check for Updates…" menu item plus a
  daily background check against a signed appcast; updates install only if their
  EdDSA signature matches the app's embedded public key.
- **fastlane** lanes (`build`, `release`, `appcast`, `keys`) that wrap the
  Developer-ID + notarization + Sparkle-appcast release pipeline (this app can't use
  the App Store / TestFlight because its Accessibility + screen-capture features are
  incompatible with the App Sandbox those require).

### Changed
- Sparkle is vendored via `bin/fetch-sparkle.sh` and embedded + code-signed
  (inner-to-outer, hardened runtime) into the bundle by `build.sh`.

## [0.1.0] — 2026-07-29

First public release. 🎉

### Added
- Live window previews when hovering over running apps in the Dock, Windows-taskbar
  style, via the Accessibility API + ScreenCaptureKit.
- Dock-orientation-aware previews for **bottom, left, and right** Docks, with a notch
  pointing at the hovered icon.
- Header showing the app name and window count; click a thumbnail to raise that
  window; **Esc** to dismiss.
- Onboarding flow that explains the two required permissions, with live status and a
  reliable **Relaunch** button (permissions are only re-evaluated on launch).
- Menu-bar controls: Pause/Resume, Preferences, Launch at Login, Quit.
- Preferences: hover delay, thumbnail size, animation toggle, and a per-app on/off
  list.
- Accessibility: VoiceOver labels on preview cards, and automatic honoring of Reduce
  Motion and Reduce Transparency.
- Build & distribution tooling: `build.sh` (assemble + sign), `package.sh`
  (`.zip` + `.dmg`), `notarize.sh` (Developer ID + notarization), and a generated
  app icon (`tools/make_icon.swift`).

[0.1.1]: https://github.com/PrajjwalDatir/dock-preview-mac/releases/tag/v0.1.1
[0.1.0]: https://github.com/PrajjwalDatir/dock-preview-mac/releases/tag/v0.1.0
