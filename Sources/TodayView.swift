import SwiftUI

// MARK: - 今天页
//
// 进度环 + 习惯列表（打卡按钮内联），下拉无、长按无，就是每天那一眼。

struct TodayView: View {
    @EnvironmentObject private var store: Store
    @State private var adding = false
    @State private var editingHabit: Habit?
    @State private var path: [Habit.ID] = []

    init() {
        // 供模拟器截图验证：直接落详情页
        if CommandLine.arguments.contains("-uitest-detail"),
           let first = AppContext.shared.store.habits.first {
            _path = State(initialValue: [first.id])
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

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.habits.isEmpty {
                    EmptyState(symbol: "square.grid.3x3.topleft.filled",
                               title: String(localized: "还没有习惯"),
                               subtitle: String(localized: "点右上角 ＋ 种下第一块布片"))
                } else {
                    todayList
                }
            }
            .navigationTitle("今天")
            .toolbar {
                if !store.habits.isEmpty {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("新建习惯")
                }
            }
            .sheet(isPresented: $adding) { EditHabitView(store: store, habit: nil) }
            .sheet(item: $editingHabit) { EditHabitView(store: store, habit: $0) }
            .navigationDestination(for: Habit.ID.self) { id in
                if let habit = store.habit(id: id) {
                    HabitDetailView(habit: habit)
                }
            }
            .onAppear {
                // 供模拟器截图验证：启动即全部打卡，走真实 store 链路
                if CommandLine.arguments.contains("-uitest-checkin") {
                    for habit in dueToday {
                        store.checkInToday(habit)
                    }
                }
            }
        }
    }

    private var todayList: some View {
        List {
            Section {
                HStack(spacing: DS.gap) {
                    ProgressRing(value: doneToday, total: dueToday.count)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Date().formatted(.dateTime.month().day().weekday(.wide)))
                            .font(.headline)
                        Text(doneToday == dueToday.count && !dueToday.isEmpty
                             ? "全部完成，今天这床布又密了一格"
                             : "还剩 \(max(dueToday.count - doneToday, 0)) 件事")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .card()
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            .listSectionSpacing(DS.gapSmall)

            Section {
                ForEach(store.habits) { habit in
                    NavigationLink(value: habit.id) {
                        HabitRow(habit: habit)
                    }
                }
                .onMove { from, to in store.moveHabit(fromOffsets: from, toOffset: to) }
                .onDelete { offsets in
                    for i in offsets {
                        HabitNotifications.cancel(for: store.habits[i])
                        store.delete(store.habits[i])
                    }
                }
            }
        }
    }
}

// MARK: - 习惯行

struct HabitRow: View {
    @EnvironmentObject private var store: Store
    let habit: Habit

    private var todayCount: Int { store.todayCounts[habit.id] ?? 0 }
    private var done: Bool { todayCount >= habit.goal }

    var body: some View {
        HStack(spacing: DS.gap) {
            SymbolCircle(symbol: habit.symbol, colorHex: habit.colorHex)
            VStack(alignment: .leading, spacing: 3) {
                Text(habit.name)
                    .font(.headline)
                    .strikethrough(!habit.isFlexible && !habit.isDue(on: Date()))
                    .foregroundStyle(habit.isFlexible || habit.isDue(on: Date()) ? .primary : .secondary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(subtitleColor)
            }
            Spacer()
            StreakBadge(count: store.streak(of: habit))
            trailingControl
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        if habit.isFlexible {
            return String(localized: "本周 \(store.weeklyDone(of: habit))/\(habit.timesPerWeek) 次 · 弹性")
        }
        if !habit.isDue(on: Date()) { return String(localized: "今天不用 · ") + repeatText }
        if habit.isCounter { return String(localized: "目标 \(habit.goal) 次 · ") + repeatText }
        return repeatText
    }

    /// 弹性习惯本周已达标时副标变品牌色，给一点正反馈
    private var subtitleColor: Color {
        if habit.isFlexible, store.weeklyDone(of: habit) >= habit.timesPerWeek {
            return .brand
        }
        return .secondary
    }

    private var repeatText: String {
        if habit.isFlexible { return String(localized: "每周 \(habit.timesPerWeek) 次") }
        if habit.weekdayMask == HabitMath.allWeekdayMask { return String(localized: "每天") }
        let symbols = Calendar.current.veryShortWeekdaySymbols
        var names: [String] = []
        for wd in 1...7 where habit.weekdayMask & (1 << (wd - 1)) != 0 {
            names.append(symbols[wd - 1])
        }
        return names.joined(separator: " ")
    }

    @ViewBuilder
    private var trailingControl: some View {
        if habit.isCounter {
            HStack(spacing: DS.gapSmall) {
                if todayCount > 0 {
                    Button {
                        store.decrementToday(habit)
                    } label: {
                        Image(systemName: "minus.circle")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("\(habit.name)减一")
                }
                if done {
                    // 达标：明显的成功徽章（不只是数字变色）
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                        Text("\(todayCount)/\(habit.goal)")
                            .font(.caption.weight(.bold).monospacedDigit())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.habitColor(habit.colorHex)))
                    .fixedSize()
                } else {
                    Text("\(todayCount)/\(habit.goal)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                Button {
                    store.checkInToday(habit)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.habitColor(habit.colorHex))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(habit.name)加一")
            }
        } else {
            Button {
                store.checkInToday(habit)
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(done ? Color.habitColor(habit.colorHex) : Color.secondary.opacity(0.5))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(done ? "\(habit.name)取消打卡" : "\(habit.name)打卡")
        }
    }
}
