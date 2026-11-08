import Foundation

// MARK: - 习惯数学（纯函数，零依赖，全部可单测）
//
// 所有日期一律是本地时区的 startOfDay。weekdayMask 的第 (weekday-1) 位
// 表示星期几应做：weekday 1=周日 … 7=周六（对齐 Calendar.component(.weekday)）。

/// 某天的打卡数
struct DayCount: Equatable {
    var day: Date
    var count: Int
}

/// 年格子（GitHub 贡献格子风）中的一个格子
struct GridCell: Equatable {
    var day: Date
    var due: Bool       // 当天应做（含创建日之后）
    var done: Bool
    /// count/goal，0…1+，用于颜色深浅
    var ratio: Double
    var isFuture: Bool
}

enum HabitMath {

    static let allWeekdayMask = 0b1111111

    static func isDue(mask: Int, day: Date, calendar: Calendar = .current) -> Bool {
        let wd = calendar.component(.weekday, from: day)
        return mask & (1 << (wd - 1)) != 0
    }

    static func isDone(_ count: Int, goal: Int) -> Bool {
        count >= max(goal, 1)
    }

    /// 当前连续链长。语义：
    /// - 今天应做但还没做：宽限，不断链（从昨天起算），当天结束前补上都算连着；
    /// - 不应做的天：直接跳过，不算断也不算长；
    /// - 创建日之前的天：不存在，停止计数。
    static func currentStreak(counts: [Date: Int],
                              mask: Int,
                              goal: Int,
                              created: Date,
                              today: Date,
                              calendar: Calendar = .current) -> Int {
        let todayDone = isDone(counts[today] ?? 0, goal: goal)
        var day = today
        if isDue(mask: mask, day: today, calendar: calendar), !todayDone {
            day = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        }
        let createdStart = calendar.startOfDay(for: created)
        var streak = 0
        var guardCounter = 0
        while day >= createdStart, guardCounter < 40_000 {
            if isDue(mask: mask, day: day, calendar: calendar) {
                if isDone(counts[day] ?? 0, goal: goal) {
                    streak += 1
                } else {
                    break
                }
            }
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
            guardCounter += 1
        }
        return streak
    }

    /// 历史最长链长（今天的宽限同样生效：今天没做不截断过去的链）
    static func longestStreak(counts: [Date: Int],
                              mask: Int,
                              goal: Int,
                              created: Date,
                              today: Date,
                              calendar: Calendar = .current) -> Int {
        let createdStart = calendar.startOfDay(for: created)
        var day = calendar.startOfDay(for: today)
        var run = 0
        var best = 0
        var guardCounter = 0
        while day >= createdStart, guardCounter < 40_000 {
            if isDue(mask: mask, day: day, calendar: calendar) {
                if isDone(counts[day] ?? 0, goal: goal) {
                    run += 1
                    best = max(best, run)
                } else if day != today {
                    run = 0
                }
            }
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
            guardCounter += 1
        }
        return best
    }

    /// [from, to] 区间内的完成率（应做且完成 / 应做；无应做天返回 0）
    static func completionRate(counts: [Date: Int],
                               mask: Int,
                               goal: Int,
                               created: Date,
                               from: Date,
                               to: Date,
                               calendar: Calendar = .current) -> Double {
        let createdStart = calendar.startOfDay(for: created)
        var day = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: to)
        var due = 0
        var done = 0
        var guardCounter = 0
        while day <= end, guardCounter < 40_000 {
            if day >= createdStart, isDue(mask: mask, day: day, calendar: calendar) {
                due += 1
                if isDone(counts[day] ?? 0, goal: goal) { done += 1 }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            guardCounter += 1
        }
        guard due > 0 else { return 0 }
        return Double(done) / Double(due)
    }

