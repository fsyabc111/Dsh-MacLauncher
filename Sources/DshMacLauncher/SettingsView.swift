import DshLauncherCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: LauncherSettingsStore

    init(model: AppModel) {
        self.model = model
        settings = model.settings
    }

    var body: some View {
        Form {
            Picker("端口", selection: binding(\.portMode)) {
                ForEach(PortMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            if settings.value.portMode == .fixed {
                TextField("端口号", value: binding(\.preferredPort), format: .number)
            }

            Toggle("启动成功后打开浏览器", isOn: binding(\.openBrowserAfterStart))
            Toggle(
                "登录时启动 DSH Launcher",
                isOn: Binding(
                    get: { settings.value.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                )
            )
            Toggle("登录后自动启动 DSH", isOn: binding(\.startServiceAtLogin))

            LabeledContent("DSH 配置") {
                Text(model.paths.dshHomeURL.path).font(.caption.monospaced())
            }
            LabeledContent("运行时") {
                Text(model.runtime.activeInstallation?.manifest.dshVersion ?? "未安装")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<LauncherSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settings.value[keyPath: keyPath] },
            set: { newValue in settings.update { $0[keyPath: keyPath] = newValue } }
        )
    }
}

