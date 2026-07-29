# Security Policy

## Reporting a vulnerability

Please **do not** open a public issue for security vulnerabilities.

Instead, report privately via GitHub's
[security advisory form](https://github.com/PrajjwalDatir/dock-preview-mac/security/advisories/new),
or email **in.prajj@gmail.com** with the details and steps to reproduce.

You can expect an initial response within a few days. Once a fix is available, a new
release will be published and the reporter credited (unless you prefer otherwise).

## Scope & threat model

DockPeek requests two macOS permissions:

- **Accessibility** — to read which Dock icon the cursor is over and its frame.
- **Screen Recording** — to capture window thumbnails via ScreenCaptureKit.

Captured images live only in memory to draw the preview. DockPeek makes **no network
requests** and stores no window contents on disk. Reports about data exfiltration,
unexpected network activity, or privilege escalation are especially welcome.

## Supported versions

The latest released version receives security fixes.
