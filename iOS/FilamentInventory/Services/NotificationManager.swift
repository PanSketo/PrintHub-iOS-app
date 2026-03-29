import Foundation
import UserNotifications

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()

    func requestPermission() {
        center.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    // MARK: - Print Job Notifications

    func notifyPrintStarted(printName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Print Started"
        content.body = printName.isEmpty ? "A new print job has started." : "\"\(printName)\" has started."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "print_started_\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        center.add(request)
    }

    func notifyPrintCompleted(printName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Print Complete"
        content.body = printName.isEmpty ? "Your print finished successfully!" : "\"\(printName)\" finished successfully!"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "print_completed_\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        center.add(request)
    }

    func notifyPrintFailed(printName: String, reason: String?) {
        let content = UNMutableNotificationContent()
        content.title = "Print Failed"
        var body = printName.isEmpty ? "A print job has failed." : "\"\(printName)\" has failed."
        if let reason { body += " (\(reason))" }
        content.body = body
        content.sound = .defaultCritical
        let request = UNNotificationRequest(
            identifier: "print_failed_\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        center.add(request)
    }

    // MARK: - Low Stock Notifications

    func scheduleAlertIfNeeded(for filament: Filament) {
        guard filament.isLowStock || filament.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.title = filament.isEmpty ? "Filament Empty! 🚫" : "Low Filament Stock ⚠️"
        content.body = filament.isEmpty
            ? "\(filament.brand) \(filament.color.name) \(filament.type.rawValue) is empty. Time to reorder!"
            : "\(filament.brand) \(filament.color.name) \(filament.type.rawValue) has only \(Int(filament.remainingWeightG))g left."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "filament_low_\(filament.id)",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }
}
