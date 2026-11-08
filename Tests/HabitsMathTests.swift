import XCTest
@testable import Quilt

// MARK: - HabitMath 纯函数测试
//
// 固定「今天 = 2026-09-08（周二，weekday=3）」，日历时区固定为 UTC，
// 一切断言基于显式传入的 calendar，不依赖运行环境。

final class HabitsMathTests: XCTestCase {

    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// 2026-09-08 是周二
    private var today: Date {
        var comps = DateComponents()
        comps.timeZone = TimeZone(identifier: "UTC")!
        comps.year = 2026
        comps.month = 9
        comps.day = 8
        return cal.date(from: comps)!
    }

    private func day(_ offsetFromToday: Int) -> Date {
        cal.date(byAdding: .day, value: offsetFromToday, to: today)!
    }

    private func mask(_ weekdays: [Int]) -> Int {
        weekdays.reduce(0) { $0 | (1 << ($1 - 1)) }
    }

    func testIsDueByWeekdayMask() throws {
        let m = mask([2, 4, 6])   // 周一/三/五
        XCTAssertTrue(HabitMath.isDue(mask: m, day: day(-1), calendar: cal))   // 周一
        XCTAssertFalse(HabitMath.isDue(mask: m, day: today, calendar: cal))    // 周二
        XCTAssertTrue(HabitMath.isDue(mask: HabitMath.allWeekdayMask, day: today, calendar: cal))
    }

    func testCurrentStreakWithTodayGrace() throws {
        // 每天都做，唯独今天还没做 → 宽限，链 = 昨天往前连续 N 天
        var counts: [Date: Int] = [:]
        for offset in -5...(-1) { counts[day(offset)] = 1 }
        let streak = HabitMath.currentStreak(counts: counts, mask: HabitMath.allWeekdayMask,
                                             goal: 1, created: day(-30), today: today, calendar: cal)
        XCTAssertEqual(streak, 5)

        // 今天补上 → 6
        counts[today] = 1
        let streak2 = HabitMath.currentStreak(counts: counts, mask: HabitMath.allWeekdayMask,
                                              goal: 1, created: day(-30), today: today, calendar: cal)
        XCTAssertEqual(streak2, 6)
    }

    func testCurrentStreakBreaksOnMissedDueDay() throws {
        var counts: [Date: Int] = [:]
        for offset in -10...(-3) { counts[day(offset)] = 1 }   // 前天(‑2)与昨天(‑1)都没做
        let streak = HabitMath.currentStreak(counts: counts, mask: HabitMath.allWeekdayMask,
                                             goal: 1, created: day(-30), today: today, calendar: cal)
        XCTAssertEqual(streak, 0)
    }

    func testCurrentStreakSkipsNotDueDays() throws {
        // 周一三五：周五(-4)与周一(-1)做了，周末跳过，今天周二未做 → 2
        let m = mask([2, 4, 6])
        var counts: [Date: Int] = [:]
        counts[day(-1)] = 1   // 周一
        counts[day(-4)] = 1   // 周五
        let streak = HabitMath.currentStreak(counts: counts, mask: m,
                                             goal: 1, created: day(-30), today: today, calendar: cal)
        XCTAssertEqual(streak, 2)
    }

    func testStreakStopsAtCreation() throws {
        // 昨天才创建，昨天没做，今天没做 → 0（宽限只给今天）
        let created = day(-1)
        let streak = HabitMath.currentStreak(counts: [:], mask: HabitMath.allWeekdayMask,
                                             goal: 1, created: created, today: today, calendar: cal)
        XCTAssertEqual(streak, 0)
        // 昨天做了 → 1
        let streak2 = HabitMath.currentStreak(counts: [created: 1], mask: HabitMath.allWeekdayMask,
                                              goal: 1, created: created, today: today, calendar: cal)
        XCTAssertEqual(streak2, 1)
    }

    func testLongestStreak() throws {
        var counts: [Date: Int] = [:]
        // -10…-4 连续 7 天，之后断了，最近 -1…今天连续
        for offset in -10...(-4) { counts[day(offset)] = 1 }
        for offset in -1...0 { counts[day(offset)] = 1 }
        let longest = HabitMath.longestStreak(counts: counts, mask: HabitMath.allWeekdayMask,
                                              goal: 1, created: day(-30), today: today, calendar: cal)
        XCTAssertEqual(longest, 7)
        // 当前链（含今天的宽限）= 2（昨天+今天）
        let current = HabitMath.currentStreak(counts: counts, mask: HabitMath.allWeekdayMask,
                                              goal: 1, created: day(-30), today: today, calendar: cal)
        XCTAssertEqual(current, 2)
    }

