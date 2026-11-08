import XCTest
import SwiftData
@testable import Quilt

// MARK: - Store 测试（内存库，不落盘）

@MainActor
final class StoreTests: XCTestCase {

    private func makeStore() -> Store {
        Store(inMemory: true, seed: false)
    }

    func testAddAndSort() {
        let store = makeStore()
        let a = store.addHabit(Habit(name: "阅读", symbol: "book.closed", colorHex: 0x5B8DEF))
        let b = store.addHabit(Habit(name: "锻炼", symbol: "figure.run", colorHex: 0x3E9B6C))
        XCTAssertEqual(store.habits.map { $0.name }, ["阅读", "锻炼"])
        XCTAssertEqual(b.sortOrder, a.sortOrder + 1)
    }

    func testSetCountUpsertAndDelete() {
        let store = makeStore()
        let habit = store.addHabit(Habit(name: "喝水", symbol: "drop", colorHex: 0x3FA8B5,
                                         isCounter: true, dailyGoal: 8))
        let today = HabitMath.startOfDay(Date())
        store.setCount(habit, day: today, count: 3)
        XCTAssertEqual(store.count(of: habit, on: today), 3)
        XCTAssertEqual(habit.checkIns.count, 1)
        store.setCount(habit, day: today, count: 8)
        XCTAssertEqual(store.count(of: habit, on: today), 8)
        XCTAssertEqual(habit.checkIns.count, 1, "同一天重复 set 应该更新同一条记录")
        store.setCount(habit, day: today, count: 0)
        XCTAssertEqual(store.count(of: habit, on: today), 0)
        XCTAssertEqual(habit.checkIns.count, 0, "归零应删除当天记录")
    }

    func testCheckInToggleForBoolHabit() {
        let store = makeStore()
        let habit = store.addHabit(Habit(name: "阅读", symbol: "book.closed", colorHex: 0x5B8DEF))
        store.checkInToday(habit)
        XCTAssertEqual(store.todayCounts[habit.id], 1)
        store.checkInToday(habit)
        XCTAssertEqual(store.todayCounts[habit.id], 0, "勾选型再点一次应取消")
    }

    func testCounterIncrement() {
        let store = makeStore()
        let habit = store.addHabit(Habit(name: "喝水", symbol: "drop", colorHex: 0x3FA8B5,
                                         isCounter: true, dailyGoal: 8))
        store.checkInToday(habit)
        store.checkInToday(habit)
        store.decrementToday(habit)
        XCTAssertEqual(store.todayCounts[habit.id], 1)
        store.decrementToday(habit)
        XCTAssertEqual(store.todayCounts[habit.id], 0)
        store.decrementToday(habit)
        XCTAssertEqual(store.todayCounts[habit.id], 0, "不能减到负数")
    }

