import AppKit
import SwiftUI

struct LogView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { copyLogs() } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                Button { model.logs.clear() } label: {
                    Label("清空", systemImage: "trash")
                }
                Button { NSWorkspace.shared.open(model.logs.directoryURL) } label: {
                    Label("打开目录", systemImage: "folder")
                }
                Spacer()
            }
            .padding(10)

            Divider()

            ScrollView {
                Text(model.logs.text.isEmpty ? "暂无日志" : model.logs.text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private func copyLogs() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.logs.text, forType: .string)
    }
}