    func testCounterGoalDoneAndRatio() throws {
        // 目标 8 次，今天 8 → done；格子 ratio = 1
        let goal = 8
        XCTAssertFalse(HabitMath.isDone(5, goal: goal))
        XCTAssertTrue(HabitMath.isDone(8, goal: goal))
        let cells = HabitMath.gridCells(counts: [today: 8], mask: HabitMath.allWeekdayMask,
                                        goal: goal, created: day(-30), today: today,
                                        weeks: 4, calendar: cal)
        let todayCell = try XCTUnwrap(cells.first { $0.day == today })
        XCTAssertTrue(todayCell.done)
        XCTAssertEqual(todayCell.ratio, 1, accuracy: 0.0001)
        // 5 次的昨天：未完成但有进度
        var counts = [today: 8]
        counts[day(-1)] = 5
        let cells2 = HabitMath.gridCells(counts: counts, mask: HabitMath.allWeekdayMask,
                                         goal: goal, created: day(-30), today: today,
                                         weeks: 4, calendar: cal)
        let yesterdayCell = try XCTUnwrap(cells2.first { $0.day == day(-1) })
        XCTAssertFalse(yesterdayCell.done)
        XCTAssertEqual(yesterdayCell.ratio, 5.0 / 8.0, accuracy: 0.0001)
    }

    func testCompletionRate() throws {
        // 最近 7 天里有 3 天该做（周二不算，这里直接用每天习惯更直观）
        var counts: [Date: Int] = [:]
        for offset in [0, -1, -3] { counts[day(offset)] = 1 }   // 今天/昨天/前天(‑3)做
        let rate = HabitMath.completionRate(counts: counts, mask: HabitMath.allWeekdayMask,
                                            goal: 1, created: day(-30),
                                            from: day(-6), to: today, calendar: cal)
        XCTAssertEqual(rate, 3.0 / 7.0, accuracy: 0.0001)
    }

    func testGridCellsShapeAndMondayStart() throws {
        let cells = HabitMath.gridCells(counts: [:], mask: HabitMath.allWeekdayMask,
                                        goal: 1, created: day(-400), today: today,
                                        weeks: 26, calendar: cal)
        XCTAssertEqual(cells.count, 26 * 7)
        // 首格必须是周一（weekday == 2）
        XCTAssertEqual(cal.component(.weekday, from: cells[0].day), 2)
        // 末格必须是本周日（weekday == 1）
        XCTAssertEqual(cal.component(.weekday, from: cells[cells.count - 1].day), 1)
        // 今天存在且不是 future
        let todayCell = try XCTUnwrap(cells.first { $0.day == today })
        XCTAssertFalse(todayCell.isFuture)
        // 未来的格子标记 future
        XCTAssertTrue(cells.last!.isFuture)
    }

    func testGridCellsBeforeCreationNotDue() throws {
        let created = day(-7)
        let cells = HabitMath.gridCells(counts: [:], mask: HabitMath.allWeekdayMask,
                                        goal: 1, created: created, today: today,
                                        weeks: 4, calendar: cal)
        let before = cells.filter { $0.day < created }
        XCTAssertFalse(before.isEmpty)
        XCTAssertTrue(before.allSatisfy { !$0.due && !$0.done }, "创建日之前的格子不应算应做")
        let active = cells.filter { $0.day >= created && !$0.isFuture }
        XCTAssertTrue(active.allSatisfy { $0.due }, "创建之后（含今天）每天都应做")
    }

    func testCombinedRatio() {
        XCTAssertEqual(HabitMath.combinedRatio(dueCount: 0, doneCount: 0), 0)
        XCTAssertEqual(HabitMath.combinedRatio(dueCount: 4, doneCount: 2), 0.5)
    }
}

// MARK: - 弹性周目标（每周 N 次）

extension HabitsMathTests {

    private func week(_ offset: Int) -> Date {
        HabitMath.weekStart(for: day(offset), calendar: cal)
    }

    func testWeekStartIsMonday() throws {
        let ws = try XCTUnwrap(HabitMath.weekStart(for: today, calendar: cal))   // 周二
        XCTAssertEqual(cal.component(.weekday, from: ws), 2, "周起点必须是周一")
        XCTAssertEqual(cal.component(.day, from: ws), 7, "2026-09-08 所在周的周一是 9/7")
    }

