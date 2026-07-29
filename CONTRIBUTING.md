# Contributing to DockPeek

Thanks for your interest in improving DockPeek! 🎉

## Ground rules

- By contributing, you agree your work is licensed under **AGPL-3.0-or-later**
  (the project license).
- Be kind — see the [Code of Conduct](CODE_OF_CONDUCT.md).

## Getting set up

Requirements: macOS 14+ and a recent Swift toolchain (Xcode 15+).

```bash
git clone https://github.com/PrajjwalDatir/DockPeek.git
cd DockPeek
swift build          # debug build
./build.sh           # assemble + sign dock-preview.app
open ./dock-preview.app
```

Grant **Accessibility** and **Screen Recording** when prompted.

## Project layout

See the "Layout" section of the [README](README.md#layout). In short:
`DockObserver` (hover detection) → `WindowService` (capture) → `PreviewController`
(the floating panel). `AppDelegate` wires them together.

## Making a change

1. Create a branch off `main`.
2. Keep changes focused; match the surrounding code style.
3. Add the SPDX header to any new Swift file:
   `// SPDX-License-Identifier: AGPL-3.0-or-later`
4. `swift build` should succeed with **no new warnings**.
5. Manually verify hover → preview still works. If you can, test with the Dock on
   the **bottom, left, and right**, and with apps that have one vs. many windows.
6. Open a PR using the template and describe what you tested.

## Testing tips

There's no automated UI test for the hover/capture path (it needs real permissions
and a live Dock), so manual verification matters. Useful things to check:

- Multiple monitors, especially with different resolutions.
- Fullscreen apps and minimized windows.
- Reduce Motion / Reduce Transparency (System Settings → Accessibility).

## Reporting bugs / ideas

Use the issue templates. For security issues, please follow [SECURITY.md](SECURITY.md).
