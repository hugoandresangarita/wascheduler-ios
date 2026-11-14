import SwiftUI
import WebKit
import UserNotifications

class AppNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AppNotificationDelegate()

    // Mostrar notificaciones incluso con la app abierta en primer plano
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    // Manejar toque en la notificación:
    // - Si actionType == "open_app": abre WaScheduler directamente en Pendientes (para evitar envíos duplicados).
    // - Si actionType == "open_wa": abre WhatsApp Normal / Business (o pregunta si ambos están activos).
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let actionType = (userInfo["actionType"] as? String) ?? "open_wa"

        if actionType == "open_app" {
            // Al abrir la app por defecto en iOS, se muestra la vista Pendientes automáticamente
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
        let waCategory = UNNotificationCategory(
            identifier: "WA_MESSAGE_CATEGORY",
            actions: [openAction],
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
            actions: [reviewAction],
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
        config.allowsInlineMediaPlayback = true
        config.preferences.javaScriptEnabled = true
        
        config.userContentController.add(context.coordinator, name: "openExternal")
        config.userContentController.add(context.coordinator, name: "syncAllNotifications")
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
                let center = UNUserNotificationCenter.current()

                // 1. Notificación inicial en 5s (abre WhatsApp)
                let content1 = UNMutableNotificationContent()
                content1.title = "🔔 Prueba 1: Envío Programado"
                content1.body = "Toca para abrir WhatsApp con el mensaje listo."
                content1.sound = .default
                content1.categoryIdentifier = "WA_MESSAGE_CATEGORY"
                content1.userInfo = [
                    "actionType": "open_wa",
                    "waMode": mode,
                    "waQuery": "text=Hola%2C%20esta%20es%20una%20prueba%20desde%20WaScheduler"
                ]
                let trigger1 = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
                center.add(UNNotificationRequest(identifier: "test_notif_1_\(UUID().uuidString)", content: content1, trigger: trigger1))

                // 2. Recordatorio de seguimiento en 15s (abre WaScheduler para evitar duplicados)
                let content2 = UNMutableNotificationContent()
                content2.title = "⚠️ Prueba 2: Tienes un mensaje sin enviar"
                content2.body = "Toca para abrir WaScheduler y confirmar si ya lo enviaste."
                content2.sound = .default
                content2.categoryIdentifier = "WA_REMINDER_CATEGORY"
                content2.userInfo = [
                    "actionType": "open_app"
                ]
                let trigger2 = UNTimeIntervalNotificationTrigger(timeInterval: 15, repeats: false)
                center.add(UNNotificationRequest(identifier: "test_notif_2_\(UUID().uuidString)", content: content2, trigger: trigger2))
                return
            }

            // Sincronización global inteligente (respeta límite de 64 notificaciones de iOS)
            if message.name == "syncAllNotifications", let payload = message.body as? [String: Any] {
                let center = UNUserNotificationCenter.current()
                let items = (payload["messages"] as? [[String: Any]]) ?? []
                let reminderHours = (payload["reminderHours"] as? Int) ?? 2
                let waMode = (payload["waMode"] as? String) ?? "whatsapp"

                // Limpiar notificaciones anteriores (excepto pruebas activas) para reconstruir la cola exacta
                center.getPendingNotificationRequests { requests in
                    let idsToRemove = requests.map { $0.identifier }.filter { !$0.hasPrefix("test_notif_") }
                    center.removePendingNotificationRequests(withIdentifiers: idsToRemove)

                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd HH:mm"
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    let now = Date()

                    struct ScheduledItem {
                        let id: String
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

                        // 1. Notificación principal (si aún no ha pasado)
                        if baseDate > now {
                            queue.append(ScheduledItem(
                                id: "\(id)_main",
                                date: baseDate,
                                title: "⏰ Envío pendiente: \(name)",
                                body: "Para \(recipient): \(text)",
                                isReminder: false,
                                waQuery: waQuery
                            ))
                        }

                        // 2. Recordatorios de seguimiento cada X horas hasta que se marque como enviado
                        if reminderHours > 0 {
                            let stepSeconds = TimeInterval(reminderHours * 3600)
                            for step in 1...12 {
                                let remDate = baseDate.addingTimeInterval(stepSeconds * Double(step))
                                // Solo programar recordatorios futuros (y dentro de los próximos 7 días)
                                if remDate > now && remDate.timeIntervalSince(now) <= 7 * 86400 {
                                    queue.append(ScheduledItem(
                                        id: "\(id)_rem_\(step)",
                                        date: remDate,
                                        title: "⚠️ Tienes mensajes que no has enviado",
                                        body: "Campaña '\(name)' para \(recipient) sigue pendiente. Toca para revisar en la app.",
                                        isReminder: true,
                                        waQuery: waQuery
                                    ))
                                }
                            }
                        }
                    }

                    // Ordenar cronológicamente y tomar las 60 más próximas (iOS permite máx 64 por app)
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
                                "actionType": "open_app"
                            ]
                        } else {
                            content.categoryIdentifier = "WA_MESSAGE_CATEGORY"
                            content.userInfo = [
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
