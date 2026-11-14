import SwiftUI
import WebKit
import UserNotifications

class AppNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppNotificationDelegate()

    // Mostrar notificaciones incluso con la app abierta en primer plano
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    // Abrir WhatsApp / WhatsApp Business o preguntar si ambos están activos (incluso si la app estaba cerrada)
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let mode = (userInfo["waMode"] as? String) ?? "whatsapp"
        let query = (userInfo["waQuery"] as? String) ?? ""

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if mode == "both" {
                let alert = UIAlertController(title: "Enviar mensaje", message: "¿Con qué aplicación deseas abrir este envío?", preferredStyle: .actionSheet)
                alert.addAction(UIAlertAction(title: "WhatsApp Normal", style: .default) { _ in
                    if let url = URL(string: "whatsapp://send?\(query)") {
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
            } else {
                let scheme = (mode == "whatsapp-smb") ? "whatsapp-smb" : "whatsapp"
                if let url = URL(string: "\(scheme)://send?\(query)") {
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
        let category = UNNotificationCategory(
            identifier: "WA_MESSAGE_CATEGORY",
            actions: [openAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])

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
        config.allowsInlineMediaPlayback = true
        config.preferences.javaScriptEnabled = true
        
        config.userContentController.add(context.coordinator, name: "openExternal")
        config.userContentController.add(context.coordinator, name: "scheduleNotification")
        config.userContentController.add(context.coordinator, name: "cancelNotification")
        config.userContentController.add(context.coordinator, name: "testNotification")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.953, green: 0.957, blue: 0.965, alpha: 1.0)

        if let htmlURL = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "openExternal", let urlString = message.body as? String, let url = URL(string: urlString) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                return
            }

            if message.name == "testNotification" {
                let mode = (message.body as? String) ?? "whatsapp"
                let content = UNMutableNotificationContent()
                content.title = "🔔 Prueba WaScheduler"
                content.body = "Toca esta notificación para abrir WhatsApp según tu configuración."
                content.sound = .default
                content.categoryIdentifier = "WA_MESSAGE_CATEGORY"
                content.userInfo = [
                    "waMode": mode,
                    "waQuery": "text=Hola%2C%20esta%20es%20una%20prueba%20desde%20WaScheduler"
                ]

                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
                let request = UNNotificationRequest(identifier: "test_notif_\(UUID().uuidString)", content: content, trigger: trigger)
                UNUserNotificationCenter.current().add(request)
                return
            }

            if message.name == "scheduleNotification", let data = message.body as? [String: Any] {
                guard let id = data["id"] as? String,
                      let title = data["title"] as? String,
                      let body = data["body"] as? String,
                      let dateStr = data["date"] as? String,
                      let timeStr = data["time"] as? String else { return }

                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm"
                formatter.locale = Locale(identifier: "en_US_POSIX")

                if let targetDate = formatter.date(from: "\(dateStr) \(timeStr)"), targetDate > Date() {
                    let content = UNMutableNotificationContent()
                    content.title = title
                    content.body = body
                    content.sound = .default
                    content.categoryIdentifier = "WA_MESSAGE_CATEGORY"
                    
                    let mode = (data["waMode"] as? String) ?? "whatsapp"
                    let query = (data["waQuery"] as? String) ?? ""
                    content.userInfo = [
                        "waMode": mode,
                        "waQuery": query
                    ]

                    let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: targetDate)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                    let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

                    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
                    UNUserNotificationCenter.current().add(request)
                }
                return
            }

            if message.name == "cancelNotification", let id = message.body as? String {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
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
