import AppKit
import ArgusSupport
import UniformTypeIdentifiers
import WebKit

@MainActor
final class MarkdownPreviewWindow: NSObject, NSWindowDelegate, WKScriptMessageHandler, ObservableObject {
    private var window: NSWindow?
    private var currentFilePath: String?
    private var currentWorktreePath: String?
    private var previewHTMLURL: URL?

    func open(worktreePath: String) {
        currentWorktreePath = worktreePath
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
        if currentFilePath == fileURL.path, let existing = window {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        // The tree walk touches the whole worktree, so it runs off the main actor; the window is
        // presented once it's ready.
        let rootPath = currentWorktreePath ?? fileURL.deletingLastPathComponent().path
        Task { [weak self] in
            let tree = await Task.detached(priority: .userInitiated) { MarkdownFileTree.build(at: rootPath) }.value
            self?.present(fileURL: fileURL, tree: tree)
        }
    }

    private func present(fileURL: URL, tree: [MarkdownTreeNode]) {
        if currentFilePath == fileURL.path, let existing = window {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        guard let html = buildHTML(for: fileURL, tree: tree), let htmlURL = writePreviewHTML(html, next: fileURL)
        else { return }
        let directoryURL = fileURL.deletingLastPathComponent()

        if let win = window, let webView = win.contentView as? WKWebView {
            win.title = fileURL.lastPathComponent
            webView.loadFileURL(htmlURL, allowingReadAccessTo: directoryURL)
            win.makeKeyAndOrderFront(nil)
        } else {
            let controller = WKUserContentController()
            controller.add(self, name: "linkClicked")
            let config = WKWebViewConfiguration()
            config.userContentController = controller

            let webView = WKWebView(frame: .zero, configuration: config)
            webView.loadFileURL(htmlURL, allowingReadAccessTo: directoryURL)

            let screenFrame = NSScreen.popupVisibleFrame
            let size = CGSize(width: screenFrame.width * 0.85, height: screenFrame.height * 0.85)
            let origin = NSPoint(x: screenFrame.midX - size.width / 2, y: screenFrame.midY - size.height / 2)

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
        }

        currentFilePath = fileURL.path
    }

    // Inline marked.js so the base URL is the file's own directory,
    // enabling relative links (e.g. CONVENTIONS.md) to resolve correctly.
    private func buildHTML(for fileURL: URL, tree: [MarkdownTreeNode]) -> String? {
        let encoder = JSONEncoder()
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8),
            let templateURL = Bundle.main.url(forResource: "markdown-preview", withExtension: "html"),
            let template = try? String(contentsOf: templateURL, encoding: .utf8),
            let markedURL = Bundle.main.url(forResource: "marked.min", withExtension: "js"),
            let markedJS = try? String(contentsOf: markedURL, encoding: .utf8),
            let mdJSON = String(data: (try? encoder.encode(content)) ?? Data(), encoding: .utf8),
            let pathJSON = String(data: (try? encoder.encode(fileURL.path)) ?? Data(), encoding: .utf8)
        else { return nil }

        let treeJSON = String(data: (try? encoder.encode(tree)) ?? Data(), encoding: .utf8) ?? "[]"

        // One pass over the template: chained replacements re-scanned inserted text, so markdown that
        // quotes a literal `{{FILE_TREE_JSON}}` had it replaced by the file tree.
        let html = TemplateFill.fill(
            template,
            with: ["MARKDOWN_JSON": mdJSON, "FILE_TREE_JSON": treeJSON, "CURRENT_FILE_JSON": pathJSON])
        return html.replacingOccurrences(
            of: #"<script src="marked.min.js"></script>"#,
            with: "<script>\(markedJS)</script>")
    }

    // WKWebView only allows loading local subresources (e.g. relative image paths) when the
    // page itself was loaded via loadFileURL(_:allowingReadAccessTo:) — loadHTMLString(_:baseURL:)
    // cannot read files from disk even with a file:// base URL. So the composed HTML is written
    // next to the source markdown file and loaded from there.
    private func writePreviewHTML(_ html: String, next fileURL: URL) -> URL? {
        let htmlURL = fileURL.deletingLastPathComponent().appendingPathComponent(".argus-markdown-preview.html")
        guard (try? html.write(to: htmlURL, atomically: true, encoding: .utf8)) != nil else { return nil }
        if let previous = previewHTMLURL, previous != htmlURL {
            try? FileManager.default.removeItem(at: previous)
        }
        previewHTMLURL = htmlURL
        return htmlURL
    }

    func windowWillClose(_: Notification) {
        if let webView = window?.contentView as? WKWebView {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "linkClicked")
        }
        if let previewHTMLURL {
            try? FileManager.default.removeItem(at: previewHTMLURL)
        }
        previewHTMLURL = nil
        window = nil
        currentFilePath = nil
    }

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        MainActor.assumeIsolated {
            guard message.name == "linkClicked",
                let urlString = message.body as? String,
                let url = URL(string: urlString)
            else { return }
            if url.isFileURL && url.pathExtension.lowercased() == "md" {
                show(fileURL: url)
            } else {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
