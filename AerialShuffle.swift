import AppKit
import SwiftUI
import SQLite3
import ServiceManagement
import ApplicationServices

// MARK: - Categories

struct AerialCategory: Identifiable, Hashable {
    let id: String
    let name: String
    let keywords: [String]
}

let aerialCategories: [AerialCategory] = [
    AerialCategory(id: "landscape", name: "Landscape", keywords: [
        "tahoe", "sequoia", "yosemite", "patagonia", "iceland", "scotland", "hawaii",
        "grand canyon", "monument valley", "cazadero", "redwood", "sonoma", "wildflower",
        "goa", "liwa", "oregon", "waves", "beach", "field", "river", "greenland",
        "cloud", "sunrise", "morning", "evening", "night", "day", "mac blue", "mac pink",
        "mac purple", "mac yellow", "tea garden"
    ]),
    AerialCategory(id: "cityscape", name: "Cityscape", keywords: [
        "york", "london", "dubai", "hong kong", "san francisco", "los angeles", "vegas"
    ]),
    AerialCategory(id: "underwater", name: "Underwater", keywords: [
        "jelly", "coral", "shark", "seal", "ray", "barracuda", "kelp", "fish",
        "star", "bumphead", "dolphin", "whale", "octopus", "palau"
    ]),
    AerialCategory(id: "earth", name: "Earth", keywords: [
        "africa", "middle east", "asia", "europe", "atlantic", "caribbean",
        "iran", "afghanistan", "korea", "japan", "spain", "france", "alps",
        "himalayas", "india", "australia", "antarctica", "ireland", "north asia",
        "south africa"
    ])
]

func categorize(_ name: String) -> String {
    let lower = name.lowercased()
    for cat in aerialCategories where cat.id != "landscape" {
        if cat.keywords.contains(where: { lower.contains($0) }) { return cat.id }
    }
    return "landscape"
}

// MARK: - Event Detector

class EventDetector {
    var sawMouseEvent = false
    var lastLaunch: Date = .distantPast
    var tapRef: CFMachPort?
    weak var appState: AppState?

    func start() {
        let mask: CGEventMask = (1 << 14) | (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) | (1 << CGEventType.otherMouseUp.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        tapRef = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let d = Unmanaged<EventDetector>.fromOpaque(refcon).takeUnretainedValue()

                if type == .tapDisabledByTimeout {
                    if let tap = d.tapRef { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passRetained(event)
                }

                let t = type
                if t == .leftMouseDown || t == .rightMouseDown || t == .otherMouseDown ||
                   t == .leftMouseUp || t == .rightMouseUp || t == .otherMouseUp {
                    d.sawMouseEvent = true
                }

                // ESC -> display sleep
                if type == .keyDown && event.getIntegerValueField(.keyboardEventKeycode) == 0x35 {
                    DispatchQueue.global().async {
                        let p = Process()
                        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
                        p.arguments = ["displaysleepnow"]
                        try? p.run()
                    }
                }

                // Power button -> screensaver + shift
                if type.rawValue == 14 && event.flags.rawValue == 0 {
                    let now = Date()
                    if now.timeIntervalSince(d.lastLaunch) > 2.0 {
                        d.sawMouseEvent = false
                        DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) {
                            if !d.sawMouseEvent {
                                d.lastLaunch = Date()
                                d.appState?.launchScreensaverThenDismiss()
                            }
                        }
                    }
                }
                return Unmanaged.passRetained(event)
            },
            userInfo: refcon
        )
        guard let tap = tapRef else { return }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}

// MARK: - App State

class AppState: ObservableObject {
    @Published var interval: Int = 300
    @Published var desktopCategories: Set<String> = Set(aerialCategories.map { $0.id })
    @Published var aerialCats: Set<String> = Set(aerialCategories.map { $0.id })
    @Published var aerialCount: Int = 0
    @Published var desktopFilteredCount: Int = 0
    @Published var aerialFilteredCount: Int = 0
    @Published var currentName: String = ""
    @Published var launchAtLogin: Bool = false

    let home = FileManager.default.homeDirectoryForCurrentUser.path
    var configDir: String { "\(home)/Library/Application Support/AerialShuffle" }
    var configFile: String { "\(configDir)/config.json" }
    var stillsDir: String { "\(home)/Library/Application Support/com.apple.wallpaper/aerials/stills" }
    var activeDir: String { "\(configDir)/active" }
    var videosDir: String { "\(home)/Library/Application Support/com.apple.wallpaper/aerials/videos" }
    var manifestPath: String { "\(home)/Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json" }
    var dbPath: String { "\(home)/Library/Containers/com.apple.wallpaper.extension.aerials/Data/Library/Application Support/Shuffle/ShuffleOrder.db" }

