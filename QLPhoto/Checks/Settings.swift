import Cocoa

// Compile alongside a temporary copy of App.swift with its @main annotation removed.
@main struct SettingsCheck {
    @MainActor static func main() {
        _ = NSApplication.shared
        let suite = "QLPhoto.SettingsCheck." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let delegate = AppDelegate(preferences: defaults)
        precondition(delegate.showDockIcon && delegate.showMenuBarIcon)
        for menu in [true, false] {
            for dock in [true, false] {
                delegate.showMenuBarIcon = menu
                delegate.showDockIcon = dock
                precondition((delegate.statusItem != nil) == menu)
                precondition(NSApp.activationPolicy() == (dock ? .regular : .accessory))
                let restored = AppDelegate(preferences: defaults)
                precondition(restored.showMenuBarIcon == menu && restored.showDockIcon == dock)
            }
        }
        print("PASS all four icon combinations and preference restoration")
        precondition(!delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp))
        delegate.showSettings()
        let original = delegate.settingsWindow
        original?.close()
        _ = delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
        precondition(delegate.settingsWindow === original && original?.isVisible == true)
        precondition(NSApp.activationPolicy() == .accessory && delegate.statusItem == nil)
        original?.close()
        print("PASS hidden icons preserve background lifetime and reopen settings")
    }
}
