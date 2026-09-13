import SwiftUI
import AppKit

/// Inspector column: files in the selected project's directory.
/// 单击选中，双击打开，可预览（QuickLook）或在 Finder 中显示。
struct FileListView: View {
    let dirPath: String

    struct FileItem: Identifiable {
        let url: URL
        let isDir: Bool
        let size: Int64
        let mtime: Date?
        var id: String { url.path }
        var name: String { url.lastPathComponent }
    }

    @State private var files: [FileItem] = []
    @State private var selected: String?

    var body: some View {
        VStack(spacing: 0) {
            List(files, selection: $selected) { item in
                HStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                        .resizable()
                        .frame(width: 16, height: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name).lineLimit(1)
                        Text(subtitle(for: item))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(item.url.path)
                .contextMenu {
                    Button("预览") { QuickLookController.shared.preview(item.url) }
                    Button("打开") { NSWorkspace.shared.open(item.url) }
                    Button("在 Finder 中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                    }
                }
            }
            .listStyle(.inset)
            .onTapGesture(count: 2) {
                if let sel = selected, let item = files.first(where: { $0.id == sel }) {
                    NSWorkspace.shared.open(item.url)
                }
            }

            Divider()
            HStack(spacing: 12) {
                Button {
                    previewSelection()
                } label: { Image(systemName: "eye") }
                .help("预览（QuickLook）")
                Button {
                    openSelection()
                } label: { Image(systemName: "arrow.up.forward.app") }
                .help("打开")
                Button {
                    if let sel = selected {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: sel)])
                    }
                } label: { Image(systemName: "folder") }
                .help("在 Finder 中显示")
                Spacer()
                Text("\(files.count) 项")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button {
                    reload()
                } label: { Image(systemName: "arrow.clockwise") }
                .help("刷新")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .onAppear { reload() }
        .onChange(of: dirPath) { _, _ in selected = nil; reload() }
        // 会话进行中 agent 会生成/修改文件：每 5 秒自动刷新
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            reload()
        }
    }

    private func previewSelection() {
        guard let sel = selected, let item = files.first(where: { $0.id == sel }) else { return }
        QuickLookController.shared.preview(item.url)
    }

    private func openSelection() {
        guard let sel = selected, let item = files.first(where: { $0.id == sel }) else { return }
        NSWorkspace.shared.open(item.url)
    }

    private func subtitle(for item: FileItem) -> String {
        var parts: [String] = []
        if item.isDir {
            parts.append("文件夹")
        } else {
            parts.append(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
        }
        if let m = item.mtime {
            parts.append(m.formatted(.relative(presentation: .named)))
        }
        return parts.joined(separator: " · ")
    }

    private func reload() {
        let url = URL(fileURLWithPath: dirPath)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { files = []; return }
        files = contents.map { u in
            let rv = try? u.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            return FileItem(
                url: u,
                isDir: rv?.isDirectory ?? false,
                size: Int64(rv?.fileSize ?? 0),
                mtime: rv?.contentModificationDate
            )
        }.sorted { ($0.mtime ?? .distantPast) > ($1.mtime ?? .distantPast) }
    }
}
