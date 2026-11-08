import SwiftUI

// MARK: - 习惯详情：统计卡 + GitHub 式年格子 + 最近记录

struct HabitDetailView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let habit: Habit

    @State private var counts: [Date: Int] = [:]
    @State private var editing = false
    @State private var confirmDelete = false

    private let gridWeeks = 30

    var body: some View {
        ScrollView {
            VStack(spacing: DS.gap) {
                statCards
                gridCard
                recentCard
            }
            .padding(DS.pad)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(habit.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("编辑") { editing = true }
                    Button(habit.isArchived ? "取消归档" : "归档（保留历史）") {
                        store.archive(habit, !habit.isArchived)
                        dismiss()
                    }
                    Button("删除（连历史一起）", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("更多操作")
            }
        }
        .sheet(isPresented: $editing) { EditHabitView(store: store, habit: habit) }
        .confirmationDialog("删除「\(habit.name)」及其全部打卡历史？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                HabitNotifications.cancel(for: habit)
                store.delete(habit)
                dismiss()
            }
        }
        .onAppear(perform: load)
        .onReceive(store.objectWillChange) { _ in load() }
    }

    private func load() {
        counts = store.counts(habit: habit, daysBack: 800)
        if CommandLine.arguments.contains("-uitest-griddebug") {
            let cells = HabitMath.gridCells(counts: counts, mask: habit.weekdayMask,
                                            goal: habit.goal, created: habit.createdAt,
                                            today: HabitMath.startOfDay(Date()), weeks: gridWeeks)
            print("GRIDDEBUG mask=\(habit.weekdayMask) counts=\(counts.count) cells=\(cells.count) due=\(cells.filter { $0.due }.count) done=\(cells.filter { $0.done }.count)")
        }
    }

    // MARK: 统计卡

    private var statCards: some View {
        let today = HabitMath.startOfDay(Date())
        let isFlex = habit.isFlexible
        let rateMask = isFlex ? HabitMath.allWeekdayMask : habit.weekdayMask
        let streak: Int
        let longest: Int
        if isFlex {
            streak = HabitMath.weeklyStreak(counts: counts, timesPerWeek: habit.timesPerWeek,
                                            goal: habit.goal, created: habit.createdAt, today: today)
            longest = HabitMath.longestWeeklyStreak(counts: counts, timesPerWeek: habit.timesPerWeek,
                                                    goal: habit.goal, created: habit.createdAt, today: today)
        } else {
            streak = HabitMath.currentStreak(counts: counts, mask: habit.weekdayMask,
                                             goal: habit.goal, created: habit.createdAt, today: today)
            longest = HabitMath.longestStreak(counts: counts, mask: habit.weekdayMask,
                                              goal: habit.goal, created: habit.createdAt, today: today)
        }
        let rate30 = HabitMath.completionRate(
            counts: counts, mask: rateMask, goal: habit.goal, created: habit.createdAt,
            from: Calendar.current.date(byAdding: .day, value: -29, to: today) ?? today, to: today)
        let total = counts.values.reduce(0, +)
        let unit = String(localized: isFlex ? "周" : "天")

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DS.gap) {
            StatCard(title: String(localized: "当前连续"), value: "\(streak)", unit: unit, color: .flame, symbol: "flame.fill")
            StatCard(title: String(localized: "最长连续"), value: "\(longest)", unit: unit, color: .brandDeep, symbol: "trophy.fill")
            StatCard(title: String(localized: isFlex ? "30 天打卡率" : "30 天完成率"),
                     value: "\(Int((rate30 * 100).rounded()))", unit: "%", color: .brand, symbol: "chart.line.uptrend.xyaxis")
            StatCard(title: String(localized: "累计打卡"), value: "\(total)", unit: String(localized: "次"), color: .brandSoft, symbol: "checkmark.seal.fill")
        }
    }

    // MARK: 年格子

    private var gridCard: some View {
        VStack(alignment: .leading, spacing: DS.gapSmall) {
            HStack {
                Text("近 30 周")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                legend
            }
            HabitGridView(
                colorHex: habit.colorHex,
                cells: HabitMath.gridCells(counts: counts, mask: habit.weekdayMask,
                                           goal: habit.goal, created: habit.createdAt,
                                           today: HabitMath.startOfDay(Date()), weeks: gridWeeks)
            )
            Text("创建于 \(habit.createdAt.formatted(.dateTime.year().month().day()))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("少").font(.caption2).foregroundStyle(.secondary)
            ForEach([0.07, 0.3, 0.6, 1.0], id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.habitColor(habit.colorHex).opacity(level == 0.07 ? 0.07 : level))
                    .frame(width: 9, height: 9)
            }
            Text("多").font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: 最近记录

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: DS.gapSmall) {
            Text("最近记录")
                .font(.subheadline.weight(.semibold))
            let recent = counts
                .filter { $0.value > 0 }
                .sorted { $0.key > $1.key }
                .prefix(10)
            if recent.isEmpty {
                Text("还没有记录，从今天开始")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(recent), id: \.key) { day, count in
                    HStack {
                        Text(day.formatted(.dateTime.month().day().weekday()))
                            .font(.callout)
                        Spacer()
                        Text(habit.isCounter ? "×\(count)" : "✓")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(Color.habitColor(habit.colorHex))
                    }
                }
            }
        }
        .card()
    }
}

// MARK: - 统计卡

struct StatCard: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.caption2)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - 格子视图（App 与统计页共用）
//
// 自带横向滚动，出现时自动定位到最右（今天是最后一列）——
// GitHub 式格子的历史在左、当下在右，第一眼必须看到当下。

struct HabitGridView: View {
    let colorHex: Int
    let cells: [GridCell]

    var body: some View {
        let columns = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: DS.cellGap) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { idx, column in
                        VStack(spacing: DS.cellGap) {
                            ForEach(Array(column.enumerated()), id: \.element.day) { _, cell in
                                GridCellView(colorHex: colorHex, cell: cell)
                            }
                        }
                        .id(idx)
                    }
                }
                .padding(2)
            }
            .onAppear {
                if let last = columns.indices.last {
                    proxy.scrollTo(last, anchor: .trailing)
                }
            }
        }
    }
}

struct GridCellView: View {
    let colorHex: Int
    let cell: GridCell

    private var fill: Color {
        let color = Color.habitColor(colorHex)
        if cell.isFuture { return Color.primary.opacity(0.03) }
        if !cell.due { return Color.primary.opacity(0.07) }
        if cell.done { return color.opacity(0.45 + 0.55 * cell.ratio) }
        if cell.ratio > 0 { return color.opacity(0.2 + 0.4 * cell.ratio) }
        return Color.primary.opacity(0.1)
    }

    private var isToday: Bool {
        cell.day == HabitMath.startOfDay(Date())
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(fill)
            .frame(width: DS.cell, height: DS.cell)
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .strokeBorder(Color.brandDeep, lineWidth: 1.5)
                }
            }
    }
}
