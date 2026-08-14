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

            Section("进程环境") {
                TextField("额外的 PATH 目录（冒号分隔）", text: extraPathBinding)
                Text("DSH Web 子进程（pnpm、npm 等）会继承这些目录。例如 ~/.npm-global/bin")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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

    private var extraPathBinding: Binding<String> {
        Binding(
            get: { settings.value.extraPathEntries.joined(separator: ":") },
            set: { newValue in
                let entries = newValue
                    .split(separator: ":", omittingEmptySubsequences: true)
                    .map(String.init)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                settings.update { $0.extraPathEntries = entries }
            }
        )
    }
}

