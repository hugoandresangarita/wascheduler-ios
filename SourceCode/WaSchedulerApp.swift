import SwiftUI
import WebKit
import UserNotifications
import UIKit
import Network

class WebViewBridge {
    static let shared = WebViewBridge()
    weak var webView: WKWebView?
    private var pendingDoneIds: Set<String> = []
    private var pendingPostponeIds: Set<String> = []
    private var pendingSkipIds: Set<String> = []

    func markMessageDone(messageId: String) {
        guard !messageId.isEmpty else { return }
        DispatchQueue.main.async {
            if let wv = self.webView {
                let safeId = messageId.replacingOccurrences(of: "'", with: "\\'")
                wv.evaluateJavaScript("if (window.markAsSentFromNative) { window.markAsSentFromNative('\(safeId)'); }") { _, error in
                    if error != nil { self.pendingDoneIds.insert(messageId) }
                }
            } else {
                self.pendingDoneIds.insert(messageId)
            }
        }
    }

    func postponeMessageOneDay(messageId: String) {
        guard !messageId.isEmpty else { return }
        DispatchQueue.main.async {
            if let wv = self.webView {
                let safeId = messageId.replacingOccurrences(of: "'", with: "\\'")
                wv.evaluateJavaScript("if (window.postponeOneDayFromNative) { window.postponeOneDayFromNative('\(safeId)'); }") { _, error in
                    if error != nil { self.pendingPostponeIds.insert(messageId) }
                }
            } else {
                self.pendingPostponeIds.insert(messageId)
            }
        }
    }

    func skipMessage(messageId: String) {
        guard !messageId.isEmpty else { return }
        DispatchQueue.main.async {
            if let wv = self.webView {
                let safeId = messageId.replacingOccurrences(of: "'", with: "\\'")
                wv.evaluateJavaScript("if (window.skipMessageFromNative) { window.skipMessageFromNative('\(safeId)'); }") { _, error in
                    if error != nil { self.pendingSkipIds.insert(messageId) }
                }
            } else {
                self.pendingSkipIds.insert(messageId)
            }
        }
    }

    func flushPendingActions() {
        guard let wv = self.webView else { return }

        if !pendingDoneIds.isEmpty {
            let ids = Array(pendingDoneIds)
            pendingDoneIds.removeAll()
            for id in ids {
                let safeId = id.replacingOccurrences(of: "'", with: "\\'")
                wv.evaluateJavaScript("if (window.markAsSentFromNative) { window.markAsSentFromNative('\(safeId)'); }", completionHandler: nil)
            }
        }

        if !pendingPostponeIds.isEmpty {
            let ids = Array(pendingPostponeIds)
            pendingPostponeIds.removeAll()
            for id in ids {
                let safeId = id.replacingOccurrences(of: "'", with: "\\'")
                wv.evaluateJavaScript("if (window.postponeOneDayFromNative) { window.postponeOneDayFromNative('\(safeId)'); }", completionHandler: nil)
            }
        }

        if !pendingSkipIds.isEmpty {
            let ids = Array(pendingSkipIds)
            pendingSkipIds.removeAll()
            for id in ids {
                let safeId = id.replacingOccurrences(of: "'", with: "\\'")
                wv.evaluateJavaScript("if (window.skipMessageFromNative) { window.skipMessageFromNative('\(safeId)'); }", completionHandler: nil)
            }
        }
    }
}

class AppNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppNotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let messageId = (userInfo["messageId"] as? String) ?? ""

        func cancelNotificationsForMessage(_ id: String) {
            guard !id.isEmpty else { return }
            center.getPendingNotificationRequests { requests in
                let toCancel = requests.map { $0.identifier }.filter {
                    $0 == "\(id)_main" || $0.hasPrefix("\(id)_rem_")
                }
                center.removePendingNotificationRequests(withIdentifiers: toCancel)
            }
        }

        if response.actionIdentifier == "MARK_DONE_ACTION" {
            cancelNotificationsForMessage(messageId)
            WebViewBridge.shared.markMessageDone(messageId: messageId)
            completionHandler()
            return
        }

        if response.actionIdentifier == "POSTPONE_1D_ACTION" {
            cancelNotificationsForMessage(messageId)
            WebViewBridge.shared.postponeMessageOneDay(messageId: messageId)
            completionHandler()
            return
        }

        if response.actionIdentifier == "SKIP_MSG_ACTION" {
            cancelNotificationsForMessage(messageId)
            WebViewBridge.shared.skipMessage(messageId: messageId)
            completionHandler()
            return
        }

        let actionType = (userInfo["actionType"] as? String) ?? "open_wa"
        if actionType == "open_app" {
            completionHandler()
            return
        }

        let mode = (userInfo["waMode"] as? String) ?? "whatsapp"
        let query = (userInfo["waQuery"] as? String) ?? ""

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if mode == "both" {
                let alert = UIAlertController(title: "Enviar mensaje", message: "¿Con qué aplicación deseas abrir este envío?", preferredStyle: .actionSheet)
                alert.addAction(UIAlertAction(title: "WhatsApp Normal", style: .default) { _ in
                    if let url = URL(string: "https://api.whatsapp.com/send?\(query)") {
                        UIApplication.shared.open(url, options: [:], completionHandler: nil)
                    }
                })
                alert.addAction(UIAlertAction(title: "WhatsApp Business", style: .default) { _ in
                    if let url = URL(string: "whatsapp-smb://send?\(query)") {
                        UIApplication.shared.open(url, options: [:], completionHandler: nil)
                    }
                })
                alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel, handler: nil))

                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootVC = scene.windows.first?.rootViewController {
                    if let popover = alert.popoverPresentationController {
                        popover.sourceView = rootVC.view
                        popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
                        popover.permittedArrowDirections = []
                    }
                    rootVC.present(alert, animated: true)
                }
            } else if mode == "whatsapp-smb" {
                if let url = URL(string: "whatsapp-smb://send?\(query)") {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            } else {
                if let url = URL(string: "https://api.whatsapp.com/send?\(query)") {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            }
        }
        completionHandler()
    }
}

