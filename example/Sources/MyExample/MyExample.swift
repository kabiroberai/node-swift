import Foundation
import NodeAPI
import UserNotifications

private let notificationDelegate = AmieUserNotificationCenterDelegate()

private var jsQueue: NodeAsyncQueue?

class AmieUserNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {

    var actions: [String: NodeFunction] = [:]

    func saveAction(id: String, action: NodeFunction) {

        actions[id] = action
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {

        let id = response.notification.request.identifier
        guard let action = Action(identifier: response.actionIdentifier) else { return }
        let nodeFunction = actions[id]

        try? jsQueue?.run {
            _ = try? nodeFunction?(id, action.rawValue)
        }
    }
}

enum Action: String {

    case click
    case join

    init?(identifier: String) {
        switch identifier {
        case UNNotificationDefaultActionIdentifier:
            // ⚠️ For the default action, we simply propagate "click" to the JS callback
            self = .click
        case Action.join.rawValue:
            self = .join
        default:
            return nil
        }
    }

    var unNotificationAction: UNNotificationAction? {
        switch self {

        case .click:
            return nil

        case .join:
            return UNNotificationAction(
                identifier: rawValue,
                title: "Join",
                options: []
            )
        }
    }
}

enum Category: String, CaseIterable {

    case call

    var unNotificationCategory: UNNotificationCategory {
        switch self {
        case .call:
            return UNNotificationCategory(
                identifier: rawValue,
                actions: [Action.join.unNotificationAction].compactMap { $0 },
                intentIdentifiers: []
            )
        }
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
                let categories = Category.allCases.map(\.unNotificationCategory)
                notificationCenter.setNotificationCategories(Set(categories))
                return ""
            },
            "showNotification": NodeFunction {
                (id: String, title: String, body: String, containsCall: Bool, action: NodeFunction) in

                let content = UNMutableNotificationContent()
                let notificationCenter = UNUserNotificationCenter.current()

                if containsCall {
                    content.categoryIdentifier = Category.call.rawValue
                }

                content.title = title
                content.body = body
                content.sound = .default
                if #available(macOS 12.0, *) {
                    content.interruptionLevel = .timeSensitive
                }
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                notificationCenter.add(request)

                // Save action to propagate responses back to the JS thread
                notificationDelegate.saveAction(id: id, action: action)

                return id
            },
        ]
    }
}