    func testWeeklyStreakWithMidWeekGrace() throws {
        // 目标每周 3 次；本周（周二）只做了 1 天 → 宽限，不算断链，从上周数
        var precise: [Date: Int] = [:]
        let lastWeekMonday = week(-7)
        for d in 0..<3 { precise[cal.date(byAdding: .day, value: d, to: lastWeekMonday)!] = 1 }
        precise[day(0)] = 1
        let s = HabitMath.weeklyStreak(counts: precise, timesPerWeek: 3, goal: 1,
                                       created: day(-30), today: today, calendar: cal)
        XCTAssertEqual(s, 1, "上周达标 + 本周未完（宽限）→ 连续 1 周")
    }

    func testWeeklyStreakBreaksAfterFullMissedWeek() throws {
        var counts: [Date: Int] = [:]
        let twoWeeksAgo = week(-14)
        for d in 0..<3 { counts[cal.date(byAdding: .day, value: d, to: twoWeeksAgo)!] = 1 }
        // 上周整周空白 + 本周只做 1 天 → 宽限从上周起算，上周不达标 → 0
        counts[day(0)] = 1
        let s = HabitMath.weeklyStreak(counts: counts, timesPerWeek: 3, goal: 1,
                                       created: day(-30), today: today, calendar: cal)
        XCTAssertEqual(s, 0)
    }

    func testWeeklyStreakCountsWhenThisWeekMet() throws {
        // 目标每周 2 次；周一周二各一次（今天周二，未来日不算）→ 立即记 1 周
        var counts: [Date: Int] = [:]
        let thisWeek = week(0)
        for d in 0..<2 { counts[cal.date(byAdding: .day, value: d, to: thisWeek)!] = 1 }
        let s = HabitMath.weeklyStreak(counts: counts, timesPerWeek: 2, goal: 1,
                                       created: day(-30), today: today, calendar: cal)
        XCTAssertEqual(s, 1, "本周已攒够 2 天 → 立即记 1 周")
    }

    func testLongestWeeklyStreak() throws {
        var counts: [Date: Int] = [:]
        // 两周连达（-21、-14 周的周一~周三）→ 最佳 2；之后一周空档断链
        for w in [-21, -14] {
            let ws = week(w)
            for d in 0..<3 { counts[cal.date(byAdding: .day, value: d, to: ws)!] = 1 }
        }
        let best = HabitMath.longestWeeklyStreak(counts: counts, timesPerWeek: 3, goal: 1,
                                                 created: day(-40), today: today, calendar: cal)
        XCTAssertEqual(best, 2)
    }
}

// MARK: - 分次提醒槽位（喝水式计数习惯）

extension HabitsMathTests {

    /// 固定测试时刻：当天 14:00
    private var noon: Date {
        cal.date(bySettingHour: 14, minute: 0, second: 0, of: today)!
    }

    func testPacedSlotsSpreadEvenly() throws {
        // 剩 4 杯，最晚到 22:00（1400 分钟 = 8 小时窗口，扣 20 分钟缓冲）
        let slots = HabitMath.pacedSlots(now: noon, startMinute: 8 * 60, endMinute: 22 * 60,
                                         remaining: 4, calendar: cal)
        XCTAssertEqual(slots.count, 4)
        // 升序、首个不早于 now+缓冲、末个不晚于结束
        XCTAssertGreaterThanOrEqual(slots[0], noon.addingTimeInterval(20 * 60))
        XCTAssertLessThanOrEqual(slots.last!.timeIntervalSince(noon), 8 * 3600 + 1)
        for i in 1..<slots.count {
            XCTAssertGreaterThan(slots[i], slots[i - 1])
        }
    }

    func testPacedSlotsCapAndFullWindow() throws {
        // 剩 12 杯 > 上限 6 → 只排 6 条，但均匀铺满整个时段
        let slots = HabitMath.pacedSlots(now: noon, startMinute: 8 * 60, endMinute: 22 * 60,
                                         remaining: 12, calendar: cal)
        XCTAssertEqual(slots.count, HabitMath.pacedSlotCap)
        let span = slots.last!.timeIntervalSince(slots[0])
        let window = TimeInterval(7 * 3600 + 40 * 60)   // 14:20 → 22:00
        XCTAssertEqual(span, window * 5.0 / 6.0, accuracy: 2, "6 条应铺满窗口")
    }

