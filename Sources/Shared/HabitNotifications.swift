import Foundation
import UserNotifications

// MARK: - 本地提醒（App 与小组件共享）
//
// 「逐日续链 + 双日预排」调度：任意时刻每个习惯挂「今天剩余槽位 + 明天全天槽位」，
// 每次打卡/回前台/编辑保存（App 进程）与小组件打卡（扩展进程）都会全量重排。
// 两种方式：
//   固定时间 —— 今天@时间（未过点且未完成）+ 明天兜底；
//   分次提醒（计数型）—— 剩余均分到 [现在+缓冲 或 08:00（取更晚者）, 最晚时间]，
//   明天按目标次数全天预排（08:00 起）。达标当天静默，明天照常。
// 全局预算：系统待定通知上限 64 条，这里封 60，超限先砍明天再砍今天尾部。

enum HabitNotifications {

    static func requestAuth() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 某天的当天分钟数 → 具体日期
    private static func slotDate(_ day: Date, _ minuteOfDay: Int,
                                 calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: minuteOfDay / 60,
                      minute: minuteOfDay % 60, second: 0, of: day) ?? day
    }

    /// 固定模式今天这条：今天@minute，已过点则 nil
    static func fixedTodaySlot(now: Date, minute: Int, calendar: Calendar = .current) -> Date? {
        guard let slot = calendar.date(bySettingHour: minute / 60, minute: minute % 60,
                                       second: 0, of: calendar.startOfDay(for: now)) else { return nil }
        return slot > now ? slot : nil
    }

    static func tomorrowSlot(now: Date, minute: Int, calendar: Calendar = .current) -> Date? {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1,
                                           to: calendar.startOfDay(for: now)) else { return nil }
        return calendar.date(bySettingHour: minute / 60, minute: minute % 60,
                             second: 0, of: tomorrow)
    }

    /// 全量重排（App 回前台 / 每次打卡 / 编辑保存 / 小组件打卡后调用）
    @MainActor
    static func syncAll(store: Store) {
        let now = Date()
        let today = HabitMath.startOfDay(now)
        var budget = 60
        for habit in store.habits {
            guard let minute = habit.reminderMinute else { continue }
            let count = store.count(of: habit, on: today)
            let done = count >= habit.goal

            var todaySlots: [Date] = []
            var tomorrowSlots: [Date] = []
            if habit.reminderStyle == 1, habit.isCounter {
                // 分次：固定段首时刻（不随打卡漂移），打卡只刷新未来通知的进度文案
                let times = HabitMath.pacedSlotTimes(startMinute: habit.reminderStartMinute,
                                                     endMinute: minute, count: habit.goal)
                let tomorrowDay = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
                todaySlots = times.compactMap { slotDate(today, $0) > now ? slotDate(today, $0) : nil }
                budget -= todaySlots.count
                tomorrowSlots = times.compactMap { slotDate(tomorrowDay, $0) }
                budget -= tomorrowSlots.count
            } else if !done, let slot = fixedTodaySlot(now: now, minute: minute) {
                todaySlots = [slot]
                budget -= 1
                tomorrowSlots = [tomorrowSlot(now: now, minute: minute)].compactMap { $0 }
                budget -= tomorrowSlots.count
            } else {
                tomorrowSlots = [tomorrowSlot(now: now, minute: minute)].compactMap { $0 }
                budget -= tomorrowSlots.count
            }
            schedule(habit: habit, todaySlots: todaySlots, tomorrowSlots: tomorrowSlots,
                     progress: habit.isCounter ? (count, habit.goal) : nil)
        }
    }

    private static func schedule(habit: Habit, todaySlots: [Date],
                                 tomorrowSlots: [Date], progress: (Int, Int)?) {
        let center = UNUserNotificationCenter.current()
        removePending(habit)
        guard habit.reminderMinute != nil else { return }

        func content(_ body: String) -> UNMutableNotificationContent {
            let c = UNMutableNotificationContent()
            c.title = habit.name
            c.body = body
            c.sound = .default
            c.interruptionLevel = .timeSensitive   // 穿透专注/定时推送摘要，足够显眼
            c.threadIdentifier = habit.id.uuidString   // 按习惯堆叠，与其他 App 观感一致
            return c
        }

        func add(_ identifier: String, _ date: Date, _ body: String) {
            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: date)
            center.add(UNNotificationRequest(
                identifier: identifier,
                content: content(body),
                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }

        for (idx, date) in todaySlots.enumerated() {
            let body: String
            if let (count, goal) = progress {
                body = String(format: String(localized: "今日 %lld/%lld · 下一杯 💧"), count, goal)
            } else {
                body = String(localized: "到点了，缝一针，别断链 🔥")
            }
            add(notificationID(habit) + "-p\(idx)", date, body)
        }
        for (idx, date) in tomorrowSlots.enumerated() {
            add(notificationID(habit) + "-t\(idx)", date,
                String(localized: "到点了，缝一针，别断链 🔥"))
        }
    }

    /// 小组件打卡达标后：移除该习惯今天剩余的分次槽位（明天预排保留）
    static func silenceToday(habitID: String) {
        let ids = (0..<HabitMath.pacedSlotCap).map { "habit-\(habitID)-p\($0)" }
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ids)
    }

    static func cancel(for habit: Habit) {
        removePending(habit)
    }

    static func cancelAll(for habits: [Habit]) {
        for habit in habits { removePending(habit) }
    }

    private static func removePending(_ habit: Habit) {
        let id = notificationID(habit)
        var ids = [id + "-0", id + "-1"]
        for i in 0..<HabitMath.pacedSlotCap { ids.append(id + "-p\(i)") }
        for i in 0..<HabitMath.pacedSlotCap { ids.append(id + "-t\(i)") }
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static func notificationID(_ habit: Habit) -> String {
        "habit-\(habit.id.uuidString)"
    }
}
