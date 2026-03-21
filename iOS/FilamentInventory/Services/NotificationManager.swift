import Foundation
import UserNotifications

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()

    func requestPermission() {
        center.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

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