    struct AerialInfo { let id, name, shotID, category: String }

    lazy var allAerials: [AerialInfo] = {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = json["assets"] as? [[String: Any]] else { return [] }
        return assets.compactMap { a in
            guard let id = a["id"] as? String, let name = a["accessibilityLabel"] as? String,
                  let shotID = a["shotID"] as? String else { return nil }
            return AerialInfo(id: id, name: name, shotID: shotID, category: categorize(name))
        }
    }()

    lazy var idToAerial: [String: AerialInfo] = {
        Dictionary(uniqueKeysWithValues: allAerials.map { ($0.id, $0) })
    }()

    var recentIDs: [String] = []

    init() {
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: activeDir, withIntermediateDirectories: true)
        loadConfig()
        rebuildActiveFrames()
        updateCounts()
        updateCurrentName()
        enablePowerButtonIntercept()
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func enablePowerButtonIntercept() {
        let t = Process(); t.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        t.arguments = ["write", "com.apple.loginwindow", "DisableScreenLockImmediate", "-bool", "YES"]
        try? t.run(); t.waitUntilExit()
    }

    func disablePowerButtonIntercept() {
        let t = Process(); t.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        t.arguments = ["delete", "com.apple.loginwindow", "DisableScreenLockImmediate"]
        try? t.run(); t.waitUntilExit()
    }

    func launchScreensaverThenDismiss() {
        DispatchQueue.global().async {
            let t = Process(); t.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            t.arguments = ["-a", "ScreenSaverEngine"]; try? t.run(); t.waitUntilExit()
            Thread.sleep(forTimeInterval: 0.5)
            let s = CGEvent(keyboardEventSource: nil, virtualKey: 0x38, keyDown: true)
            s?.post(tap: .cghidEventTap)
            let u = CGEvent(keyboardEventSource: nil, virtualKey: 0x38, keyDown: false)
            u?.post(tap: .cghidEventTap)
        }
    }

    func loadConfig() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configFile)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let i = json["interval"] as? Int { interval = i }
        if let c = json["desktopCategories"] as? [String] { desktopCategories = Set(c) }
        if let c = json["aerialCategories"] as? [String] { aerialCats = Set(c) }
    }

    func saveConfig() {
        let json: [String: Any] = ["interval": interval, "desktopCategories": Array(desktopCategories), "aerialCategories": Array(aerialCats)]
        if let data = try? JSONSerialization.data(withJSONObject: json) { try? data.write(to: URL(fileURLWithPath: configFile)) }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; launchAtLogin = enabled }
        catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    func rebuildActiveFrames() {
        if let files = try? FileManager.default.contentsOfDirectory(atPath: activeDir) {
            for f in files { try? FileManager.default.removeItem(atPath: "\(activeDir)/\(f)") }
        }
        let stillIDs = Set((try? FileManager.default.contentsOfDirectory(atPath: stillsDir))?.filter { $0.hasSuffix(".png") }.map { $0.replacingOccurrences(of: ".png", with: "") } ?? [])
        var count = 0
        for a in allAerials where desktopCategories.contains(a.category) && stillIDs.contains(a.id) {
            try? FileManager.default.createSymbolicLink(atPath: "\(activeDir)/\(a.id).png", withDestinationPath: "\(stillsDir)/\(a.id).png")
            count += 1
        }
        desktopFilteredCount = count
    }

    func shuffle() {
        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT ZCURRENTID FROM ZPERSISTENTSHUFFLEORDER WHERE Z_PK=1", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) else { sqlite3_finalize(stmt); return }
        let current = String(cString: c); sqlite3_finalize(stmt)
        let fileIDs = Set((try? FileManager.default.contentsOfDirectory(atPath: videosDir))?.filter { $0.hasSuffix(".mov") }.map { $0.replacingOccurrences(of: ".mov", with: "") } ?? [])
        let ids = allAerials.filter { fileIDs.contains($0.id) && aerialCats.contains($0.category) }.map { $0.id }
        guard ids.count >= 2 else { return }
        let candidates = ids.filter { !recentIDs.contains($0) && $0 != current }
        let pool = candidates.isEmpty ? ids.filter { $0 != current } : candidates
        guard let next = pool.randomElement() else { return }
        recentIDs.append(next); if recentIDs.count > 20 { recentIDs.removeFirst() }
        sqlite3_exec(db, "UPDATE ZPERSISTENTSHUFFLEORDER SET ZCURRENTID='\(next)' WHERE Z_PK=1", nil, nil, nil)
        let t = Process(); t.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        t.arguments = ["-9", "WallpaperAerialsExtension"]; try? t.run()
    }

    func updateCounts() {
        aerialCount = (try? FileManager.default.contentsOfDirectory(atPath: stillsDir))?.filter { $0.hasSuffix(".png") }.count ?? 0
        desktopFilteredCount = (try? FileManager.default.contentsOfDirectory(atPath: activeDir))?.filter { $0.hasSuffix(".png") }.count ?? 0
        let fileIDs = Set((try? FileManager.default.contentsOfDirectory(atPath: videosDir))?.filter { $0.hasSuffix(".mov") }.map { $0.replacingOccurrences(of: ".mov", with: "") } ?? [])
        aerialFilteredCount = allAerials.filter { fileIDs.contains($0.id) && aerialCats.contains($0.category) }.count
    }

    func updateCurrentName() {
        guard let screen = NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return }
        let filename = url.deletingPathExtension().lastPathComponent
        if let a = idToAerial[filename] {
            let same = allAerials.filter { $0.name == a.name }
            if same.count > 1, let idx = same.sorted(by: { $0.shotID < $1.shotID }).firstIndex(where: { $0.id == a.id }) {
                currentName = "\(a.name) (\(idx + 1) of \(same.count))"; return
            }
            currentName = a.name
        }
    }

    func uninstall() {
        disablePowerButtonIntercept()
        try? SMAppService.mainApp.unregister()
        try? FileManager.default.removeItem(atPath: configDir)
        // Remove TCC entries via tccutil
        for service in ["Accessibility", "ListenEvent", "SystemPolicyAllFiles"] {
            let t = Process(); t.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            t.arguments = ["reset", service, "com.user.aerial-shuffle"]; try? t.run(); t.waitUntilExit()
        }
        try? FileManager.default.removeItem(atPath: Bundle.main.bundlePath)
        NSApp.terminate(nil)
    }

    static func needsPermissions() -> Bool {
        return !AXIsProcessTrusted()
    }
}