    /// 以「周一为首列」的 GitHub 式年格子，包含当前周在内的最近 `weeks` 周。
    /// 创建日之前与未来日期的 due=false（渲染时更淡）。
    static func gridCells(counts: [Date: Int],
                          mask: Int,
                          goal: Int,
                          created: Date,
                          today: Date,
                          weeks: Int,
                          calendar: Calendar = .current) -> [GridCell] {
        let createdStart = calendar.startOfDay(for: created)
        let todayStart = calendar.startOfDay(for: today)
        // 本周一 = today - (weekday+5)%7 天（weekday: 1=周日…7=周六）
        let wd = calendar.component(.weekday, from: todayStart)
        let mondayOffset = (wd + 5) % 7
        guard let currentWeekStart = calendar.date(byAdding: .day, value: -mondayOffset, to: todayStart) else {
            return []
        }
        guard let firstDay = calendar.date(byAdding: .day, value: -(weeks - 1) * 7, to: currentWeekStart),
              let weekEnd = calendar.date(byAdding: .day, value: 6, to: currentWeekStart) else {
            return []
        }
        var cells: [GridCell] = []
        var day = firstDay
        var guardCounter = 0
        while day <= weekEnd, guardCounter < weeks * 7 + 8 {
            let due = day >= createdStart && isDue(mask: mask, day: day, calendar: calendar)
            let count = counts[day] ?? 0
            let goalSafe = max(goal, 1)
            let ratio = due ? min(Double(count) / Double(goalSafe), 1) : 0
            cells.append(GridCell(
                day: day,
                due: due,
                done: due && isDone(count, goal: goalSafe),
                ratio: ratio,
                isFuture: day > todayStart
            ))
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            guardCounter += 1
        }
        return cells
    }

    /// 合并热力图单格：多习惯按天汇总，ratio = 完成 / 应做
    static func combinedRatio(dueCount: Int, doneCount: Int) -> Double {
        guard dueCount > 0 else { return 0 }
        return Double(doneCount) / Double(dueCount)
    }

    static func startOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    // MARK: 弹性周目标（每周 N 次）
    //
    // 连击语义按「周」折叠：一周内完成天数 ≥ N 记 1 周；
    // 本周还没达标不断链（宽限到本周日结束），从上周起算。

    /// 含 date 的那一周的周一（本地时区）
    static func weekStart(for day: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        let wd = calendar.component(.weekday, from: start)
        let mondayOffset = (wd + 5) % 7
        return calendar.date(byAdding: .day, value: -mondayOffset, to: start) ?? start
    }

    /// 某一周（截至今天，不看未来）完成的天数
    static func weeklyDoneCount(counts: [Date: Int],
                                weekStart: Date,
                                goal: Int,
                                today: Date,
                                calendar: Calendar = .current) -> Int {
        let todayStart = calendar.startOfDay(for: today)
        var day = calendar.startOfDay(for: weekStart)
        var done = 0
        var guardCounter = 0
        while day <= todayStart, guardCounter < 8 {
            if isDone(counts[day] ?? 0, goal: goal) { done += 1 }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            guardCounter += 1
        }
        return done
    }

    /// 当前连续达标周数（弹性模式）。
    /// 本周未达标 → 宽限（从上周起算）；创建周之前不存在。
    static func weeklyStreak(counts: [Date: Int],
                             timesPerWeek: Int,
                             goal: Int,
                             created: Date,
                             today: Date,
                             calendar: Calendar = .current) -> Int {
        let target = min(max(timesPerWeek, 1), 7)
        let todayStart = calendar.startOfDay(for: today)
        var week = weekStart(for: todayStart, calendar: calendar)
        let createdWeek = weekStart(for: calendar.startOfDay(for: created), calendar: calendar)
        if weeklyDoneCount(counts: counts, weekStart: week, goal: goal,
                           today: todayStart, calendar: calendar) < target {
            week = calendar.date(byAdding: .day, value: -7, to: week) ?? week
        }
        var streak = 0
        var guardCounter = 0
        while week >= createdWeek, guardCounter < 3_000 {
            if weeklyDoneCount(counts: counts, weekStart: week, goal: goal,
                               today: todayStart, calendar: calendar) >= target {
                streak += 1
            } else {
                break
            }
            week = calendar.date(byAdding: .day, value: -7, to: week) ?? week
            guardCounter += 1
        }
        return streak
    }

