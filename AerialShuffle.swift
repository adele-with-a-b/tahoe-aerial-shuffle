import AppKit
import ServiceManagement
import ApplicationServices

// Two keys, nothing else. On macOS 27 the system shuffles the aerials itself (Screen Saver →
// Shuffle All Aerials, Continuously) and the desktop stills are a plain folder shuffle, so this
// app only adds what macOS doesn't do:
//   Ctrl+Cmd+Q       → start the screensaver, which plays on every display. A plain macOS lock
//                      plays video only on the main display.
//   ESC while locked → turn the displays off. macOS does this on the plain lock screen, but not
//                      while the screensaver is showing.
// The README ("macOS 27") explains why the aerial switching and the 60 Hz pin were removed.

// MARK: - Lock Screen Handler

class LockScreenHandler {
    var tapRef: CFMachPort?
    var isScreenLocked = false
    private var retryTimer: Timer?

    func start() {
        attemptTapCreation()
        listenForLockState()
    }

    func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        if let tap = tapRef { CGEvent.tapEnable(tap: tap, enable: false) }
    }

    func startScreenSaver() {
        let t = Process(); t.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        t.arguments = ["-a", "ScreenSaverEngine"]; try? t.run()
    }

    private func attemptTapCreation() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let handler = Unmanaged<LockScreenHandler>.fromOpaque(refcon).takeUnretainedValue()

                if type == .tapDisabledByTimeout {
                    if let tap = handler.tapRef { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passRetained(event)
                }

                if type == .keyDown {
                    let keycode = event.getIntegerValueField(.keyboardEventKeycode)
                    let flags = event.flags

                    // Intercept Ctrl+Cmd+Q (lock screen shortcut)
                    if keycode == 0x0C && flags.contains(.maskCommand) && flags.contains(.maskControl) {
                        handler.startScreenSaver()
                        return nil // consume the event
                    }

                    // ESC -> display sleep (only when screen is locked)
                    if keycode == 0x35 && handler.isScreenLocked {
                        NSLog("ESC while locked: putting the displays to sleep")
                        DispatchQueue.global().async {
                            let p = Process()
                            p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
                            p.arguments = ["displaysleepnow"]
                            try? p.run()
                        }
                    }
                }

                return Unmanaged.passRetained(event)
            },
            userInfo: refcon
        )

        if let tap = tap {
            retryTimer?.invalidate()
            retryTimer = nil
            tapRef = tap
            let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        } else {
            // No Accessibility permission — retry silently, menu shows warning
            if retryTimer == nil {
                retryTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
                    self?.attemptTapCreation()
                }
            }
        }
    }

    // The window server's own lock flag. Present (true) only while the session is locked.
    func sessionIsLocked() -> Bool {
        let d = CGSessionCopyCurrentDictionary() as? [String: Any]
        return (d?["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    func listenForLockState() {
        let center = DistributedNotificationCenter.default()
        for name in ["com.apple.screensaver.didstart", "com.apple.screenIsLocked"] {
            center.addObserver(forName: NSNotification.Name(name), object: nil, queue: .main) { [weak self] _ in
                self?.isScreenLocked = true
            }
        }
        // The screensaver stopping doesn't mean the screen unlocked: with "require password
        // immediately" the password prompt is still up, and ESC there should still turn the
        // displays off. screenIsUnlocked only fires when the login window actually appeared, so
        // ask the window server whether the session is still locked.
        center.addObserver(forName: NSNotification.Name("com.apple.screensaver.didstop"), object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.isScreenLocked = self.sessionIsLocked()
            NSLog("Screensaver stopped; session locked = \(self.isScreenLocked)")
        }
        center.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.isScreenLocked = false
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var lockHandler: LockScreenHandler!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let appPath = Bundle.main.bundlePath
        if !appPath.hasPrefix("/Applications") {
            let alert = NSAlert()
            alert.messageText = "Move to Applications?"
            alert.informativeText = "AerialShuffle works best from the Applications folder."
            alert.addButton(withTitle: "Move & Relaunch")
            alert.addButton(withTitle: "Continue Anyway")
            if alert.runModal() == .alertFirstButtonReturn {
                let dest = "/Applications/AerialShuffle.app"
                try? FileManager.default.removeItem(atPath: dest)
                do {
                    try FileManager.default.moveItem(atPath: appPath, toPath: dest)
                    Process.launchedProcess(launchPath: "/usr/bin/open", arguments: [dest])
                    NSApp.terminate(nil); return
                } catch {}
            }
        }

        NSApp.setActivationPolicy(.accessory)
        lockHandler = LockScreenHandler()
        lockHandler.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mountain.2.fill", accessibilityDescription: "Aerial Shuffle")
            button.action = #selector(showMenu)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc func showMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let li = NSMenuItem(title: "Start at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        li.target = self
        li.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(li)

        if !AXIsProcessTrusted() {
            menu.addItem(NSMenuItem.separator())
            let pw = NSMenuItem(title: "⚠️ Grant Accessibility (needed for the keys)", action: #selector(openAccessibility), keyEquivalent: "")
            pw.target = self; menu.addItem(pw)
        }

        menu.addItem(NSMenuItem.separator())

        let ui = NSMenuItem(title: "Uninstall", action: #selector(doUninstall), keyEquivalent: "")
        ui.target = self; menu.addItem(ui)

        let qi = NSMenuItem(title: "Quit Aerial Shuffle", action: #selector(doQuit), keyEquivalent: "q")
        qi.target = self; menu.addItem(qi)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc func toggleLaunchAtLogin() {
        if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.unregister() }
        else { try? SMAppService.mainApp.register() }
    }

    @objc func openAccessibility() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]
        try? p.run()
    }

    @objc func doUninstall() {
        let alert = NSAlert()
        alert.messageText = "Uninstall AerialShuffle?"
        alert.informativeText = "This removes the app, its login item, and its permissions. Your wallpaper and screen saver settings are not changed."
        alert.addButton(withTitle: "Uninstall"); alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        lockHandler.stop()
        try? SMAppService.mainApp.unregister()
        // Full Disk Access is from older versions, which edited the aerial shuffle database.
        for service in ["Accessibility", "PostEvent", "SystemPolicyAllFiles", "SystemPolicyAppData"] {
            let t = Process(); t.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            t.arguments = ["reset", service, "com.user.aerial-shuffle"]; try? t.run(); t.waitUntilExit()
        }
        try? FileManager.default.removeItem(atPath: Bundle.main.bundlePath)
        NSApp.terminate(nil)
    }

    @objc func doQuit() {
        lockHandler.stop()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        lockHandler?.stop()
    }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