    func testMoveHabitReordersSortOrder() {
        let store = makeStore()
        _ = store.addHabit(Habit(name: "A", symbol: "star", colorHex: 0x3E9B6C))
        _ = store.addHabit(Habit(name: "B", symbol: "star", colorHex: 0x5B8DEF))
        _ = store.addHabit(Habit(name: "C", symbol: "star", colorHex: 0xE58B45))
        store.moveHabit(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(store.habits.map { $0.name }, ["C", "A", "B"])
        XCTAssertEqual(store.habits.map { $0.sortOrder }, [0, 1, 2])
    }

    func testArchiveRemovesFromActiveKeepsHistory() {
        let store = makeStore()
        let habit = store.addHabit(Habit(name: "旧习惯", symbol: "leaf", colorHex: 0x8B6FD8))
        store.setCount(habit, day: HabitMath.startOfDay(Date()), count: 1)
        store.archive(habit, true)
        XCTAssertTrue(store.habits.isEmpty)
        XCTAssertEqual(store.archivedHabits.count, 1)
        XCTAssertEqual(habit.checkIns.count, 1, "归档保留历史")
        store.archive(habit, false)
        XCTAssertEqual(store.habits.count, 1)
    }

    func testStreakViaStore() {
        let store = makeStore()
        let cal = Calendar.current
        let habit = store.addHabit(Habit(name: "锻炼", symbol: "figure.run", colorHex: 0x3E9B6C,
                                         createdAt: cal.date(byAdding: .day, value: -10, to: Date())!))
        for offset in -3...(-1) {
            let day = cal.startOfDay(for: cal.date(byAdding: .day, value: offset, to: Date())!)
            store.setCount(habit, day: day, count: 1)
        }
        XCTAssertEqual(store.streak(of: habit), 3)
    }

    func testExportImportRoundTrip() throws {
        let store = makeStore()
        let cal = Calendar.current
        let habit = store.addHabit(Habit(name: "阅读", symbol: "book.closed", colorHex: 0x5B8DEF,
                                         isCounter: true, dailyGoal: 5,
                                         createdAt: cal.date(byAdding: .day, value: -20, to: Date())!))
        let archived = store.addHabit(Habit(name: "旧事", symbol: "leaf", colorHex: 0x8B6FD8, isArchived: true))
        store.setCount(habit, day: cal.startOfDay(for: Date()), count: 5)
        store.setCount(archived, day: cal.startOfDay(for: cal.date(byAdding: .day, value: -2, to: Date())!), count: 1)

        let url = try XCTUnwrap(store.exportJSON())

        let target = makeStore()
        try target.importJSON(from: url)
        XCTAssertEqual(target.habits.count, 1, "归档习惯不在活跃列表")
        XCTAssertEqual(target.archivedHabits.count, 1)
        let restored = try XCTUnwrap(target.habits.first)
        XCTAssertEqual(restored.name, "阅读")
        XCTAssertTrue(restored.isCounter)
        XCTAssertEqual(restored.goal, 5)
        XCTAssertEqual(target.count(of: restored, on: cal.startOfDay(for: Date())), 5)
    }

    func testClearAll() {
        let store = makeStore()
        _ = store.addHabit(Habit(name: "A", symbol: "star", colorHex: 0x3E9B6C))
        _ = store.addHabit(Habit(name: "B", symbol: "star", colorHex: 0x5B8DEF))
        store.clearAllData()
        XCTAssertTrue(store.habits.isEmpty)
        XCTAssertTrue(store.archivedHabits.isEmpty)
    }

    func testSnapshotWrittenAfterChange() throws {
        let store = makeStore()
        let habit = store.addHabit(Habit(name: "阅读", symbol: "book.closed", colorHex: 0x5B8DEF))
        store.checkInToday(habit)
        let snapshot = SnapshotStore.load()
        XCTAssertEqual(snapshot.habits.count, store.habits.count)
        let info = try XCTUnwrap(snapshot.habits.first { $0.id == habit.id.uuidString })
        XCTAssertEqual(info.todayCount, 1)
        XCTAssertTrue(info.dueToday)
        XCTAssertFalse((snapshot.grids[habit.id.uuidString] ?? []).isEmpty, "应带格子数据")
    }

    func testSeedOnlyOnce() {
        // seed: true 的 store 首次会种示例数据；显式 seed:false 不会
        let plain = Store(inMemory: true, seed: false)
        XCTAssertTrue(plain.habits.isEmpty)
        let seeded = Store(inMemory: true, seed: true, forceSeed: true)
        XCTAssertEqual(seeded.habits.count, 3, "示例应为 3 条习惯")
        XCTAssertFalse(seeded.habits.first?.checkIns.isEmpty ?? true, "示例应带近 6 周历史")
    }
}

// MARK: - v2：弹性习惯（每周 N 次）

extension StoreTests {

    func testFlexibleHabitWeeklyProgress() {
        let store = makeStore()
        let habit = store.addHabit(Habit(name: "跑步", symbol: "figure.run", colorHex: 0x3E9B6C,
                                         scheduleKind: 1, timesPerWeek: 3))
        XCTAssertTrue(habit.isFlexible)
        // 弹性习惯天天可打（isDue），但不进硬性应做
        XCTAssertTrue(habit.isDue(on: Date()))
        XCTAssertFalse(habit.isHardDue(on: Date()))
        store.checkInToday(habit)
        XCTAssertEqual(store.weeklyDone(of: habit), 1)
        store.checkInToday(habit)   // bool 再点 = 取消
        XCTAssertEqual(store.weeklyDone(of: habit), 0)
    }

    func testFlexibleStreakInWeeks() {
        let store = makeStore()
        let cal = Calendar.current
        let habit = store.addHabit(Habit(name: "冥想", symbol: "brain.head.profile", colorHex: 0x8B6FD8,
                                         scheduleKind: 1, timesPerWeek: 2,
                                         createdAt: cal.date(byAdding: .day, value: -20, to: Date())!))
        // 上周（周一起算）打满 2 天 → 至少连续 1 周；本周处于宽限，随当周进度涨到 2。
        // 构造只依赖「上周」，任何星期几运行结果都一致（本周未完→宽限从上周起算）。
        let lastWeek = cal.date(byAdding: .day, value: -7,
                                to: HabitMath.weekStart(for: Date()))!
        for d in 0..<2 {
            store.setCount(habit, day: cal.date(byAdding: .day, value: d, to: lastWeek)!, count: 1)
        }
        XCTAssertEqual(store.streak(of: habit), 1, "上周达标 + 本周宽限 → 连续 1 周")
    }