@main
struct WaSchedulerApp: App {
    init() {
        let center = UNUserNotificationCenter.current()
        center.delegate = AppNotificationDelegate.shared
        
        let openAction = UNNotificationAction(
            identifier: "OPEN_WHATSAPP_ACTION",
            title: "Abrir WhatsApp",
            options: [.foreground]
        )
        let markDoneAction = UNNotificationAction(
            identifier: "MARK_DONE_ACTION",
            title: "✓ Marcar como Listo",
            options: []
        )
        let postponeAction = UNNotificationAction(
            identifier: "POSTPONE_1D_ACTION",
            title: "📅 Posponer 1 día",
            options: []
        )
        let skipAction = UNNotificationAction(
            identifier: "SKIP_MSG_ACTION",
            title: "🚫 Omitir mensaje",
            options: [.destructive]
        )
        let waCategory = UNNotificationCategory(
            identifier: "WA_MESSAGE_CATEGORY",
            actions: [openAction, markDoneAction, postponeAction, skipAction],
            intentIdentifiers: [],
            options: []
        )

        let reviewAction = UNNotificationAction(
            identifier: "REVIEW_APP_ACTION",
            title: "Revisar en WaScheduler",
            options: [.foreground]
        )
        let reminderCategory = UNNotificationCategory(
            identifier: "WA_REMINDER_CATEGORY",
            actions: [markDoneAction, postponeAction, skipAction, reviewAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([waCategory, reminderCategory])

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Error solicitando permisos de notificación: \(error.localizedDescription)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .ignoresSafeArea(.container, edges: .bottom)
        }
    }
}

struct ContentView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.preferences.javaScriptEnabled = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        config.userContentController.add(context.coordinator, name: "openExternal")
        config.userContentController.add(context.coordinator, name: "syncAllNotifications")
        config.userContentController.add(context.coordinator, name: "testNotification")
        config.userContentController.add(context.coordinator, name: "webAppReady")
        config.userContentController.add(context.coordinator, name: "updateAppBadge")
        config.userContentController.add(context.coordinator, name: "triggerHaptic")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.953, green: 0.957, blue: 0.965, alpha: 1.0)

        WebViewBridge.shared.webView = webView

        if let htmlURL = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private let pathMonitor = NWPathMonitor()
        private let monitorQueue = DispatchQueue(label: "com.hugoangarita.wascheduler.netmonitor")
        private var lastIsConnected: Bool = true

        override init() {
            super.init()
            pathMonitor.pathUpdateHandler = { [weak self] path in
                let connected = (path.status == .satisfied)
                self?.lastIsConnected = connected
                DispatchQueue.main.async {
                    WebViewBridge.shared.webView?.evaluateJavaScript(
                        "if (window.onNativeNetworkChange) { window.onNativeNetworkChange(\(connected ? "true" : "false")); }",
                        completionHandler: nil
                    )
                }
            }
            pathMonitor.start(queue: monitorQueue)
        }

        deinit {
            pathMonitor.cancel()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let connected = lastIsConnected
            webView.evaluateJavaScript(
                "if (window.onNativeNetworkChange) { window.onNativeNetworkChange(\(connected ? "true" : "false")); }",
                completionHandler: nil
            )
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "webAppReady" {
                WebViewBridge.shared.flushPendingActions()
                return
            }

            if message.name == "updateAppBadge", let count = message.body as? Int {
                DispatchQueue.main.async {
                    if #available(iOS 16.0, *) {
                        UNUserNotificationCenter.current().setBadgeCount(max(0, count), withCompletionHandler: nil)
                    } else {
                        UIApplication.shared.applicationIconBadgeNumber = max(0, count)
                    }
                }
                return
            }

            if message.name == "triggerHaptic" {
                let style = (message.body as? String) ?? "light"
                DispatchQueue.main.async {
                    if style == "success" {
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                    } else {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                    }
                }
                return
            }

            if message.name == "openExternal", let urlString = message.body as? String, let url = URL(string: urlString) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                return
            }

            if message.name == "testNotification" {
                let mode = (message.body as? String) ?? "whatsapp"
                let center = UNUserNotificationCenter.current()

                let content1 = UNMutableNotificationContent()
                content1.title = "🔔 Prueba 1: Envío Programado"
                content1.body = "Mantén presionada esta notificación para ver las 4 acciones: Abrir WhatsApp, ✓ Listo, 📅 Posponer 1 día y 🚫 Omitir."
                content1.sound = .default
                content1.categoryIdentifier = "WA_MESSAGE_CATEGORY"
                content1.userInfo = [
                    "messageId": "test_demo_id",
                    "actionType": "open_wa",
                    "waMode": mode,
                    "waQuery": "text=Hola%2C%20esta%20es%20una%20prueba%20desde%20WaScheduler"
                ]
                let trigger1 = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
                center.add(UNNotificationRequest(identifier: "test_notif_1_\(UUID().uuidString)", content: content1, trigger: trigger1))

                let content2 = UNMutableNotificationContent()
                content2.title = "⚠️ Prueba 2: Tienes un mensaje sin enviar"
                content2.body = "Mantén presionado para Marcar Listo, Posponer 1 día u Omitir."
                content2.sound = .default
                content2.categoryIdentifier = "WA_REMINDER_CATEGORY"
                content2.userInfo = [
                    "messageId": "test_demo_id",
                    "actionType": "open_app"
                ]
                let trigger2 = UNTimeIntervalNotificationTrigger(timeInterval: 15, repeats: false)
                center.add(UNNotificationRequest(identifier: "test_notif_2_\(UUID().uuidString)", content: content2, trigger: trigger2))
                return
            }

            if message.name == "syncAllNotifications", let payload = message.body as? [String: Any] {
                let center = UNUserNotificationCenter.current()
                let items = (payload["messages"] as? [[String: Any]]) ?? []
                let reminderHours = (payload["reminderHours"] as? Int) ?? 2
                let waMode = (payload["waMode"] as? String) ?? "whatsapp"

                center.getPendingNotificationRequests { requests in
                    let idsToRemove = requests.map { $0.identifier }.filter { !$0.hasPrefix("test_notif_") }
                    center.removePendingNotificationRequests(withIdentifiers: idsToRemove)

                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd HH:mm"
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    let now = Date()

                    struct ScheduledItem {
                        let id: String
                        let messageId: String
                        let date: Date
                        let title: String
                        let body: String
                        let isReminder: Bool
                        let waQuery: String
                    }

                    var queue: [ScheduledItem] = []

                    for item in items {
                        guard let id = item["id"] as? String,
                              let name = item["name"] as? String,
                              let recipient = item["recipient"] as? String,
                              let text = item["text"] as? String,
                              let dateStr = item["date"] as? String,
                              let timeStr = item["time"] as? String,
                              let waQuery = item["waQuery"] as? String,
                              let baseDate = formatter.date(from: "\(dateStr) \(timeStr)") else { continue }

                        if baseDate > now {
                            queue.append(ScheduledItem(
                                id: "\(id)_main",
                                messageId: id,
                                date: baseDate,
                                title: "⏰ Envío pendiente: \(name)",
                                body: "Para \(recipient): \(text)",
                                isReminder: false,
                                waQuery: waQuery
                            ))
                        }

                        if reminderHours > 0 {
                            let stepSeconds = TimeInterval(reminderHours * 3600)
                            for step in 1...12 {
                                let remDate = baseDate.addingTimeInterval(stepSeconds * Double(step))
                                if remDate > now && remDate.timeIntervalSince(now) <= 7 * 86400 {
                                    queue.append(ScheduledItem(
                                        id: "\(id)_rem_\(step)",
                                        messageId: id,
                                        date: remDate,
                                        title: "⚠️ Tienes mensajes que no has enviado",
                                        body: "Campaña '\(name)' para \(recipient) sigue pendiente. Mantén presionado para Listo, Posponer u Omitir.",
                                        isReminder: true,
                                        waQuery: waQuery
                                    ))
                                }
                            }
                        }
                    }

                    queue.sort { $0.date < $1.date }
                    let topQueue = queue.prefix(60)

                    for entry in topQueue {
                        let content = UNMutableNotificationContent()
                        content.title = entry.title
                        content.body = entry.body
                        content.sound = .default

                        if entry.isReminder {
                            content.categoryIdentifier = "WA_REMINDER_CATEGORY"
                            content.userInfo = [
                                "messageId": entry.messageId,
                                "actionType": "open_app"
                            ]
                        } else {
                            content.categoryIdentifier = "WA_MESSAGE_CATEGORY"
                            content.userInfo = [
                                "messageId": entry.messageId,
                                "actionType": "open_wa",
                                "waMode": waMode,
                                "waQuery": entry.waQuery
                            ]
                        }

                        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: entry.date)
                        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                        let request = UNNotificationRequest(identifier: entry.id, content: content, trigger: trigger)
                        center.add(request)
                    }
                }
                return
            }
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = UIAlertController(title: "WaScheduler", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            presentAlert(alert)
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = UIAlertController(title: "Confirmar", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancelar", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "Aceptar", style: .default) { _ in completionHandler(true) })
            presentAlert(alert)
        }

        private func presentAlert(_ alert: UIAlertController) {
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = scene.windows.first?.rootViewController {
                rootVC.present(alert, animated: true)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                let scheme = url.scheme?.lowercased() ?? ""
                let host = url.host?.lowercased() ?? ""
                
                if scheme == "whatsapp" || scheme == "whatsapp-smb" || host.contains("wa.me") || host.contains("whatsapp.com") {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }
    }
}