    /// 历史最长连续达标周数（弹性模式）
    static func longestWeeklyStreak(counts: [Date: Int],
                                    timesPerWeek: Int,
                                    goal: Int,
                                    created: Date,
                                    today: Date,
                                    calendar: Calendar = .current) -> Int {
        let target = min(max(timesPerWeek, 1), 7)
        let todayStart = calendar.startOfDay(for: today)
        var week = weekStart(for: calendar.startOfDay(for: created), calendar: calendar)
        let currentWeek = weekStart(for: todayStart, calendar: calendar)
        var run = 0
        var best = 0
        var guardCounter = 0
        while week <= currentWeek, guardCounter < 3_000 {
            if weeklyDoneCount(counts: counts, weekStart: week, goal: goal,
                               today: todayStart, calendar: calendar) >= target {
                run += 1
                best = max(best, run)
            } else if week != currentWeek {
                run = 0
            }
            week = calendar.date(byAdding: .day, value: 7, to: week) ?? week
            guardCounter += 1
        }
        return best
    }

    // MARK: 分次提醒（喝水式计数习惯）
    //
    // 把剩余次数均分到 [now+缓冲 或 当日最早时刻（取更晚者）, 当日结束时间]。
    // 深夜与清晨不排（最早时刻默认 08:00）；已过去的时间不补发；
    // 剩余多于槽位上限时仍均匀铺满整个时段（只是通知变稀）。

    static let pacedSlotCap = 6
    static let pacedBufferMinutes = 20
    /// 分次提醒时间段的默认开始（08:00）
    static let pacedDefaultStartMinute = 8 * 60

    static func pacedSlots(now: Date,
                           startMinute: Int,
                           endMinute: Int,
                           remaining: Int,
                           maxSlots: Int = pacedSlotCap,
                           bufferMinutes: Int = pacedBufferMinutes,
                           calendar: Calendar = .current) -> [Date] {
        guard remaining > 0, endMinute > startMinute else { return [] }
        let dayStart = calendar.startOfDay(for: now)
        var start = now.addingTimeInterval(TimeInterval(bufferMinutes * 60))
        if let windowStart = calendar.date(bySettingHour: startMinute / 60,
                                           minute: startMinute % 60, second: 0, of: dayStart),
           start < windowStart {
            start = windowStart
        }
        guard let end = calendar.date(bySettingHour: endMinute / 60,
                                      minute: endMinute % 60, second: 0,
                                      of: dayStart) else { return [] }
        let window = end.timeIntervalSince(start)
        guard window > 0 else { return [] }
        let slots = min(remaining, maxSlots)
        let step = window / TimeInterval(slots)
        return (1...slots).compactMap { i in
            start.addingTimeInterval(step * TimeInterval(i))
        }
    }

    /// 分次提醒的固定时刻表：把窗口均分为 N 段，取每段起点（段首触发）。
    /// N = min(目标次数, 上限)。结果只依赖窗口，与打卡时机无关（时间稳定）。
    static func pacedSlotTimes(startMinute: Int,
                               endMinute: Int,
                               count: Int,
                               calendar: Calendar = .current) -> [Int] {
        guard count > 0, endMinute > startMinute else { return [] }
        let window = endMinute - startMinute
        let n = min(count, pacedSlotCap)
        let step = window / n
        return (0..<n).map { startMinute + step * $0 }
    }

    /// 明天全天的分次槽位（前一天预约好，当天不打开 App 也不断链）：
    /// 从明天 startMinute 到 endMinute，按目标次数均分（上限 maxSlots）
    static func pacedTomorrowSlots(today: Date,
                                  startMinute: Int,
                                  endMinute: Int,
                                  goal: Int,
                                  maxSlots: Int = pacedSlotCap,
                                  calendar: Calendar = .current) -> [Date] {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1,
                                           to: calendar.startOfDay(for: today)) else { return [] }
        guard let windowStart = calendar.date(bySettingHour: startMinute / 60,
                                              minute: startMinute % 60, second: 0,
                                              of: tomorrow) else { return [] }
        return pacedSlots(now: windowStart, startMinute: startMinute, endMinute: endMinute,
                          remaining: goal, maxSlots: maxSlots, bufferMinutes: 0,
                          calendar: calendar)
    }
}
