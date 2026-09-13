import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var serverManager: ServerManager?

    func applicationWillTerminate(_ notification: Notification) {
        serverManager?.stop()
    }
}

@main
struct KimiDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let serverManager = ServerManager()
    private let usageManager = UsageManager()
    @State private var projectStore = ProjectStore()

    init() {
        appDelegate.serverManager = serverManager
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(serverManager)
                .environment(projectStore)
                .environment(usageManager)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    projectStore.load()
                    serverManager.start()
                    usageManager.start()
                }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(after: .newItem) {
                Button("添加项目…") {
                    projectStore.addViaPanel()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }
    }
}
