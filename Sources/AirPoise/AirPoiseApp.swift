import SwiftUI
import AppKit
import AirPoiseCore

@main
struct AirPoiseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings {
            SettingsHost()
        }
    }
}

private struct SettingsHost: View {
    @ObservedObject private var model = AppModel.shared
    var body: some View {
        SettingsView().environmentObject(model)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var status: StatusItemController?
    private var onboardWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Comic.registerFonts()
        NSApp.setActivationPolicy(.accessory)
        NSApp.servicesProvider = self

        let model = AppModel.shared
        model.start()
        status = StatusItemController(model: model)

        NotificationCenter.default.addObserver(
            forName: .airPoiseShowOnboarding,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.showOnboarding()
            }
        }

        if model.onboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.showOnboarding()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(wake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppModel.shared.refreshPermissions()
    }

    @objc private func wake() {
        Task { @MainActor in
            AppModel.shared.motion.resubscribe()
        }
    }

    private func showOnboarding() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openOnboardingWindow()
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { note in
            if (note.object as? NSWindow)?.identifier?.rawValue == "onboarding" {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    private func openOnboardingWindow() {
        if let existing = NSApp.windows.first(where: { $0.identifier?.rawValue == "onboarding" }) {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: OnboardingView { [weak self] in
            self?.onboardWindow?.close()
            NSApp.setActivationPolicy(.accessory)
        }.environmentObject(AppModel.shared))
        let win = NSWindow(contentViewController: host)
        win.title = "AirPoise"
        win.identifier = NSUserInterfaceItemIdentifier("onboarding")
        win.styleMask = [.titled, .closable, .fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.backgroundColor = Comic.nsPaper
        win.setContentSize(NSSize(width: 760, height: 600))
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        onboardWindow = win
    }
}
