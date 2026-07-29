// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit

/// Reliably restarts DockPeek.
///
/// macOS only re-evaluates Accessibility and Screen Recording permission at process
/// launch, so after the user flips those switches the *running* process still sees
/// "denied" — the only cure is a real relaunch. A naive `open` racing against
/// `terminate` often fails to bring the app back, so we hand off to a detached shell
/// that waits for this exact PID to die and *then* reopens the bundle.
enum Relauncher {
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        // Detached: wait until we're gone, then reopen (fresh -n instance).
        let script = "while /bin/kill -0 \(pid) >/dev/null 2>&1; do /bin/sleep 0.1; done; "
                   + "/usr/bin/open -n \"\(path)\""
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script]
        do {
            try task.run()
        } catch {
            NSLog("DockPeek: relaunch failed: \(error.localizedDescription)")
            return
        }
        // Let the watcher spin up before we exit.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NSApp.terminate(nil)
        }
    }
}
