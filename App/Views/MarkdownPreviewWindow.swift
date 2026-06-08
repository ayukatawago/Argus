import AppKit
import UniformTypeIdentifiers
import WebKit

@MainActor
final class MarkdownPreviewWindow: NSObject, NSWindowDelegate, ObservableObject {
    private var window: NSWindow?
    private var currentFilePath: String?

    func open(worktreePath: String) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: worktreePath)
        if let mdType = UTType(filenameExtension: "md") {
            panel.allowedContentTypes = [mdType]
        }
        panel.title = "Choose Markdown File"
        panel.prompt = "Preview"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        show(fileURL: url)
    }

    private func show(fileURL: URL) {
        if let existing = window, currentFilePath == fileURL.path {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        window?.close()

        guard let content = try? String(contentsOf: fileURL, encoding: .utf8),
              let templateURL = Bundle.main.url(forResource: "markdown-preview", withExtension: "html"),
              let template = try? String(contentsOf: templateURL, encoding: .utf8),
              let jsonData = try? JSONEncoder().encode(content),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else { return }

        let html = template.replacingOccurrences(of: "{{MARKDOWN_JSON}}", with: jsonString)
        let baseURL = Bundle.main.resourceURL

        let webView = WKWebView(frame: .zero)
        webView.loadHTMLString(html, baseURL: baseURL)

        let screen = NSApp.keyWindow?.screen ?? NSApp.mainWindow?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let sf = screen.visibleFrame
        let size = CGSize(width: sf.width * 0.85, height: sf.height * 0.85)
        let origin = NSPoint(x: sf.midX - size.width / 2, y: sf.midY - size.height / 2)

        let win = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = fileURL.lastPathComponent
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.contentView = webView
        win.delegate = self
        win.makeKeyAndOrderFront(nil)

        window = win
        currentFilePath = fileURL.path
    }

    func windowWillClose(_: Notification) {
        window = nil
        currentFilePath = nil
    }
}