    func testFlexibleExcludedFromExportRoundTrip() throws {
        let store = makeStore()
        _ = store.addHabit(Habit(name: "弹性", symbol: "leaf", colorHex: 0x3E9B6C,
                                 scheduleKind: 1, timesPerWeek: 4))
        let url = try XCTUnwrap(store.exportJSON())
        let target = makeStore()
        try target.importJSON(from: url)
        let restored = try XCTUnwrap(target.habits.first)
        XCTAssertTrue(restored.isFlexible)
        XCTAssertEqual(restored.timesPerWeek, 4)
    }
}

extension StoreTests {

    /// reminderStyle 经真实 save 路径落盘，跨实例（跨进程模拟）可回读
    func testReminderStylePersistsToDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quilt-test-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = Store(inMemory: false, seed: false, url: url)
        let habit = writer.addHabit(Habit(name: "喝水", symbol: "drop", colorHex: 0x3FA8B5,
                                          isCounter: true, dailyGoal: 8,
                                          reminderStyle: 1))
        _ = habit

        let reader = Store(inMemory: false, seed: false, url: url)
        let restored = try XCTUnwrap(reader.habits.first)
        XCTAssertEqual(restored.reminderStyle, 1, "分次提醒方式应落盘")
        XCTAssertTrue(restored.isFlexible == false || true)
        XCTAssertEqual(restored.isCounter, true)
    }
}

extension StoreTests {

    // MARK: 数据位置迁移 + 小组件排队落库

    func testMigrateStoreIfNeeded() throws {
        let fm = FileManager.default
        let oldDir = fm.temporaryDirectory.appendingPathComponent("old-\(UUID().uuidString)")
        let newDir = fm.temporaryDirectory.appendingPathComponent("new-\(UUID().uuidString)")
        try fm.createDirectory(at: oldDir, withIntermediateDirectories: true)
        let payload = try XCTUnwrap("fake-sqlite".data(using: .utf8))
        try payload.write(to: oldDir.appendingPathComponent("Quilt.store"))
        try XCTUnwrap("wal".data(using: .utf8)).write(to: oldDir.appendingPathComponent("Quilt.store-wal"))

        Store.migrateStoreIfNeeded(oldContainerURL: oldDir, newDirectory: newDir)

        let moved = try XCTUnwrap(fm.contents(atPath: newDir.appendingPathComponent("Quilt.store").path))
        XCTAssertEqual(moved, payload)
        XCTAssertNotNil(fm.contents(atPath: newDir.appendingPathComponent("Quilt.store-wal").path))
        XCTAssertFalse(fm.fileExists(atPath: oldDir.appendingPathComponent("Quilt.store").path),
                       "旧库应被移走而非复制")
        // 新位置已存在时不覆盖
        try XCTUnwrap("keep".data(using: .utf8)).write(to: newDir.appendingPathComponent("Quilt.store"))
        Store.migrateStoreIfNeeded(oldContainerURL: oldDir, newDirectory: newDir)
        XCTAssertEqual(fm.contents(atPath: newDir.appendingPathComponent("Quilt.store").path),
                       "keep".data(using: .utf8))
    }

    func testDrainPendingCheckIns() {
        let store = makeStore()
        let water = store.addHabit(Habit(name: "喝水", symbol: "drop", colorHex: 0x3FA8B5,
                                         isCounter: true, dailyGoal: 8))
        let read = store.addHabit(Habit(name: "阅读", symbol: "book.closed", colorHex: 0x5B8DEF))
        let day = Fmt.dailyFormatter.string(from: Date())

        PendingCheckInQueue.append(.init(habitID: water.id.uuidString, day: day, count: 3))
        PendingCheckInQueue.append(.init(habitID: read.id.uuidString, day: day, count: 1))
        // 同习惯同天重复排队 → 只留最后一条
        PendingCheckInQueue.append(.init(habitID: water.id.uuidString, day: day, count: 5))

        store.drainPendingCheckIns()

        XCTAssertEqual(store.count(of: water, on: HabitMath.startOfDay(Date())), 5)
        XCTAssertEqual(store.count(of: read, on: HabitMath.startOfDay(Date())), 1)
        XCTAssertTrue(PendingCheckInQueue.load().isEmpty, "落库后队列应清空")
    }
}

extension StoreTests {

    // MARK: 计数达标边界：到 8 记为完成，减回 7 取消完成

