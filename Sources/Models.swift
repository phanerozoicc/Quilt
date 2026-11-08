import Foundation
import SwiftData

// MARK: - 习惯

@Model
final class Habit {
    var id: UUID = UUID()
    var name: String = ""
    /// SF Symbol 名
    var symbol: String = "checkmark.circle"
    /// 习惯色板下标对应的色值（存 Int，色板见 Theme.habitPalette）
    var colorHex: Int = 0x3E9B6C
    /// false = 每日勾选；true = 计数型（如喝水 8 杯）
    var isCounter: Bool = false
    /// 计数型每日目标（勾选型恒 1）
    var dailyGoal: Int = 1
    /// 哪些天应做：bit << (weekday-1)，全 1 = 每天（scheduleKind == 0 时生效）
    var weekdayMask: Int = HabitMath.allWeekdayMask
    /// 0 = 按 weekdayMask（每天/指定星期几）；1 = 每周 N 次弹性（哪天做随意）
    var scheduleKind: Int = 0
    /// 弹性模式的每周目标次数
    var timesPerWeek: Int = 3
    /// 每日提醒 HH*60+mm，nil = 不提醒。
    /// reminderStyle == 1（分次）时它表示时间段的「结束分钟」。
    var reminderMinute: Int?
    /// 提醒方式：0 = 固定时间；1 = 分次提醒（仅计数型，剩余次数均分到当天）
    var reminderStyle: Int = 0
    /// 分次提醒时间段的「开始分钟」（默认 08:00）
    var reminderStartMinute: Int = HabitMath.pacedDefaultStartMinute
    var createdAt: Date = Date()
    var sortOrder: Int = 0
    /// 归档：不再出现在今天列表，历史保留
    var isArchived: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \CheckIn.habit)
    var checkIns: [CheckIn] = []

    init(name: String,
         symbol: String,
         colorHex: Int,
         isCounter: Bool = false,
         dailyGoal: Int = 1,
         weekdayMask: Int = HabitMath.allWeekdayMask,
         scheduleKind: Int = 0,
         timesPerWeek: Int = 3,
         reminderMinute: Int? = nil,
         reminderStyle: Int = 0,
         reminderStartMinute: Int = HabitMath.pacedDefaultStartMinute,
         sortOrder: Int = 0,
         isArchived: Bool = false,
         createdAt: Date = Date()) {
        self.name = name
        self.symbol = symbol
        self.colorHex = colorHex
        self.isCounter = isCounter
        self.dailyGoal = isCounter ? max(dailyGoal, 1) : 1
        self.weekdayMask = weekdayMask
        self.scheduleKind = scheduleKind
        self.timesPerWeek = min(max(timesPerWeek, 1), 7)
        self.reminderMinute = reminderMinute
        self.reminderStyle = reminderStyle
        self.reminderStartMinute = min(max(reminderStartMinute, 0), reminderMinute ?? 1439)
        self.createdAt = createdAt
        self.sortOrder = sortOrder
        self.isArchived = isArchived
    }

    var goal: Int { isCounter ? max(dailyGoal, 1) : 1 }

    /// 弹性模式（每周 N 次）
    var isFlexible: Bool { scheduleKind == 1 }

    /// 「可打卡日」：弹性模式天天可打；weekday 模式看掩码
    func isDue(on day: Date, calendar: Calendar = .current) -> Bool {
        isFlexible || HabitMath.isDue(mask: weekdayMask, day: day, calendar: calendar)
    }

    /// 「硬性应做日」：只算 weekday 模式（今天页进度环的分母，弹性习惯不计入）
    func isHardDue(on day: Date, calendar: Calendar = .current) -> Bool {
        !isFlexible && HabitMath.isDue(mask: weekdayMask, day: day, calendar: calendar)
    }
}

// MARK: - 打卡记录
//
// 每个 (habit, day) 一条记录，count 表示当天次数。

@Model
final class CheckIn {
    /// 本地时区 startOfDay
    var day: Date = Date()
    var count: Int = 1
    var habit: Habit?

    init(day: Date, count: Int = 1) {
        self.day = day
        self.count = count
    }
}
