import SwiftUI

// MARK: - 统计页：今日概览 + 全习惯合并热力图 + 各习惯横条

struct StatsView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.gap) {
                    if store.habits.isEmpty {
                        EmptyState(symbol: "chart.bar",
                                   title: String(localized: "还没有数据"),
                                   subtitle: String(localized: "先在「今天」页建一个习惯"))
                    } else {
                        overviewCard
                        combinedHeatCard
                        rankingCard
                    }
                }
                .padding(DS.pad)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("统计")
        }
    }

    /// 硬性应做（弹性「每周 N 次」不计入进度环分母）
    private var dueToday: [Habit] {
        let today = Date()
        return store.habits.filter { $0.isHardDue(on: today) }
    }

    private var doneToday: Int {
        dueToday.filter { (store.todayCounts[$0.id] ?? 0) >= $0.goal }.count
    }

    // MARK: 今日概览

    private var overviewCard: some View {
        HStack(spacing: DS.gap) {
            ProgressRing(value: doneToday, total: dueToday.count, size: 76)
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "今日概览"))
                        .font(.subheadline.weight(.semibold))
                    LabeledStat(String(localized: "应做"), "\(dueToday.count)", .brand)
                    LabeledStat(String(localized: "已完成"), "\(doneToday)", .brandDeep)
                    LabeledStat(String(localized: "累计打卡"),
                                totalCheckIns(), .flame)
                }
            Spacer()
        }
        .card()
    }

    private func LabeledStat(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
        }
    }

    private func totalCheckIns() -> String {
        var total = 0
        for habit in store.habits + store.archivedHabits {
            total += habit.checkIns.reduce(0) { $0 + ($1.count > 0 ? 1 : 0) }
        }
        return "\(total)"
    }

    // MARK: 合并热力图

    private var combinedHeatCard: some View {
        VStack(alignment: .leading, spacing: DS.gapSmall) {
            Text("全部习惯 · 近 26 周")
                .font(.subheadline.weight(.semibold))
            HabitGridView(colorHex: 0x3E9B6C, cells: combinedCells())
            Text("颜色 = 当天应做习惯的完成比例")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private func combinedCells() -> [GridCell] {
        let today = HabitMath.startOfDay(Date())
        guard let first = store.habits.first else { return [] }
        // 用第一个习惯的日历范围铺底，再逐日合并（只统计硬性应做，弹性习惯不进分母）
        var cells = HabitMath.gridCells(counts: [:], mask: HabitMath.allWeekdayMask, goal: 1,
                                        created: first.createdAt, today: today, weeks: 26)
        for i in cells.indices {
            let day = cells[i].day
            let due = store.habits.filter { $0.createdAt <= day && $0.isHardDue(on: day) }
            let done = due.filter { (store.count(of: $0, on: day)) >= $0.goal }.count
            cells[i].due = !due.isEmpty
            cells[i].done = !due.isEmpty && done == due.count
            cells[i].ratio = HabitMath.combinedRatio(dueCount: due.count, doneCount: done)
            cells[i].isFuture = day > today
        }
        return cells
    }

    // MARK: 排行

    private var rankingCard: some View {
        VStack(alignment: .leading, spacing: DS.gap) {
            Text("30 天完成率")
                .font(.subheadline.weight(.semibold))
            ForEach(store.habits) { habit in
                HabitRateRow(habit: habit, store: store)
            }
        }
        .card()
    }
}

struct HabitRateRow: View {
    let habit: Habit
    @ObservedObject var store: Store

    var body: some View {
        let today = HabitMath.startOfDay(Date())
        // 弹性习惯按「天天可打」算打卡率
        let mask = habit.isFlexible ? HabitMath.allWeekdayMask : habit.weekdayMask
        let rate = HabitMath.completionRate(
            counts: store.counts(habit: habit, daysBack: 60),
            mask: mask, goal: habit.goal, created: habit.createdAt,
            from: Calendar.current.date(byAdding: .day, value: -29, to: today) ?? today,
            to: today)
        return HStack(spacing: DS.gap) {
            SymbolCircle(symbol: habit.symbol, colorHex: habit.colorHex, size: 30)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(habit.name).font(.callout.weight(.medium))
                    Spacer()
                    Text("\(Int((rate * 100).rounded()))%")
                        .font(.callout.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.habitColor(habit.colorHex))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.07))
                        Capsule()
                            .fill(Color.habitColor(habit.colorHex))
                            .frame(width: geo.size.width * rate)
                    }
                }
                .frame(height: 6)
            }
        }
    }
}
