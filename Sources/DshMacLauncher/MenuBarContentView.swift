import DshLauncherCore
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var service: ServiceController
    @ObservedObject private var runtime: RuntimeManager
    @ObservedObject private var settings: LauncherSettingsStore

    init(model: AppModel) {
        self.model = model
        service = model.service
        runtime = model.runtime
        settings = model.settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("DSH Launcher")
                        .font(.headline)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isBusy { ProgressView().controlSize(.small) }
            }

            if let url = service.state.url, service.state.phase == .running {
                HStack {
                    Text(url.absoluteString)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                    Spacer()
                    Button { model.copyServiceURL() } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("复制地址")
                }
            }

            Divider()

            HStack {
                Button {
                    Task {
                        if service.state.phase == .running {
                            model.openService()
                        } else {
                            await model.startService()
                        }
                    }
                } label: {
                    Label(
                        service.state.phase == .running ? "打开 DSH" : "启动 DSH",
                        systemImage: service.state.phase == .running ? "safari" : "play.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)

                if service.state.phase == .running || service.state.phase == .starting {
                    Button { Task { await model.stopService() } } label: {
                        Image(systemName: "stop.fill")
                    }
                    .help("停止")
                    .disabled(model.isBusy)

                    Button { Task { await model.restartService() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("重启")
                    .disabled(model.isBusy)
                }
            }

            Menu {
                ForEach(settings.value.recentWorkspaces, id: \.self) { path in
                    Button {
                        model.selectWorkspace(path: path)
                    } label: {
                        if path == settings.value.recentWorkspaces.first {
                            Label(path, systemImage: "checkmark")
                        } else {
                            Text(path)
                        }
                    }
                }
                Divider()
                Button("选择其他目录…") { model.chooseWorkspace() }
            } label: {
                Label(
                    model.selectedWorkspace?.lastPathComponent ?? "主目录（默认）",
                    systemImage: model.selectedWorkspace == nil ? "house" : "folder"
                )
                .lineLimit(1)
            }

            if let updateMessage = model.updateMessage {
                HStack {
                    Text(updateMessage).font(.caption)
                    Spacer()
                    if runtime.availableManifest != nil {
                        Button("安装") { Task { await model.installAvailableUpdate() } }
                            .controlSize(.small)
                    }
                }
            }

            if let error = model.errorMessage ?? service.state.message {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Button { AppWindows.shared.showLogs(model: model) } label: {
                    Label("日志", systemImage: "text.alignleft")
                }
                Button { AppWindows.shared.showDiagnostics(model: model) } label: {
                    Label("诊断", systemImage: "stethoscope")
                }
                Spacer()
                Button { model.showSettings() } label: {
                    Image(systemName: "gearshape")
                }
                .help("设置")
            }
            .buttonStyle(.borderless)

            HStack {
                Button("检查更新") { Task { await model.checkForUpdates() } }
                    .buttonStyle(.plain)
                    .font(.caption)
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.caption)
            }
        }
        .padding(14)
        .frame(width: 340)
        .task { await model.bootstrap() }
    }

    private var statusText: String {
        switch service.state.phase {
        case .runtimeMissing: "需要安装运行时"
        case .installing: "正在安装"
        case .stopped: runtime.activeInstallation == nil ? "需要安装运行时" : "已停止"
        case .starting: "正在启动"
        case .running: "正在运行"
        case .stopping: "正在停止"
        case .failed: "启动失败"
        }
    }

    private var statusIcon: String {
        switch service.state.phase {
        case .running: "checkmark.circle.fill"
        case .starting, .stopping, .installing: "clock.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .runtimeMissing: "arrow.down.circle.fill"
        case .stopped: "circle.fill"
        }
    }

    private var statusColor: Color {
        switch service.state.phase {
        case .running: .green
        case .starting, .stopping, .installing: .orange
        case .failed: .red
        default: .secondary
        }
    }
}
