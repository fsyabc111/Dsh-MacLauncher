import AppKit
import SwiftUI

@MainActor
final class AppWindows {
    static let shared = AppWindows()
    private var controllers: [String: NSWindowController] = [:]

    func showOnboarding(model: AppModel) {
        show(
            key: "onboarding",
            title: "设置 DSH Launcher",
            size: NSSize(width: 560, height: 520),
            rootView: AnyView(OnboardingView(model: model))
        )
    }

    func showLogs(model: AppModel) {
        show(
            key: "logs",
            title: "DSH 日志",
            size: NSSize(width: 760, height: 520),
            rootView: AnyView(LogView(model: model))
        )
    }

    func showDiagnostics(model: AppModel) {
        show(
            key: "diagnostics",
            title: "DSH 诊断",
            size: NSSize(width: 620, height: 500),
            rootView: AnyView(DiagnosticsView(model: model))
        )
    }

    func close(key: String) {
        controllers[key]?.close()
        controllers[key] = nil
    }

    private func show(key: String, title: String, size: NSSize, rootView: AnyView) {
        if let existing = controllers[key] {
            existing.showWindow(nil)
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = NSWindowController(
            window: NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
        )
        controller.window?.title = title
        controller.window?.contentViewController = NSHostingController(rootView: rootView)
        controller.window?.center()
        controller.window?.isReleasedWhenClosed = false
        controllers[key] = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

