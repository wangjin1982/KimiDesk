import AppKit
import Quartz

/// Minimal QuickLook driver: preview file URLs in the system QLPreviewPanel.
@MainActor
final class QuickLookController: NSObject {
    static let shared = QuickLookController()

    private var items: [URL] = []

    func preview(_ url: URL) {
        items = [url]
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }
}

extension QuickLookController: @preconcurrency QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { items.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        items[index] as NSURL
    }
}

extension QuickLookController: @preconcurrency QLPreviewPanelDelegate {
}
