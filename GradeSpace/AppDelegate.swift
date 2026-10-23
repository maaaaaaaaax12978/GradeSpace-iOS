import UIKit
import WebKit
import UniformTypeIdentifiers

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = JournalViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

final class JournalViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, UIDocumentPickerDelegate {
    private var webView: WKWebView!
    private var webRoot: URL!
    private var darkAppearance = false
    private var readError: String?

    private var journalURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GradeSpace", isDirectory: true)
            .appendingPathComponent("journal.json")
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        darkAppearance ? .lightContent : .darkContent
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.95, green: 0.94, blue: 0.98, alpha: 1)
        guard let index = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web") else {
            showLoadError("В сборке отсутствуют файлы интерфейса. Открой журнал сборки GitHub Actions.")
            return
        }
        webRoot = index.deletingLastPathComponent()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let bridge = configuration.userContentController
        for name in ["journal", "exportJournal", "importJournal", "appearance"] {
            bridge.add(self, name: name)
        }

        var saved: Any = NSNull()
        if FileManager.default.fileExists(atPath: journalURL.path) {
            do { saved = try String(contentsOf: journalURL, encoding: .utf8) }
            catch {
                // Invalid seed blocks all writes in the interface until deliberate recovery.
                saved = "{}"
                readError = "Не удалось прочитать журнал. Исходный файл сохранён. " + error.localizedDescription
            }
        }
        let seed: [String: Any] = ["journal": saved, "version": 1]
        if let data = try? JSONSerialization.data(withJSONObject: seed),
           let json = String(data: data, encoding: .utf8) {
            bridge.addUserScript(WKUserScript(source: "window.GradeSpaceNative = \(json);",
                injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.keyboardDismissMode = .interactive
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        webView.loadFileURL(index, allowingReadAccessTo: webRoot)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let error = readError {
            readError = nil
            let alert = UIAlertController(title: "Журнал не прочитан", message: error, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Понятно", style: .default))
            present(alert, animated: true)
        }
    }

    private func showLoadError(_ text: String) {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30)
        ])
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let source = message.frameInfo.request.url,
              source.isFileURL,
              source.standardizedFileURL.path.hasPrefix(webRoot.standardizedFileURL.path + "/") else { return }
        switch message.name {
        case "journal":
            guard let text = message.body as? String else { return }
            saveJournal(text)
        case "exportJournal":
            guard let body = message.body as? [String: Any],
                  let text = body["text"] as? String else { return }
            shareJournal(text, suggestedName: body["name"] as? String)
        case "importJournal":
            guard presentedViewController == nil else { return }
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json, .xml, .plainText, .data], asCopy: true)
            picker.delegate = self
            picker.allowsMultipleSelection = false
            present(picker, animated: true)
        case "appearance":
            darkAppearance = (message.body as? String) == "dark"
            view.backgroundColor = darkAppearance ? UIColor(red: 0.08, green: 0.08, blue: 0.13, alpha: 1) : UIColor(red: 0.95, green: 0.94, blue: 0.98, alpha: 1)
            setNeedsStatusBarAppearanceUpdate()
        default: break
        }
    }

    private func saveJournal(_ text: String) {
        do {
            guard let data = text.data(using: .utf8), data.count <= 10 * 1024 * 1024,
                  let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  root["version"] as? Int == 1, root["subjects"] is [[String: Any]] else {
                throw NSError(domain: "GradeSpace", code: 1, userInfo: [NSLocalizedDescriptionKey: "Неверный формат журнала"])
            }
            let folder = journalURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if let old = try? Data(contentsOf: journalURL) {
                try? old.write(to: folder.appendingPathComponent("journal.previous.json"), options: .atomic)
            }
            try data.write(to: journalURL, options: .atomic)
        } catch {
            sendEvent("gradespace-save-error", detail: ["message": error.localizedDescription])
        }
    }

    private func shareJournal(_ text: String, suggestedName: String?) {
        do {
            // Export names are generated by the app; strip path components regardless.
            let name = suggestedName ?? "GradeSpace.json"
            let safeName = (name as NSString).lastPathComponent
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(safeName.isEmpty ? "GradeSpace.json" : safeName)
            try text.write(to: url, atomically: true, encoding: .utf8)
            let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            share.popoverPresentationController?.sourceView = view
            share.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            share.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: folder) }
            present(share, animated: true)
        } catch {
            sendEvent("gradespace-save-error", detail: ["message": "Не удалось создать копию: " + error.localizedDescription])
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard ((attributes[.size] as? NSNumber)?.intValue ?? 0) <= 10 * 1024 * 1024 else {
                throw NSError(domain: "GradeSpace", code: 2, userInfo: [NSLocalizedDescriptionKey: "Файл больше 10 МБ"])
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            // Deliver after the native picker has dismissed before opening the HTML confirmation sheet.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.sendEvent("gradespace-import", detail: ["text": text])
            }
        } catch {
            sendEvent("gradespace-save-error", detail: ["message": "Не удалось прочитать файл: " + error.localizedDescription])
        }
    }

    private func sendEvent(_ name: String, detail: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: detail),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.dispatchEvent(new CustomEvent('\(name)', {detail: \(json)}));", completionHandler: nil)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // iOS can reclaim a web content process. Reload with the most recent native journal.
        var saved: Any = NSNull()
        if FileManager.default.fileExists(atPath: journalURL.path) {
            saved = (try? String(contentsOf: journalURL, encoding: .utf8)) ?? "{}"
        }
        if let data = try? JSONSerialization.data(withJSONObject: ["journal": saved, "version": 1]),
           let json = String(data: data, encoding: .utf8) {
            webView.configuration.userContentController.removeAllUserScripts()
            webView.configuration.userContentController.addUserScript(WKUserScript(
                source: "window.GradeSpaceNative = \(json);",
                injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        webView.reload()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.isFileURL && url.standardizedFileURL.path.hasPrefix(webRoot.standardizedFileURL.path + "/") {
            decisionHandler(.allow)
        } else if url.absoluteString == "about:blank" {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            if url.scheme == "https" || url.scheme == "http" { UIApplication.shared.open(url) }
        }
    }
}
