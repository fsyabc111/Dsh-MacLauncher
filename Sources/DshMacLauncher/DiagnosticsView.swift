import DshLauncherCore
import SwiftUI
import UniformTypeIdentifiers

struct DiagnosticsView: View {
    @ObservedObject var model: AppModel
    @State private var exportMessage: String?

    var body: some View {
        let snapshot = model.diagnosticsSnapshot()
        VStack(alignment: .leading, spacing: 16) {
            Form {
                LabeledContent("应用版本", value: snapshot.applicationVersion)
                LabeledContent("架构", value: snapshot.architecture)
                LabeledContent("Node", value: snapshot.nodeVersion ?? "未安装")
                LabeledContent("DSH", value: snapshot.dshVersion ?? "未安装")
                LabeledContent("服务状态", value: snapshot.servicePhase.rawValue)
                LabeledContent("服务地址", value: snapshot.serviceURL ?? "—")
                LabeledContent("工作区", value: snapshot.workspacePath ?? "未选择")
                LabeledContent("Web profile", value: snapshot.webProfileExists ? "已初始化" : "首次启动时创建")
            }
            .formStyle(.grouped)

            if let exportMessage {
                Text(exportMessage).font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button { export() } label: {
                    Label("导出诊断包", systemImage: "square.and.arrow.up")
                }
            }
        }
        .padding()
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "DSH-Launcher-Diagnostics.zip"
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        Task {
            do {
                try await DiagnosticsService.export(
                    snapshot: model.diagnosticsSnapshot(),
                    logURLs: model.logs.logFileURLs(),
                    destinationURL: destination
                )
                exportMessage = "诊断包已导出"
            } catch {
                exportMessage = error.localizedDescription
            }
        }
    }
}
