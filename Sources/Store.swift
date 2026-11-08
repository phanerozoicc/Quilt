import Foundation
import SwiftData
import WidgetKit

// MARK: - 存储（App 与 Widget 共用）
//
// 单一 SwiftData 库放在 App Group 容器里；Widget 的打卡 Intent 直接写它，
// 界面用 Store 做唯一数据入口。所有变更后都会刷新快照 + 小组件时间线。

@MainActor
final class Store: ObservableObject {

    let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    @Published private(set) var habits: [Habit] = []
    @Published private(set) var archivedHabits: [Habit] = []
    /// 习惯 id → 今天的 count
    @Published private(set) var todayCounts: [UUID: Int] = [:]
    @Published private(set) var lastImportError: String?

    static let seededKey = "seeded.v1"
    private static let gridWeeks = 26

    // MARK: 数据位置（用户可见）
    //
    // 真实数据库放在 App 的 Documents/Quilt/ 下——「文件 App → 我的 iPhone → Quilt」
    // 里能看到的普通文件，可浏览、可拷贝、可备份。小组件共享的快照/队列仍留在
    // App Group 容器（扩展沙箱只能访问那里，见 SnapshotStore）。

    static func documentsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return docs.appendingPathComponent("Quilt", isDirectory: true)
    }

    static func libraryURL() -> URL {
        documentsDirectory().appendingPathComponent("Quilt.store")
    }

    /// 一次性迁移：旧版把库存在 App Group 容器，升级后搬到 Documents/Quilt/
    static func migrateStoreIfNeeded(oldContainerURL: URL, newDirectory: URL? = nil) {
        let fm = FileManager.default
        let newDir = newDirectory ?? documentsDirectory()
        let newURL = newDir.appendingPathComponent("Quilt.store")
        guard !fm.fileExists(atPath: newURL.path) else { return }
        let oldURL = oldContainerURL.appendingPathComponent("Quilt.store")
        guard fm.fileExists(atPath: oldURL.path) else { return }
        try? fm.createDirectory(at: newDir, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            let src = URL(fileURLWithPath: oldURL.path + suffix)
            let dst = URL(fileURLWithPath: newURL.path + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            if (try? fm.moveItem(at: src, to: dst)) == nil {
                try? fm.copyItem(at: src, to: dst)
            }
        }
    }

    // MARK: 初始化

    init(inMemory: Bool = false, seed: Bool = true, forceSeed: Bool = false, url: URL? = nil) {
        let schema = Schema([Habit.self, CheckIn.self])
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            config = ModelConfiguration(schema: schema, url: url ?? Self.libraryURL())
        }
        if !inMemory {
            Self.migrateStoreIfNeeded(oldContainerURL: SnapshotStore.containerURL)
            try? FileManager.default.createDirectory(at: Self.documentsDirectory(),
                                                     withIntermediateDirectories: true)
        }
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // 本地库损坏时退到内存库，绝不让应用起不来
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            container = (try? ModelContainer(for: schema, configurations: [fallback]))
                ?? { fatalError("SwiftData 初始化失败：\(error)") }()
        }
        reload()
        drainPendingCheckIns()
        if seed || forceSeed { seedDemo(force: forceSeed) }
        writeSnapshot()
    }

    /// 把小组件排队的打卡落到数据库（App 启动/回前台时调用）
    func drainPendingCheckIns() {
        let items = PendingCheckInQueue.load()
        guard !items.isEmpty else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        for item in items {
            guard let id = UUID(uuidString: item.habitID),
                  let habit = habit(id: id),
                  let day = formatter.date(from: item.day) else { continue }
            setCount(habit, day: day, count: item.count)
        }
        PendingCheckInQueue.save([])
    }

    // MARK: 查询

    func reload() {
        let descriptor = FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.sortOrder)])
        let all = (try? context.fetch(descriptor)) ?? []
        habits = all.filter { !$0.isArchived }
        archivedHabits = all.filter { $0.isArchived }
        refreshTodayCounts()
    }

    func refreshTodayCounts() {
        let today = HabitMath.startOfDay(Date())
        var dict: [UUID: Int] = [:]
        for habit in habits {
            dict[habit.id] = count(of: habit, on: today)
        }
        todayCounts = dict
    }

    func habit(id: UUID) -> Habit? {
        (habits + archivedHabits).first { $0.id == id }
    }

    func count(of habit: Habit, on day: Date) -> Int {
        let start = HabitMath.startOfDay(day)
        return habit.checkIns.first { HabitMath.startOfDay($0.day) == start }?.count ?? 0
    }

    /// 近 `daysBack` 天（含今天）的打卡字典，key 为 startOfDay
    func counts(habit: Habit, daysBack: Int) -> [Date: Int] {
        let today = HabitMath.startOfDay(Date())
        guard let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: today) else {
            return [:]
        }
        var dict: [Date: Int] = [:]
        for ci in habit.checkIns {
            let day = HabitMath.startOfDay(ci.day)
            if day >= start { dict[day] = ci.count }
        }
        return dict
    }

    func streak(of habit: Habit) -> Int {
        let counts = counts(habit: habit, daysBack: 800)
        if habit.isFlexible {
            return HabitMath.weeklyStreak(counts: counts, timesPerWeek: habit.timesPerWeek,
                                          goal: habit.goal, created: habit.createdAt,
                                          today: HabitMath.startOfDay(Date()))
        }
        return HabitMath.currentStreak(counts: counts, mask: habit.weekdayMask,
                                       goal: habit.goal, created: habit.createdAt,
                                       today: HabitMath.startOfDay(Date()))
    }

    /// 弹性习惯本周已完成天数
    func weeklyDone(of habit: Habit) -> Int {
        let counts = counts(habit: habit, daysBack: 14)
        return HabitMath.weeklyDoneCount(counts: counts,
                                         weekStart: HabitMath.weekStart(for: Date()),
                                         goal: habit.goal,
                                         today: HabitMath.startOfDay(Date()))
    }

    // MARK: 写操作

    @discardableResult
    func addHabit(_ habit: Habit) -> Habit {
        habit.sortOrder = nextSortOrder()
        context.insert(habit)
        save()
        return habit
    }

    func updateHabit(_ habit: Habit) {
        habit.dailyGoal = habit.isCounter ? max(habit.dailyGoal, 1) : 1
        save()
    }

    func delete(_ habit: Habit) {
        context.delete(habit)
        save()
    }

    func archive(_ habit: Habit, _ flag: Bool) {
        habit.isArchived = flag
        save()
    }

    func moveHabit(fromOffsets: IndexSet, toOffset: Int) {
        var reordered = habits
        reordered.move(fromOffsets: fromOffsets, toOffset: toOffset)
        for (idx, habit) in reordered.enumerated() {
            habit.sortOrder = idx
        }
        save()
    }

    private func nextSortOrder() -> Int {
        (habits.map { $0.sortOrder }.max() ?? -1) + 1
    }

    /// 设置某天打卡数（0 = 删除当天记录）
    func setCount(_ habit: Habit, day: Date, count: Int) {
        let start = HabitMath.startOfDay(day)
        let clamped = max(count, 0)
        if let existing = habit.checkIns.first(where: { HabitMath.startOfDay($0.day) == start }) {
            if clamped == 0 {
                context.delete(existing)
            } else {
                existing.count = clamped
            }
        } else if clamped > 0 {
            let ci = CheckIn(day: start, count: clamped)
            context.insert(ci)
            habit.checkIns.append(ci)
        }
        save()
    }

    /// 勾选型：切今天；计数型：+1
    func checkInToday(_ habit: Habit) {
        let today = HabitMath.startOfDay(Date())
        let current = count(of: habit, on: today)
        if habit.isCounter {
            setCount(habit, day: today, count: current + 1)
        } else {
            setCount(habit, day: today, count: current > 0 ? 0 : 1)
        }
    }

    func decrementToday(_ habit: Habit) {
        let today = HabitMath.startOfDay(Date())
        let current = count(of: habit, on: today)
        guard current > 0 else { return }
        setCount(habit, day: today, count: current - 1)
    }

    /// 每次落盘后回调（App 侧用来重排提醒；Widget 进程不设置）
    var onSave: (() -> Void)?

    func save() {
        try? context.save()
        reload()
        writeSnapshot()
        onSave?()
    }

    // MARK: 小组件快照

    func writeSnapshot() {
        let today = HabitMath.startOfDay(Date())
        var infos: [WidgetSnapshot.HabitInfo] = []
        var grids: [String: [GridCellDTO]] = [:]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        for habit in habits {
            let counts = counts(habit: habit, daysBack: Self.gridWeeks * 7 + 7)
            let streak = streak(of: habit)
            let weeklyDone = habit.isFlexible ? weeklyDone(of: habit) : 0
            infos.append(.init(id: habit.id.uuidString,
                               name: habit.name,
                               symbol: habit.symbol,
                               colorHex: habit.colorHex,
                               isCounter: habit.isCounter,
                               goal: habit.goal,
                               todayCount: counts[today] ?? 0,
                               streak: streak,
                               dueToday: habit.isHardDue(on: today),
                               flexible: habit.isFlexible,
                               weeklyDone: weeklyDone,
                               weeklyGoal: habit.isFlexible ? habit.timesPerWeek : 0))
            // 弹性模式天天可打：格子用全周掩码铺底
            let gridMask = habit.isFlexible ? HabitMath.allWeekdayMask : habit.weekdayMask
            let cells = HabitMath.gridCells(counts: counts, mask: gridMask, goal: habit.goal,
                                            created: habit.createdAt, today: today, weeks: Self.gridWeeks)
            grids[habit.id.uuidString] = cells.map {
                GridCellDTO(d: formatter.string(from: $0.day), r: $0.ratio, due: $0.due, f: $0.isFuture)
            }
        }
        SnapshotStore.save(WidgetSnapshot(generatedAt: Date(), habits: infos, grids: grids))
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: 首启动示例数据
    //
    // 三条示例习惯 + 近 6 周确定性历史（方便上手与截图），可在设置里清空。

    /// 示例数据：三条习惯 + 近 6 周确定性历史；force=true 时无视「种过」标记重种
    func seedDemo(force: Bool = false) {
        let defaults = SnapshotStore.sharedDefaults
        if force {
            defaults.set(true, forKey: Self.seededKey)
        } else {
            guard !defaults.bool(forKey: Self.seededKey) else { return }
            defaults.set(true, forKey: Self.seededKey)
        }
        guard habits.isEmpty else { return }

        let cal = Calendar.current
        let today = HabitMath.startOfDay(Date())

        let workout = addHabit(Habit(name: "锻炼", symbol: "figure.run", colorHex: 0x3E9B6C,
                                     weekdayMask: weekdayMask([2, 4, 6]),   // 一三五
                                     sortOrder: 0, createdAt: cal.date(byAdding: .day, value: -42, to: today)!))
        let reading = addHabit(Habit(name: "阅读", symbol: "book.closed", colorHex: 0x5B8DEF,
                                     sortOrder: 1, createdAt: cal.date(byAdding: .day, value: -42, to: today)!))
        let water = addHabit(Habit(name: "喝水", symbol: "drop", colorHex: 0x3FA8B5,
                                   isCounter: true, dailyGoal: 8,
                                   sortOrder: 2, createdAt: cal.date(byAdding: .day, value: -42, to: today)!))

        // 确定性伪历史：锻炼约七成、阅读约八成、喝水 4…8 杯
        for offset in stride(from: -42, through: -1, by: 1) {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            let seed = abs((day.timeIntervalSince1970 / 86_400).hashValue) % 10
            if workout.isDue(on: day), seed < 7 {
                insertCheckIn(workout, day: day, count: 1)
            }
            if reading.isDue(on: day), seed < 8 {
                insertCheckIn(reading, day: day, count: 1)
            }
            if seed < 6 {
                insertCheckIn(water, day: day, count: 4 + seed % 5)
            }
        }
        save()
    }

    private func weekdayMask(_ weekdays: [Int]) -> Int {
        weekdays.reduce(0) { $0 | (1 << ($1 - 1)) }
    }

    private func insertCheckIn(_ habit: Habit, day: Date, count: Int) {
        habit.checkIns.append(CheckIn(day: HabitMath.startOfDay(day), count: count))
    }

    // MARK: 导入 / 导出（JSON，纯本地文件）

    struct QuiltExport: Codable {
        struct H: Codable {
            var name: String
            var symbol: String
            var colorHex: Int
            var isCounter: Bool
            var dailyGoal: Int
            var weekdayMask: Int
            var scheduleKind: Int
            var timesPerWeek: Int
            var reminderStyle: Int
            var reminderStartMinute: Int
            var isArchived: Bool
            var createdAt: Date
            var checkIns: [C]
        }
        struct C: Codable {
            /// yyyy-MM-dd
            var day: String
            var count: Int
        }
        var version: Int
        var exportedAt: Date
        var habits: [H]
    }

    func exportJSON() -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let list = (habits + archivedHabits).map { h -> QuiltExport.H in
            .init(name: h.name, symbol: h.symbol, colorHex: h.colorHex,
                  isCounter: h.isCounter, dailyGoal: h.dailyGoal, weekdayMask: h.weekdayMask,
                  scheduleKind: h.scheduleKind, timesPerWeek: h.timesPerWeek,
                  reminderStyle: h.reminderStyle, reminderStartMinute: h.reminderStartMinute,
                  isArchived: h.isArchived, createdAt: h.createdAt,
                  checkIns: h.checkIns.map { .init(day: formatter.string(from: $0.day), count: $0.count) })
        }
        let export = QuiltExport(version: 1, exportedAt: Date(), habits: list)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(export) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Quilt-\(formatter.string(from: Date())).json")
        do { try data.write(to: url, options: .atomic) } catch { return nil }
        return url
    }

    /// 全量替换式导入
    func importJSON(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let export = try decoder.decode(QuiltExport.self, from: data)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        for habit in habits + archivedHabits {
            context.delete(habit)
        }
        try context.save()

        for (idx, h) in export.habits.enumerated() {
            let habit = Habit(name: h.name, symbol: h.symbol, colorHex: h.colorHex,
                              isCounter: h.isCounter, dailyGoal: h.dailyGoal,
                              weekdayMask: h.weekdayMask,
                              scheduleKind: h.scheduleKind, timesPerWeek: h.timesPerWeek,
                              reminderStyle: h.reminderStyle,
                              reminderStartMinute: h.reminderStartMinute,
                              sortOrder: idx,
                              isArchived: h.isArchived, createdAt: h.createdAt)
            context.insert(habit)
            for c in h.checkIns {
                guard let day = formatter.date(from: c.day) else { continue }
                habit.checkIns.append(CheckIn(day: day, count: c.count))
            }
        }
        try context.save()
        reload()
    }

    func clearAllData() {
        for habit in habits + archivedHabits {
            context.delete(habit)
        }
        save()
    }
}
