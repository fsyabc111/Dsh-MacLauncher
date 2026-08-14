import AppKit
import DshLauncherCore
import SwiftUI

@main
struct DshMacLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: model)
        } label: {
            Image(systemName: statusSymbol)
                .accessibilityLabel("DSH Launcher")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
                .frame(width: 480)
        }
    }

    private var statusSymbol: String {
        switch model.service.state.phase {
        case .running: "bolt.circle.fill"
        case .starting, .stopping, .installing: "arrow.triangle.2.circlepath"
        case .failed: "exclamationmark.triangle.fill"
        case .runtimeMissing: "arrow.down.circle"
        case .stopped: "bolt.circle"
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await AppModel.shared.bootstrap() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let model = AppModel.shared
        guard model.service.state.phase == .running || model.service.state.phase == .starting else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = "退出 DSH Launcher？"
        alert.informativeText = "退出会同时停止正在运行的 DSH 服务。"
        alert.addButton(withTitle: "停止并退出")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }

        Task {
            await model.stopService()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