    func testPacedSlotsEdgeCases() {
        // 已达标
        XCTAssertTrue(HabitMath.pacedSlots(now: noon, startMinute: 8 * 60, endMinute: 22 * 60,
                                           remaining: 0, calendar: cal).isEmpty)
        // 结束时间早于开始时间（窗口倒挂）
        XCTAssertTrue(HabitMath.pacedSlots(now: noon, startMinute: 8 * 60, endMinute: 7 * 60,
                                           remaining: 4, calendar: cal).isEmpty)
        // 结束时间已过
        XCTAssertTrue(HabitMath.pacedSlots(now: noon, startMinute: 8 * 60, endMinute: 13 * 60,
                                           remaining: 4, calendar: cal).isEmpty)
        // 剩余时间不足缓冲
        XCTAssertTrue(HabitMath.pacedSlots(now: noon, startMinute: 8 * 60, endMinute: 14 * 60 + 10,
                                           remaining: 4, calendar: cal).isEmpty)
    }

    func testFixedTodaySlot() throws {
        // 14:00 提醒 15:00 → 今天这条存在；提醒 13:00 → 已过点 nil
        let slot15 = HabitNotifications.fixedTodaySlot(now: noon, minute: 15 * 60, calendar: cal)
        XCTAssertEqual(slot15, cal.date(bySettingHour: 15, minute: 0, second: 0, of: today))
        XCTAssertNil(HabitNotifications.fixedTodaySlot(now: noon, minute: 13 * 60, calendar: cal))
    }
}

extension HabitsMathTests {

    // MARK: 分次提醒：清晨下限与明天全天预排

    func testPacedSlotsRespectEarlyMorningFloor() throws {
        // 现在 06:00，结束 21:00 → 槽位不得早于 08:00
        let sixAM = try XCTUnwrap(cal.date(bySettingHour: 6, minute: 0, second: 0, of: today))
        let slots = HabitMath.pacedSlots(now: sixAM, startMinute: 8 * 60, endMinute: 21 * 60,
                                         remaining: 6, calendar: cal)
        let floor = try XCTUnwrap(cal.date(bySettingHour: 8, minute: 0, second: 0, of: today))
        XCTAssertEqual(slots.count, 6)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(slots.first), floor, "清晨不应有槽位")
    }

    func testPacedTomorrowSlotsCoverFullDay() throws {
        // 明天预排：目标 8 次 → 上限 6 条，全部落在明天 08:00–21:00
        let slots = HabitMath.pacedTomorrowSlots(today: today, startMinute: 8 * 60,
                                                 endMinute: 21 * 60, goal: 8, calendar: cal)
        let tomorrow = try XCTUnwrap(cal.date(byAdding: .day, value: 1, to: today))
        let floor = try XCTUnwrap(cal.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow))
        let ceil = try XCTUnwrap(cal.date(bySettingHour: 21, minute: 0, second: 0, of: tomorrow))
        XCTAssertEqual(slots.count, HabitMath.pacedSlotCap)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(slots.first), floor)
        XCTAssertLessThanOrEqual(try XCTUnwrap(slots.last), ceil)
        for i in 1..<slots.count {
            XCTAssertGreaterThan(slots[i], slots[i - 1])
        }
    }
}

extension HabitsMathTests {

    // MARK: 分次提醒固定时刻表（段首触发，与打卡时机无关）

    func testPacedSlotTimesStableSegmentStarts() {
        // 8:00–21:00（780 分钟），目标 8 次 → 上限 6 段，段首 = 8:00 起每 130 分钟
        let times = HabitMath.pacedSlotTimes(startMinute: 480, endMinute: 1260,
                                             count: 8, calendar: cal)
        XCTAssertEqual(times, [480, 610, 740, 870, 1000, 1130])
        // 首个 = 窗口起点（段首触发）
        XCTAssertEqual(times.first, 480)
        // 末个 < 窗口终点（每段终点不触发）
        XCTAssertLessThan(times.last!, 1260)
    }

    func testPacedSlotTimesSmallCount() {
        // 目标 2 次 → 两等分：8:00 与 14:30
        let times = HabitMath.pacedSlotTimes(startMinute: 480, endMinute: 1260,
                                             count: 2, calendar: cal)
        XCTAssertEqual(times, [480, 870])
    }

    func testPacedSlotTimesEdgeCases() {
        XCTAssertTrue(HabitMath.pacedSlotTimes(startMinute: 480, endMinute: 480,
                                               count: 3, calendar: cal).isEmpty)
        XCTAssertTrue(HabitMath.pacedSlotTimes(startMinute: 480, endMinute: 1260,
                                               count: 0, calendar: cal).isEmpty)
    }
}
