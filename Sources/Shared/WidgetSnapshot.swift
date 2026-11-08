import Foundation

// MARK: - 小组件快照（App 与 Widget 共享的数据形状）
//
// App 每次变更后把「今天需要的全部数据 + 格子历史」写成 JSON 放进
// App Group 容器；Widget 时间线只读这个文件，不直接开数据库。

/// 一天一格（给 Widget 渲染格子用）
struct GridCellDTO: Codable, Equatable {
    /// yyyy-MM-dd（本地时区）
    var d: String
    /// 0…1
    var r: Double
    /// 应做
    var due: Bool
    /// 未来日
    var f: Bool
}

struct WidgetSnapshot: Codable {
    struct HabitInfo: Codable {
        var id: String
        var name: String
        var symbol: String
        var colorHex: Int
        var isCounter: Bool
        var goal: Int
        var todayCount: Int
        var streak: Int
        var dueToday: Bool
        /// 弹性模式（每周 N 次）
        var flexible: Bool
        var weeklyDone: Int
        var weeklyGoal: Int
    }

    var generatedAt: Date
    var habits: [HabitInfo]
    /// habitID → 最近 26 周格子
    var grids: [String: [GridCellDTO]]

    static let empty = WidgetSnapshot(generatedAt: .distantPast, habits: [], grids: [:])
}

extension WidgetSnapshot {
    /// 渲染期跨天修正：快照是旧的一天写的时候，从 26 周格子重推
    /// 「今天」的次数 / 应做 / 弹性周进度——App 不打开，组件也能正确显示新一天。
    /// 快照本身就是今天写的则原样返回（保留精确计数，如 9/8）。
    func habitsForRender(now: Date = Date()) -> [HabitInfo] {
        let cal = Calendar.current
        guard !cal.isDate(generatedAt, inSameDayAs: now) else { return habits }
        let today = Fmt.dailyFormatter.string(from: now)
        let todayStart = cal.startOfDay(for: now)
        let weekStart = HabitMath.weekStart(for: now)
        return habits.map { h in
            var h = h
            let cells = grids[h.id] ?? []
            let cell = cells.first { $0.d == today }
            // 今天的次数：新一天格子 r=0 → 归零；完成格 r=1 封顶显示 goal（够用）
            h.todayCount = cell.map { min(Int(($0.r * Double(max(h.goal, 1))).rounded()), h.goal) } ?? 0
            if !h.flexible, let cell {
                h.dueToday = cell.due   // 格子的 due 用写快照时的掩码算好，对新一天依然正确
            }
            if h.flexible {
                h.weeklyDone = cells.filter { item in
                    guard let day = Fmt.dailyFormatter.date(from: item.d),
                          day >= weekStart, day <= todayStart else { return false }
                    return item.r >= 1
                }.count
            }
            return h
        }
    }
}

enum SnapshotStore {
    static let appGroupID = "group.com.haozc.quilt"

    /// App Group 容器；取不到（预览/测试）时回落到 Application Support
    static var containerURL: URL {
        if let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID) {
            return group
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
    }

    static var snapshotURL: URL {
        containerURL.appendingPathComponent("widget-snapshot.json")
    }

    static func save(_ snapshot: WidgetSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: snapshotURL, options: .atomic)
        }
    }

    static func load() -> WidgetSnapshot {
        guard let data = try? Data(contentsOf: snapshotURL) else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(WidgetSnapshot.self, from: data)) ?? .empty
    }

    /// App Group 的 UserDefaults（种子标记等跨进程共享的状态）
    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }
}
