import AppKit
import UniformTypeIdentifiers
import WebKit

@MainActor
final class MarkdownPreviewWindow: NSObject, NSWindowDelegate, WKScriptMessageHandler, ObservableObject {
    private var window: NSWindow?
    private var currentFilePath: String?
    private var currentWorktreePath: String?

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

        let encoder = JSONEncoder()
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8),
              let templateURL = Bundle.main.url(forResource: "markdown-preview", withExtension: "html"),
              let template = try? String(contentsOf: templateURL, encoding: .utf8),
              let markedURL = Bundle.main.url(forResource: "marked.min", withExtension: "js"),
              let markedJS = try? String(contentsOf: markedURL, encoding: .utf8),
              let mdJSON = String(data: (try? encoder.encode(content)) ?? Data(), encoding: .utf8),
              let pathJSON = String(data: (try? encoder.encode(fileURL.path)) ?? Data(), encoding: .utf8)
        else { return }

        let rootPath = currentWorktreePath ?? fileURL.deletingLastPathComponent().path
        let tree = buildFileTree(at: rootPath)
        let treeJSON = String(data: (try? encoder.encode(tree)) ?? Data(), encoding: .utf8) ?? "[]"

        // Inline marked.js so the base URL is the file's own directory,
        // enabling relative links (e.g. CONVENTIONS.md) to resolve correctly.
        var html = template
            .replacingOccurrences(of: "{{MARKDOWN_JSON}}", with: mdJSON)
            .replacingOccurrences(of: "{{FILE_TREE_JSON}}", with: treeJSON)
            .replacingOccurrences(of: "{{CURRENT_FILE_JSON}}", with: pathJSON)
        html = html.replacingOccurrences(of: #"<script src="marked.min.js"></script>"#,
                                         with: "<script>\(markedJS)</script>")

        if let win = window, let webView = win.contentView as? WKWebView {
            win.title = fileURL.lastPathComponent
            webView.loadHTMLString(html, baseURL: fileURL.deletingLastPathComponent())
            win.makeKeyAndOrderFront(nil)
        } else {
            let controller = WKUserContentController()
            controller.add(self, name: "linkClicked")
            let config = WKWebViewConfiguration()
            config.userContentController = controller

            let webView = WKWebView(frame: .zero, configuration: config)
            webView.loadHTMLString(html, baseURL: fileURL.deletingLastPathComponent())

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
        }

        currentFilePath = fileURL.path
    }

    private struct TreeNode: Encodable {
        let type: String
        let name: String
        let path: String?
        let children: [TreeNode]?
    }

    private func buildFileTree(at dirPath: String) -> [TreeNode] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dirPath) else { return [] }
        var dirs: [TreeNode] = []
        var files: [TreeNode] = []
        for name in entries.sorted() {
            guard !name.hasPrefix(".") else { continue }
            let fullPath = (dirPath as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: fullPath, isDirectory: &isDir)
            if isDir.boolValue {
                let children = buildFileTree(at: fullPath)
                if !children.isEmpty {
                    dirs.append(TreeNode(type: "dir", name: name, path: nil, children: children))
                }
            } else if name.hasSuffix(".md") {
                files.append(TreeNode(type: "file", name: name, path: fullPath, children: nil))
            }
        }
        return dirs + files
    }

    func windowWillClose(_: Notification) {
        if let webView = window?.contentView as? WKWebView {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "linkClicked")
        }
        window = nil
        currentFilePath = nil
    }

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "linkClicked",
              let urlString = message.body as? String,
              let url = URL(string: urlString)
        else { return }
        MainActor.assumeIsolated {
            if url.isFileURL && url.pathExtension.lowercased() == "md" {
                show(fileURL: url)
            } else {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
