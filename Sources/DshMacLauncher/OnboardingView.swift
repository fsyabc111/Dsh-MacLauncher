import DshLauncherCore
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var runtime: RuntimeManager
    @ObservedObject private var settings: LauncherSettingsStore

    init(model: AppModel) {
        self.model = model
        runtime = model.runtime
        settings = model.settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("DSH Launcher")
                    .font(.largeTitle.bold())
                Text("准备本地 DSH Web 环境")
                    .foregroundStyle(.secondary)
            }

            setupRow(
                icon: model.isRuntimeReady ? "checkmark.circle.fill" : "arrow.down.circle",
                title: "DSH 运行时",
                detail: runtimeDetail
            ) {
                if !model.isRuntimeReady {
                    Button("下载并安装") { Task { await model.installRuntime() } }
                        .disabled(model.isBusy)
                }
            }

            setupRow(
                icon: model.selectedWorkspace == nil ? "house.fill" : "checkmark.circle.fill",
                title: "工作区（可选）",
                detail: model.selectedWorkspace?.path ?? "默认使用主目录：\(model.workspace.path)"
            ) {
                Button("选择…") { model.chooseWorkspace() }
            }

            setupRow(
                icon: dshHomeExists ? "checkmark.circle.fill" : "folder.badge.plus",
                title: "DSH 配置",
                detail: model.paths.dshHomeURL.path
            ) { EmptyView() }

            if model.isBusy { ProgressView().controlSize(.small) }
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Spacer()

            HStack {
                Spacer()
                Button("完成并启动") {
                    Task { await model.completeOnboardingAndStart() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.isRuntimeReady || model.isBusy)
            }
        }
        .padding(28)
        .frame(minWidth: 520, minHeight: 460)
    }

    @ViewBuilder
    private func setupRow<Action: View>(
        icon: String,
        title: String,
        detail: String,
        @ViewBuilder action: () -> Action
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(icon.contains("checkmark") ? .green : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            action()
        }
    }

    private var runtimeDetail: String {
        switch runtime.phase {
        case let .ready(installation):
            "DSH \(installation.manifest.dshVersion) · Node \(installation.manifest.nodeVersion)"
        case .downloading: "正在下载…"
        case .verifying: "正在校验…"
        case .installing: "正在安装…"
        case .checking: "正在检查…"
        case let .failed(message): message
        case .missing: "需要下载约 300 MB 的运行时"
        }
    }

    private var dshHomeExists: Bool {
        FileManager.default.fileExists(atPath: model.paths.dshHomeURL.path)
    }
}
