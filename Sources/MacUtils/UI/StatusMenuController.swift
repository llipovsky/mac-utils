import AppKit
import Combine

/// The menu bar icon and its menu. The menu is rebuilt every time it opens.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private unowned let app: AppDelegate
    private var cancellables = Set<AnyCancellable>()

    private var awake: AwakeController { app.awake }
    private var jiggler: Jiggler { app.jiggler }
    private var prefs: Preferences { app.prefs }

    init(app: AppDelegate) {
        self.app = app
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageLeading

        Publishers.Merge4(
            app.awake.objectWillChange,
            app.jiggler.objectWillChange,
            app.updater.objectWillChange,
            app.prefs.objectWillChange
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in self?.refreshButton() }
        .store(in: &cancellables)

        refreshButton()
    }

    // MARK: Button

    private func refreshButton() {
        guard let button = statusItem.button else { return }
        let symbol: String
        if jiggler.isRunning {
            symbol = "cup.and.heat.waves.fill"
        } else if awake.isActive {
            symbol = "cup.and.saucer.fill"
        } else {
            symbol = "cup.and.saucer"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "MacUtils")
            ?? NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: "MacUtils")
        image?.isTemplate = true
        button.image = image

        var title = ""
        if prefs.showRemainingTime, let remaining = awake.remaining {
            title = " " + Choices.remainingLabel(remaining, compact: true)
        }
        if case .available = app.updater.state {
            title += " •"
        }
        button.title = title
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild()
    }

    private func rebuild() {
        menu.removeAllItems()
        addKeepAwakeSection()
        menu.addItem(.separator())
        addJigglerSection()
        menu.addItem(.separator())
        addAppSection()
    }

    private func addKeepAwakeSection() {
        menu.addItem(header("Keep Awake"))
        menu.addItem(info(awakeStatusText()))

        if awake.isActive {
            menu.addItem(ActionItem("Stop Session", key: "s") { [weak self] in self?.awake.stop() })
            if awake.endDate != nil {
                let extend = NSMenu()
                for minutes in Choices.extensions {
                    extend.addItem(ActionItem("+ " + Choices.durationLabel(minutes)) { [weak self] in self?.awake.extend(minutes: minutes) })
                }
                menu.addItem(submenu("Extend", extend))
            }
        } else {
            let defaultLabel = Choices.durationLabel(prefs.defaultDurationMinutes)
            menu.addItem(ActionItem("Start Session (\(defaultLabel))", key: "s") { [weak self] in
                guard let self else { return }
                self.awake.start(minutes: self.prefs.defaultDurationMinutes)
            })
        }

        let durations = NSMenu()
        for minutes in Choices.durations {
            durations.addItem(ActionItem(Choices.durationLabel(minutes)) { [weak self] in self?.awake.start(minutes: minutes) })
        }
        durations.addItem(.separator())
        durations.addItem(ActionItem("Until a Time…") { [weak self] in self?.promptUntilTime() })
        menu.addItem(submenu(awake.isActive ? "Restart For" : "Start For", durations))

        menu.addItem(ActionItem("Allow Display to Sleep", state: prefs.allowDisplaySleep) { [weak self] in
            self?.prefs.allowDisplaySleep.toggle()
        })
        menu.addItem(ActionItem("Stay Shown as Active", state: prefs.stayActive, enabled: !prefs.allowDisplaySleep) { [weak self] in
            self?.prefs.stayActive.toggle()
        })
    }

    private func addJigglerSection() {
        menu.addItem(header("Mouse Jiggler"))
        menu.addItem(ActionItem("Jiggle Mouse", key: "j", state: jiggler.isRunning) { [weak self] in self?.jiggler.toggle() })

        let patterns = NSMenu()
        let library = ScriptLibrary.shared
        for pattern in ScriptLibrary.builtins {
            patterns.addItem(patternItem(pattern))
        }
        let userPatterns = library.userPatterns()
        if !userPatterns.isEmpty {
            patterns.addItem(.separator())
            patterns.addItem(header("Your Scripts"))
            for pattern in userPatterns {
                patterns.addItem(patternItem(pattern))
            }
        }
        patterns.addItem(.separator())
        patterns.addItem(ActionItem("Open Scripts Folder") { library.revealFolder() })
        let current = library.pattern(id: prefs.jigglePattern)?.name ?? "?"
        menu.addItem(submenu("Pattern: \(current)", patterns))

        let intervals = NSMenu()
        for seconds in Choices.jiggleIntervals {
            intervals.addItem(ActionItem(Choices.intervalLabel(seconds), state: prefs.jiggleInterval == seconds) { [weak self] in
                self?.prefs.jiggleInterval = seconds
            })
        }
        menu.addItem(submenu("Every: \(Choices.intervalLabel(prefs.jiggleInterval))", intervals))

        menu.addItem(ActionItem("Run Pattern Now") { [weak self] in self?.jiggler.runOnce() })

        if !Permissions.accessibilityGranted {
            let item = ActionItem("⚠︎ Grant Accessibility for Real Mouse Events…") { Permissions.openAccessibilitySettings() }
            item.toolTip = "Without Accessibility the cursor still moves and the idle timer is still reset, but no input events are sent."
            menu.addItem(item)
        }
    }

    private func addAppSection() {
        switch app.updater.state {
        case .available(let version):
            menu.addItem(ActionItem("Install Update \(version)…") { [weak self] in
                Task { await self?.app.updater.installLatest() }
            })
        case .downloading:
            menu.addItem(info("Downloading update…"))
        case .installing:
            menu.addItem(info("Installing update…"))
        case .checking:
            menu.addItem(info("Checking for updates…"))
        default:
            menu.addItem(ActionItem("Check for Updates…", enabled: app.updater.isSupported) { [weak self] in
                Task { await self?.app.updater.checkAndOfferInstall() }
            })
        }
        menu.addItem(ActionItem("Settings…", key: ",") { [weak self] in self?.app.showSettings() })
        menu.addItem(.separator())
        menu.addItem(info("MacUtils \(AppInfo.version)"))
        menu.addItem(ActionItem("Quit MacUtils", key: "q") { NSApp.terminate(nil) })
    }

    // MARK: Helpers

    private func awakeStatusText() -> String {
        switch awake.session {
        case .off:
            if let reason = awake.lastStopReason { return "Off — \(reason)" }
            return "Off"
        case .indefinite:
            return "On — indefinitely"
        case .until(let date):
            let left = Choices.remainingLabel(max(0, date.timeIntervalSinceNow), compact: false)
            return "On — \(left) left (until \(date.formatted(date: .omitted, time: .shortened)))"
        }
    }

    private func patternItem(_ pattern: JigglePattern) -> NSMenuItem {
        let item = ActionItem(pattern.name, state: prefs.jigglePattern == pattern.id, enabled: pattern.error == nil) { [weak self] in
            self?.prefs.jigglePattern = pattern.id
        }
        item.toolTip = pattern.error ?? pattern.summary
        return item
    }

    private func promptUntilTime() {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.hourMinute]
        picker.dateValue = Date().addingTimeInterval(3600)
        picker.sizeToFit()

        let alert = NSAlert()
        alert.messageText = "Keep awake until…"
        alert.informativeText = "If the time has already passed today, the session runs until that time tomorrow."
        alert.accessoryView = picker
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: picker.dateValue)
        if let next = calendar.nextDate(after: Date(), matching: parts, matchingPolicy: .nextTime) {
            awake.start(until: next)
        }
    }

    private func header(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) {
            return NSMenuItem.sectionHeader(title: title)
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        item.isEnabled = false
        return item
    }

    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func submenu(_ title: String, _ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        submenu.autoenablesItems = false
        item.submenu = submenu
        return item
    }
}

/// NSMenuItem that runs a closure.
final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", state: Bool = false, enabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
        self.state = state ? .on : .off
        isEnabled = enabled
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func fire() {
        handler()
    }
}