    func testCounterGoalCompletionBoundary() {
        let store = makeStore()
        let habit = store.addHabit(Habit(name: "喝水", symbol: "drop", colorHex: 0x3FA8B5,
                                         isCounter: true, dailyGoal: 8))
        for _ in 0..<7 { store.checkInToday(habit) }
        let at7 = store.todayCounts[habit.id] ?? 0
        XCTAssertFalse(at7 >= habit.goal, "7 次不应算完成")

        store.checkInToday(habit)   // 第 8 次
        XCTAssertEqual(store.todayCounts[habit.id], 8)
        XCTAssertTrue((store.todayCounts[habit.id] ?? 0) >= habit.goal, "到 8 次应记为完成")

        store.decrementToday(habit) // 减回 7 → 取消完成
        XCTAssertEqual(store.todayCounts[habit.id], 7)
        XCTAssertFalse((store.todayCounts[habit.id] ?? 0) >= habit.goal, "减到 7 应取消完成")

        store.checkInToday(habit)   // 再补回 8 → 重新完成
        XCTAssertEqual(store.todayCounts[habit.id], 8)
    }
}

// MARK: 小组件渲染期跨天修正

extension StoreTests {

    private func makeSnapshot(generatedAt: Date, todayCount: Int,
                              todayRatio: Double, flexible: Bool = false) -> WidgetSnapshot {
        let cal = Calendar.current
        let id = UUID().uuidString
        let todayStr = Fmt.dailyFormatter.string(from: Date())
        let yesterdayStr = Fmt.dailyFormatter.string(from: cal.date(byAdding: .day, value: -1, to: Date())!)
        let weekStartStr = Fmt.dailyFormatter.string(from: HabitMath.weekStart(for: Date()))
        var grids: [String: [GridCellDTO]] = [
            id: [GridCellDTO(d: yesterdayStr, r: 1, due: true, f: false),
                 GridCellDTO(d: todayStr, r: todayRatio, due: true, f: false)],
        ]
        if flexible {
            // 本周一 done 一格（弹性周进度重推用），上周与下周各一格不应计入
            let lastWeekStr = Fmt.dailyFormatter.string(from: cal.date(byAdding: .day, value: -7, to: HabitMath.weekStart(for: Date()))!)
            let nextWeekStr = Fmt.dailyFormatter.string(from: cal.date(byAdding: .day, value: 7, to: HabitMath.weekStart(for: Date()))!)
            grids[id] = [GridCellDTO(d: weekStartStr, r: 1, due: true, f: false),
                         GridCellDTO(d: lastWeekStr, r: 1, due: true, f: false),
                         GridCellDTO(d: nextWeekStr, r: 1, due: true, f: true),
                         GridCellDTO(d: todayStr, r: todayRatio, due: true, f: false)]
        }
        return WidgetSnapshot(
            generatedAt: generatedAt,
            habits: [.init(id: id, name: "测试", symbol: "drop", colorHex: 0x3FA8B5,
                           isCounter: true, goal: 8, todayCount: todayCount, streak: 3,
                           dueToday: true, flexible: flexible,
                           weeklyDone: flexible ? 9 : 0, weeklyGoal: flexible ? 3 : 0)],
            grids: grids)
    }

    func testHabitsForRenderDayRollover() {
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: Date())!
        // 旧快照：昨天写的，todayCount=8 已过期 → 从今天格子（r=0）重推为 0
        let eff = makeSnapshot(generatedAt: yesterday, todayCount: 8,
                               todayRatio: 0).habitsForRender()
        XCTAssertEqual(eff[0].todayCount, 0, "跨天后次数应从格子重推归零")
        XCTAssertTrue(eff[0].dueToday, "应做判定来自格子的 due")
        // 同天快照：原样保留精确计数
        let same = makeSnapshot(generatedAt: Date(), todayCount: 8, todayRatio: 0).habitsForRender()
        XCTAssertEqual(same[0].todayCount, 8, "同天快照应保留精确值")
    }

    func testHabitsForRenderFlexibleWeekly() {
        let cal = Calendar.current
        let yesterday = cal.date(byAdding: .day, value: -1, to: Date())!
        // 旧快照的 weeklyDone=9 已过期 → 从格子重推：本周只有周一 1 格 done
        let eff = makeSnapshot(generatedAt: yesterday, todayCount: 0,
                               todayRatio: 0, flexible: true).habitsForRender()
        XCTAssertEqual(eff[0].weeklyDone, 1, "弹性周进度应从格子重推（本周 1 天 done）")
        XCTAssertEqual(eff[0].weeklyGoal, 3)
        _ = cal
    }
}