// Permission request uses the native macOS system dialog via AXIsProcessTrustedWithOptions

// MARK: - Checkbox Menu Item (NSView-based, doesn't close menu)

class ToggleMenuItemView: NSView {
    var button: NSButton!
    var toggleAction: (() -> Void)?

    init(title: String, checked: Bool, isRadio: Bool = false, toggle: @escaping () -> Void) {
        super.init(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        self.toggleAction = toggle

        if isRadio {
            button = NSButton(radioButtonWithTitle: title, target: self, action: #selector(toggled))
        } else {
            button = NSButton(checkboxWithTitle: title, target: self, action: #selector(toggled))
        }
        button.state = checked ? .on : .off
        button.font = .menuFont(ofSize: 14)
        button.frame = NSRect(x: 18, y: 0, width: 230, height: 24)
        addSubview(button)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc func toggled() {
        toggleAction?()
    }
}

func makeCheckboxItem(title: String, checked: Bool, toggle: @escaping () -> Void) -> NSMenuItem {
    let item = NSMenuItem()
    item.view = ToggleMenuItemView(title: title, checked: checked, toggle: toggle)
    return item
}

func makeRadioItem(title: String, checked: Bool, toggle: @escaping () -> Void) -> NSMenuItem {
    let item = NSMenuItem()
    item.view = ToggleMenuItemView(title: title, checked: checked, isRadio: true, toggle: toggle)
    return item
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var state: AppState!
    var eventDetector: EventDetector!
    var shuffleTimer: Timer?

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

        if !AXIsProcessTrusted() {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
        }
        // Always open Input Monitoring + Full Disk Access on first run
        if !UserDefaults.standard.bool(forKey: "setupDone") {
            UserDefaults.standard.set(true, forKey: "setupDone")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                    NSWorkspace.shared.open(url)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        finishLaunch()
    }

    func finishLaunch() {
        NSApp.setActivationPolicy(.accessory)
        state = AppState()
        eventDetector = EventDetector()
        eventDetector.appState = state
        eventDetector.start()
        startShuffleTimer()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mountain.2.fill", accessibilityDescription: "Aerial Shuffle")
            button.action = #selector(showMenu)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    func startShuffleTimer() {
        shuffleTimer?.invalidate()
        shuffleTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(state.interval), repeats: true) { [weak self] _ in
            self?.state.shuffle()
        }
    }

    @objc func showMenu() {
        state.updateCurrentName()
        state.updateCounts()

        let menu = NSMenu()
        menu.autoenablesItems = false

        // Desktop Photo Shuffle
        let dt = NSMenuItem()
        let dtLabel = NSTextField(labelWithString: "")
        dtLabel.font = .boldSystemFont(ofSize: 13)
        dtLabel.textColor = .labelColor
        func updateDT() { dtLabel.stringValue = "Desktop Photo Shuffle (\(self.state.desktopFilteredCount)/\(self.state.aerialCount))" }
        updateDT()
        let dtView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        dtLabel.frame = NSRect(x: 18, y: 2, width: 280, height: 20)
        dtView.addSubview(dtLabel)
        dt.view = dtView
        menu.addItem(dt)

        for cat in aerialCategories {
            menu.addItem(makeCheckboxItem(title: "  \(cat.name)", checked: state.desktopCategories.contains(cat.id)) { [weak self] in
                guard let s = self?.state else { return }
                if s.desktopCategories.contains(cat.id) { s.desktopCategories.remove(cat.id) } else { s.desktopCategories.insert(cat.id) }
                s.saveConfig(); s.rebuildActiveFrames(); s.updateCounts()
                updateDT()
            })
        }

        menu.addItem(NSMenuItem.separator())

        // Lock Screen Aerials
        let at = NSMenuItem()
        let atLabel = NSTextField(labelWithString: "")
        atLabel.font = .boldSystemFont(ofSize: 13)
        atLabel.textColor = .labelColor
        func updateAT() { atLabel.stringValue = "Lock Screen Aerials (\(self.state.aerialFilteredCount)/\(self.state.aerialCount))" }
        updateAT()
        let atView = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        atLabel.frame = NSRect(x: 18, y: 2, width: 280, height: 20)
        atView.addSubview(atLabel)
        at.view = atView
        menu.addItem(at)

        for cat in aerialCategories {
            menu.addItem(makeCheckboxItem(title: "  \(cat.name)", checked: state.aerialCats.contains(cat.id)) { [weak self] in
                guard let s = self?.state else { return }
                if s.aerialCats.contains(cat.id) { s.aerialCats.remove(cat.id) } else { s.aerialCats.insert(cat.id) }
                s.saveConfig(); s.updateCounts()
                updateAT()
            })
        }

        let ii = NSMenuItem(title: "  Shuffle Every", action: nil, keyEquivalent: "")
        let isub = NSMenu()
        var radioViews: [ToggleMenuItemView] = []
        let intervals: [(String, Int)] = [("5 seconds", 5), ("1 minute", 60), ("3 minutes", 180), ("5 minutes", 300), ("10 minutes", 600), ("20 minutes", 1200)]
        for (name, val) in intervals {
            let item = makeRadioItem(title: name, checked: state.interval == val) { [weak self] in
                self?.state.interval = val; self?.state.saveConfig(); self?.startShuffleTimer()
                for rv in radioViews { rv.button.state = .off }
                if let v = radioViews.first(where: { $0.button.title == name }) { v.button.state = .on }
            }
            radioViews.append(item.view as! ToggleMenuItemView)
            isub.addItem(item)
        }
        ii.submenu = isub
        menu.addItem(ii)

        if !state.currentName.isEmpty {
            menu.addItem(NSMenuItem.separator())
            let n = NSMenuItem(title: "Now Playing: \(state.currentName)", action: nil, keyEquivalent: "")
            n.isEnabled = false; menu.addItem(n)
        }

        menu.addItem(NSMenuItem.separator())

        menu.addItem(makeCheckboxItem(title: "Start at Login", checked: state.launchAtLogin) { [weak self] in
            guard let s = self?.state else { return }
            s.setLaunchAtLogin(!s.launchAtLogin)
        })

        menu.addItem(NSMenuItem.separator())

        let ui = NSMenuItem(title: "Uninstall", action: #selector(doUninstall), keyEquivalent: "")
        ui.target = self; menu.addItem(ui)

        let qi = NSMenuItem(title: "Quit Aerial Shuffle", action: #selector(doQuit), keyEquivalent: "q")
        qi.target = self; menu.addItem(qi)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc func doUninstall() {
        let alert = NSAlert()
        alert.messageText = "Uninstall AerialShuffle?"
        alert.informativeText = "This will remove the app, config, permissions, and restore default power button behavior."
        alert.addButton(withTitle: "Uninstall"); alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn { state.uninstall() }
    }

    @objc func doQuit() {
        state.disablePowerButtonIntercept()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        state?.disablePowerButtonIntercept()
    }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
