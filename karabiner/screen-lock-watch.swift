// Keeps Karabiner's `aerial_screen_locked` variable in step with the screen lock, so the ESC rule
// in aerial-shuffle.json can swallow ESC while locked. Two macOS 27 facts make this necessary:
// no ordinary app receives key presses on the lock screen (only Karabiner, which owns the
// keyboard, sees them), and an ESC passed through to macOS wakes the displays again 0.4 s after
// they turn off (measured 2026-10-05: "Display is asleep on activity tickle"). So the decision to
// swallow ESC has to be made inside Karabiner, and Karabiner can't tell whether the screen is
// locked on its own. Runs as the LaunchAgent ai.openclaw.aerial-shuffle-lockwatch.
import CoreGraphics
import Foundation
import os

let log = Logger(subsystem: "com.user.aerial-shuffle", category: "lockwatch")
let cli = "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"

func sessionLocked() -> Bool {
    (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true
}

func setLocked(_ locked: Bool, _ why: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: cli)
    p.arguments = ["--set-variables", "{\"aerial_screen_locked\":\(locked ? 1 : 0)}"]
    do {
        try p.run()
        p.waitUntilExit()
        log.notice("\(why, privacy: .public): aerial_screen_locked = \(locked ? 1 : 0, privacy: .public), karabiner_cli exit \(p.terminationStatus, privacy: .public)")
    } catch {
        log.error("\(why, privacy: .public): karabiner_cli did not run: \(error.localizedDescription, privacy: .public)")
    }
}

let center = DistributedNotificationCenter.default()
center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
    setLocked(true, "screenIsLocked")
}
center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
    setLocked(false, "screenIsUnlocked")
}
if CommandLine.arguments.dropFirst().first == "--sync" {
    setLocked(sessionLocked(), "sync")       // one-shot, used by esc-if-locked to correct a stale value
    exit(0)
}
setLocked(sessionLocked(), "start")
RunLoop.main.run()
