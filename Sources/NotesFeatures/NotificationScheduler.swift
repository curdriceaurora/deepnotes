import NotesDomain

#if os(iOS) || os(macOS)
import UserNotifications

public actor UserNotificationScheduler: NotificationScheduling {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter? = nil) {
        self.center = center ?? UNUserNotificationCenter.current()
    }

    public func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    public func scheduleReminder(for task: Task) async {
        guard let due = task.dueStart, due > Date() else { return }
        let id = notificationID(for: task.id)
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let content = UNMutableNotificationContent()
        content.title = "Task Due"
        content.body = task.title
        content.sound = .default

        var components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: due
        )
        components.nanosecond = nil
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await center.add(request)
    }

    public func cancelReminder(for taskID: UUID) async {
        center.removePendingNotificationRequests(withIdentifiers: [notificationID(for: taskID)])
    }

    public func cancelAllReminders() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.filter { $0.identifier.hasPrefix("task-reminder:") }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private func notificationID(for taskID: UUID) -> String {
        "task-reminder:\(taskID.uuidString)"
    }
}

#else

// No-op implementation for platforms without UserNotifications
public actor UserNotificationScheduler: NotificationScheduling {
    public init() {}
    public func requestAuthorization() async -> Bool { true }
    public func scheduleReminder(for task: Task) async { }
    public func cancelReminder(for taskID: UUID) async { }
    public func cancelAllReminders() async { }
}

#endif

// No-op scheduler for use in tests (where UNUserNotificationCenter may not be available)
public actor NoOpNotificationScheduler: NotificationScheduling {
    public init() {}
    public func requestAuthorization() async -> Bool { true }
    public func scheduleReminder(for task: Task) async { }
    public func cancelReminder(for taskID: UUID) async { }
    public func cancelAllReminders() async { }
}
