// Karabiner-Elements runs this when ESC is released while its `aerial_screen_locked` variable is 1
// (karabiner/aerial-shuffle.json). Karabiner has already swallowed the ESC, so nothing reaches
// macOS that would wake the displays again. If the window server says the screen is in fact
// unlocked, the variable was stale: this ESC is lost, and the variable is corrected so the next
// one goes through.
import CoreGraphics
import Foundation
import os

let log = Logger(subsystem: "com.user.aerial-shuffle", category: "karabiner")
let locked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true
let p = Process()
if locked {
    log.notice("ESC on the lock screen: turning the displays off")
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    p.arguments = ["displaysleepnow"]
} else {
    log.error("ESC swallowed but the screen is unlocked: aerial_screen_locked was stale, correcting it")
    p.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        .deletingLastPathComponent().appendingPathComponent("screen-lock-watch")
    p.arguments = ["--sync"]
}
try? p.run()
p.waitUntilExit()
