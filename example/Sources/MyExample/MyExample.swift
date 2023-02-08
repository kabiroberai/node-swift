import Foundation
import NodeAPI
import UserNotifications

private let notificationDelegate = AmieUserNotificationCenterDelegate()

private var jsQueue: NodeAsyncQueue?

private class AmieUserNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {

    var actions: [String: NodeFunction] = [:]

    func saveAction(id: String, action: NodeFunction) {

        actions[id] = action
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {

        let id = response.notification.request.identifier

        let action = response.actionIdentifier == UNNotificationDefaultActionIdentifier
            ? "click"
            : response.actionIdentifier

        let nodeFunction = actions[id]

        try? jsQueue?.run {
            _ = try? nodeFunction?(id, action)
        }
    }
}

private extension UNNotificationCategory {

    @NodeActor
    static func make(id: String, actions: NodeArray) -> UNNotificationCategory {

        let stringActions: [String]? = try? Array.from(actions).compactMap { try? String.from($0) }
        let notificationActions: [UNNotificationAction] = (stringActions ?? []).compactMap { action in
            UNNotificationAction(
                identifier: action,
                title: action,
                options: []
            )
        }

        return UNNotificationCategory(
            identifier: id,
            actions: notificationActions,
            intentIdentifiers: []
        )
    }
}

@main
struct MyExample: NodeModule {
    let exports: NodeValueConvertible
    init() throws {
        exports = try [
            "setUp": NodeFunction { () in
                jsQueue = try? NodeAsyncQueue(label: "swift-js-queue")
                let notificationCenter = UNUserNotificationCenter.current()
                notificationCenter.delegate = notificationDelegate
                return ""
            },
            "showNotification": NodeFunction {
                (id: String, title: String, body: String, actions: NodeArray, onAction: NodeFunction) in

                let content = UNMutableNotificationContent()
                let notificationCenter = UNUserNotificationCenter.current()
                
                // Assign category for notification's actions
                let category = UNNotificationCategory.make(id: id, actions: actions)
                notificationCenter.setNotificationCategories([category])

                // Create notification
                content.title = title
                content.body = body
                content.sound = .default
                content.categoryIdentifier = category.identifier
                if #available(macOS 12.0, *) {
                    content.interruptionLevel = .timeSensitive
                }
                
                // Schedule notification
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                notificationCenter.add(request)

                // Save action to propagate responses back to the JS thread
                notificationDelegate.saveAction(id: id, action: onAction)

                return id
            },
        ]
    }
}
