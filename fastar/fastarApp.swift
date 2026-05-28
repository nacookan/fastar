import AppKit
import SwiftUI

@main
struct FastarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .toolbar) { }
            CommandGroup(replacing: .sidebar) { }
            CommandGroup(replacing: .windowSize) { }
            CommandGroup(replacing: .windowArrangement) { }
            CommandGroup(replacing: .pasteboard) { }

            CommandGroup(replacing: .newItem) {
                Button("menu.openFolder") {
                    NotificationCenter.default.post(name: .fastarOpenFolder, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(replacing: .help) {
                Button("menu.help") {
                    HelpOpener.openHelp()
                }
            }

            CommandMenu("menu.rating") {
                ForEach(0...5, id: \.self) { rating in
                    Button(RatingDisplay.label(for: rating)) {
                        NotificationCenter.default.post(name: .fastarSetRating, object: rating)
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(rating))), modifiers: [])
                }
            }
        }
    }
}

private enum HelpOpener {
    static func openHelp() {
        guard let url = Bundle.main.url(forResource: "index", withExtension: "html")
            ?? Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: nil, localization: "en")
        else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}

extension Notification.Name {
    static let fastarOpenFolder = Notification.Name("fastar.openFolder")
    static let fastarZoomFit = Notification.Name("fastar.zoomFit")
    static let fastarZoom100 = Notification.Name("fastar.zoom100")
    static let fastarZoom400 = Notification.Name("fastar.zoom400")
    static let fastarZoom800 = Notification.Name("fastar.zoom800")
    static let fastarToggleSplit = Notification.Name("fastar.toggleSplit")
    static let fastarToggleLink = Notification.Name("fastar.toggleLink")
    static let fastarSetRating = Notification.Name("fastar.setRating")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let viewMenuIdentifier = NSUserInterfaceItemIdentifier("fastar.viewMenu")
    private var didScheduleViewMenuInstallation = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        scheduleViewMenuInstallation()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        installCustomViewMenu()
    }

    func applicationDidUpdate(_ notification: Notification) {
        installCustomViewMenu()
    }

    private func scheduleViewMenuInstallation() {
        guard !didScheduleViewMenuInstallation else { return }
        didScheduleViewMenuInstallation = true

        for delay in [0.0, 0.05, 0.15, 0.35, 0.75] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.installCustomViewMenu()
            }
        }
    }

    private func installCustomViewMenu() {
        guard let mainMenu = NSApp.mainMenu else { return }
        guard let menuItem = findViewMenuItem(in: mainMenu) else { return }
        guard menuItem.identifier != viewMenuIdentifier ||
              menuItem.submenu?.identifier != viewMenuIdentifier else {
            return
        }

        menuItem.identifier = viewMenuIdentifier
        menuItem.title = String(localized: "menu.view")
        menuItem.submenu = makeCustomViewMenu()
    }

    private func findViewMenuItem(in mainMenu: NSMenu) -> NSMenuItem? {
        mainMenu.items.first { item in
            item.identifier == viewMenuIdentifier ||
            item.title == String(localized: "menu.view") ||
            item.title == "View" ||
            item.title == "表示" ||
            item.submenu.map(containsStandardViewActions) == true
        }
    }

    private func makeCustomViewMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "menu.view"))
        menu.identifier = viewMenuIdentifier

        menu.addItem(makeMenuItem(
            title: String(localized: "menu.zoomFit"),
            action: #selector(performZoomFit(_:)),
            keyEquivalent: "0",
            modifiers: .command
        ))
        menu.addItem(makeMenuItem(
            title: String(localized: "menu.zoom100"),
            action: #selector(performZoom100(_:)),
            keyEquivalent: "1",
            modifiers: .command
        ))
        menu.addItem(makeMenuItem(
            title: String(localized: "menu.zoom400"),
            action: #selector(performZoom400(_:))
        ))
        menu.addItem(makeMenuItem(
            title: String(localized: "menu.zoom800"),
            action: #selector(performZoom800(_:))
        ))

        menu.addItem(.separator())

        menu.addItem(makeMenuItem(
            title: String(localized: "menu.toggleSplit"),
            action: #selector(performToggleSplit(_:)),
            keyEquivalent: "d",
            modifiers: [.command, .shift]
        ))
        menu.addItem(makeMenuItem(
            title: String(localized: "menu.toggleLink"),
            action: #selector(performToggleLink(_:)),
            keyEquivalent: "l",
            modifiers: [.command, .shift]
        ))

        return menu
    }

    private func makeMenuItem(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private func containsStandardViewActions(_ submenu: NSMenu) -> Bool {
        let standardViewActions = [
            "toggleTabBar:",
            "showAllTabs:",
            "toggleFullScreen:"
        ]

        return submenu.items.contains { item in
            guard let action = item.action else { return false }
            return standardViewActions.contains(NSStringFromSelector(action))
        }
    }

    @objc private func performZoomFit(_ sender: Any?) {
        NotificationCenter.default.post(name: .fastarZoomFit, object: nil)
    }

    @objc private func performZoom100(_ sender: Any?) {
        NotificationCenter.default.post(name: .fastarZoom100, object: nil)
    }

    @objc private func performZoom400(_ sender: Any?) {
        NotificationCenter.default.post(name: .fastarZoom400, object: nil)
    }

    @objc private func performZoom800(_ sender: Any?) {
        NotificationCenter.default.post(name: .fastarZoom800, object: nil)
    }

    @objc private func performToggleSplit(_ sender: Any?) {
        NotificationCenter.default.post(name: .fastarToggleSplit, object: nil)
    }

    @objc private func performToggleLink(_ sender: Any?) {
        NotificationCenter.default.post(name: .fastarToggleLink, object: nil)
    }
}
