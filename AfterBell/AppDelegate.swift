import UIKit
import WebKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = PlannerController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

final class PlannerController: UIViewController, WKNavigationDelegate, WKScriptMessageHandler {
    private var webView: WKWebView!
    private var webRoot: URL!
    private var usesDarkTheme = false
    override var preferredStatusBarStyle: UIStatusBarStyle { usesDarkTheme ? .lightContent : .darkContent }
    private let journalURL: URL = {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AfterBell", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("planner.json")
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.93, green: 0.92, blue: 0.97, alpha: 1)
        overrideUserInterfaceStyle = .unspecified
        let controller = WKUserContentController()
        controller.add(self, name: "persist")
        controller.add(self, name: "exportBackup")
        controller.add(self, name: "appearance")
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.userContentController = controller
        var initial = "null"
        var savedTheme = "system"
        if let data = try? Data(contentsOf: journalURL),
           let object = try? JSONSerialization.jsonObject(with: data),
           let valid = try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed]),
           let json = String(data: valid, encoding: .utf8) {
            initial = json
            savedTheme = (object as? [String: Any])?["theme"] as? String ?? "system"
        }
        applyAppearance(dark: savedTheme == "dark" || (savedTheme != "light" && traitCollection.userInterfaceStyle == .dark), mode: savedTheme)
        controller.addUserScript(WKUserScript(source: "window.__afterBellNative = true; window.__afterBellSaved = \(initial);", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = view.backgroundColor
        webView.scrollView.backgroundColor = view.backgroundColor
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("Web", isDirectory: true) else { return }
        webRoot = root
        webView.loadFileURL(root.appendingPathComponent("index.html"), allowingReadAccessTo: root)
        NotificationCenter.default.addObserver(self, selector: #selector(resumeTimer), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    private func applyAppearance(dark: Bool, mode: String) {
        overrideUserInterfaceStyle = mode == "dark" ? .dark : mode == "light" ? .light : .unspecified
        usesDarkTheme = dark
        let color = dark ? UIColor(red: 23/255.0, green: 24/255.0, blue: 35/255.0, alpha: 1) : UIColor(red: 234/255.0, green: 233/255.0, blue: 247/255.0, alpha: 1)
        view.backgroundColor = color
        webView?.backgroundColor = color
        webView?.scrollView.backgroundColor = color
        setNeedsStatusBarAppearanceUpdate()
    }

    @objc private func resumeTimer() {
        webView?.evaluateJavaScript("if (typeof applyTheme === 'function') applyTheme(); if (typeof tick === 'function') tick();", completionHandler: nil)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              message.frameInfo.request.url?.isFileURL == true,
              JSONSerialization.isValidJSONObject(message.body) else { return }
        if message.name == "appearance", let body = message.body as? [String: Any], let dark = body["dark"] as? Bool {
            applyAppearance(dark: dark, mode: body["mode"] as? String ?? "system")
            return
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: message.body, options: [.prettyPrinted, .sortedKeys])
            guard data.count < 4_000_000 else { return }
            if message.name == "persist" {
                try data.write(to: journalURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } else if message.name == "exportBackup" {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("posle-zvonka-backup.json")
                try data.write(to: url, options: .atomic)
                let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                sheet.overrideUserInterfaceStyle = usesDarkTheme ? .dark : .light
                sheet.popoverPresentationController?.sourceView = view
                sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
                present(sheet, animated: true)
            }
        } catch {
            webView.evaluateJavaScript("toast('Не удалось сохранить файл. Проверь свободное место.');", completionHandler: nil)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.absoluteString == "about:blank" {
            decisionHandler(.allow)
        } else if url.isFileURL, let root = webRoot,
                  url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }
}
