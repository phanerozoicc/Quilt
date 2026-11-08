import Foundation

// MARK: - 小组件打卡队列
//
// 小组件扩展进程无法访问 App 的 Documents 数据库，因此组件上的打卡先写入
// App Group 里的队列文件，App 下次启动/回前台时统一落库（Store.drainPendingCheckIns）。
// 每条是「某习惯某天的绝对次数」——组件按快照算出新值后排队，同习惯同天重复排队
// 只保留最后一条。

struct PendingCheckIn: Codable, Equatable {
    let habitID: String
    /// yyyy-MM-dd（本地时区）
    let day: String
    /// 该天的绝对打卡次数
    let count: Int
}

enum PendingCheckInQueue {
    static var queueURL: URL {
        SnapshotStore.containerURL.appendingPathComponent("pending-checkins.json")
    }

    static func load() -> [PendingCheckIn] {
        guard let data = try? Data(contentsOf: queueURL) else { return [] }
        return (try? JSONDecoder().decode([PendingCheckIn].self, from: data)) ?? []
    }

    static func save(_ items: [PendingCheckIn]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: queueURL, options: .atomic)
    }

    /// 追加/覆盖：同习惯同天只保留最后一条
    static func append(_ item: PendingCheckIn) {
        var items = load()
        items.removeAll { $0.habitID == item.habitID && $0.day == item.day }
        items.append(item)
        save(items)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: queueURL)
    }
}
