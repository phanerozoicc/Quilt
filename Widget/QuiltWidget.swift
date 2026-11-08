import WidgetKit
import SwiftUI
import AppIntents

// MARK: - 小组件：今日清单（中/大）+ 单习惯格子（中，可长按选习惯）
//
// 数据来自 App 写入 App Group 的快照 JSON；打卡按钮用 AppIntent 直接写
// 共享 SwiftData 库，成功后刷新时间线。

/// 时间线重载时机：30 分钟兜底，但对齐到下一个午夜——
/// 跨天那一刻组件主动重渲染（配合渲染期重算，新的一天数据立即正确）
private func nextReloadDate(from date: Date = Date()) -> Date {
    let calendar = Calendar.current
    let nextMidnight = calendar.startOfDay(for: date).addingTimeInterval(86_400 + 60)
    return min(date.addingTimeInterval(1_800), nextMidnight)
}

@main
struct QuiltWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayListWidget()
        HabitGridWidget()
        TodayProgressWidget()
        StreakWidget()
    }
}

// MARK: - 时间线（今日习惯：可配置选习惯，小尺寸单卡 / 中大清单）

struct TodayIntentEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    /// 用户在组件配置里选中的习惯（nil = 自动轮换）
    let habitID: String?
}

struct TodayIntentProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TodayIntentEntry {
        TodayIntentEntry(date: Date(), snapshot: SnapshotStore.load(), habitID: nil)
    }

    func snapshot(for configuration: SelectHabitIntent, in context: Context) async -> TodayIntentEntry {
        TodayIntentEntry(date: Date(), snapshot: SnapshotStore.load(),
                         habitID: configuration.habit?.id)
    }

    func timeline(for configuration: SelectHabitIntent, in context: Context) async -> Timeline<TodayIntentEntry> {
        let entry = TodayIntentEntry(date: Date(), snapshot: SnapshotStore.load(),
                                     habitID: configuration.habit?.id)
        return Timeline(entries: [entry], policy: .after(nextReloadDate()))
    }
}

// MARK: - 时间线（习惯格子：可配置选习惯）

struct HabitEntity: AppEntity {
    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation { .init(title: "\(name)") }
    static let typeDisplayRepresentation: TypeDisplayRepresentation = .init(name: "习惯")

    struct HabitEntityQuery: EntityQuery {
        func suggestedEntities() async throws -> [HabitEntity] {
            SnapshotStore.load().habits.map { HabitEntity(id: $0.id, name: $0.name) }
        }

        func entities(for identifiers: [String]) async throws -> [HabitEntity] {
            let all = SnapshotStore.load().habits
            return identifiers.compactMap { id in
                all.first { $0.id == id }.map { HabitEntity(id: $0.id, name: $0.name) }
            }
        }
    }

    typealias DefaultQuery = HabitEntityQuery

    static var defaultQuery: HabitEntityQuery { HabitEntityQuery() }
}

struct SelectHabitIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "选择习惯"
    static let description = IntentDescription("选择要在格子里展示的习惯；不选则自动轮换")

    @Parameter(title: "习惯")
    var habit: HabitEntity?

    init() {}
    init(habit: HabitEntity?) { self.habit = habit }
}

struct HabitIntentEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let habitID: String?
}

struct QuiltIntentProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HabitIntentEntry {
        HabitIntentEntry(date: Date(), snapshot: SnapshotStore.load(), habitID: nil)
    }

    func snapshot(for configuration: SelectHabitIntent, in context: Context) async -> HabitIntentEntry {
        HabitIntentEntry(date: Date(), snapshot: SnapshotStore.load(),
                         habitID: configuration.habit?.id)
    }

    func timeline(for configuration: SelectHabitIntent, in context: Context) async -> Timeline<HabitIntentEntry> {
        let entry = HabitIntentEntry(date: Date(), snapshot: SnapshotStore.load(),
                                     habitID: configuration.habit?.id)
        return Timeline(entries: [entry], policy: .after(nextReloadDate()))
    }
}

// MARK: - 打卡 Intent（小组件按钮）

struct ToggleCheckIntent: AppIntent {
    static let title: LocalizedStringResource = "打卡"
    static let description = IntentDescription("记录一次打卡；勾选型习惯再次点击即取消今天。")

    @Parameter(title: "习惯 ID")
    var habitID: String

    init() {}
    init(habitID: String) { self.habitID = habitID }

    @MainActor
    func perform() async throws -> some IntentResult {
        // 扩展进程访问不了 App 的 Documents 数据库：按渲染期修正后的快照推新值
        // → 写回快照（habits + 今天的格子，跨天重算依赖格子）→ 排队给 App 落库
        // → 达标即静默今天剩余提醒
        var snapshot = SnapshotStore.load()
        var effective = snapshot.habitsForRender()
        guard let idx = effective.firstIndex(where: { $0.id == habitID }) else {
            return .result()
        }
        if effective[idx].isCounter {
            effective[idx].todayCount += 1
        } else {
            effective[idx].todayCount = effective[idx].todayCount > 0 ? 0 : 1
        }
        let newCount = effective[idx].todayCount
        let goal = max(effective[idx].goal, 1)

        if let rawIdx = snapshot.habits.firstIndex(where: { $0.id == habitID }) {
            snapshot.habits[rawIdx].todayCount = newCount
        }
        let todayStr = Fmt.dailyFormatter.string(from: Date())
        var cells = snapshot.grids[habitID] ?? []
        let ratio = min(Double(newCount) / Double(goal), 1)
        if let cIdx = cells.firstIndex(where: { $0.d == todayStr }) {
            cells[cIdx].r = ratio
            cells[cIdx].due = true
            cells[cIdx].f = false
        } else {
            cells.append(GridCellDTO(d: todayStr, r: ratio, due: true, f: false))
        }
        snapshot.grids[habitID] = cells
        snapshot.generatedAt = Date()
        SnapshotStore.save(snapshot)

        PendingCheckInQueue.append(.init(habitID: habitID, day: todayStr, count: newCount))
        if newCount >= goal {
            HabitNotifications.silenceToday(habitID: habitID)   // 达标：今天剩余提醒静默
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - 今日清单小组件

struct TodayListWidget: Widget {
    var body: some WidgetConfiguration {
        // 可配置：小尺寸可锁定某个习惯；想看多个就加多个小方块，每个选一个
        AppIntentConfiguration(kind: "QuiltTodayList",
                               intent: SelectHabitIntent.self,
                               provider: TodayIntentProvider()) { entry in
            TodayListEntryView(entry: entry)
        }
        .configurationDisplayName("今日习惯")
        .description("今天该做的事，点一下直接打卡；小尺寸可在编辑里选定习惯")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TodayListEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayIntentEntry

    private var effectiveHabits: [WidgetSnapshot.HabitInfo] { entry.snapshot.habitsForRender() }

    /// 小尺寸：配置选中的习惯；未配置 → 第一个「该做未完成」，否则第一个
    private var smallHabit: WidgetSnapshot.HabitInfo? {
        let all = effectiveHabits
        if let id = entry.habitID, let picked = all.first(where: { $0.id == id }) {
            return picked
        }
        return all.first { $0.dueToday && $0.todayCount < $0.goal } ?? all.first
    }

    private var habits: [WidgetSnapshot.HabitInfo] {
        let due = effectiveHabits.filter { $0.dueToday }
        let rest = effectiveHabits.filter { !$0.dueToday }
        let limit = family == .systemLarge ? 8 : 3
        return Array((due + rest).prefix(limit))
    }

    var body: some View {
        Group {
            if family == .systemSmall {
                smallLayout
            } else if habits.isEmpty {
                emptyView
            } else {
                listLayout
            }
        }
        .widgetURL(URL(string: "quilt://today"))
        .containerBackground(for: .widget) {
            Color(uiColor: .systemBackground)
        }
        .padding(2)
    }

    // MARK: 小尺寸：单习惯紧凑打卡

    private var smallLayout: some View {
        Group {
            if let habit = smallHabit {
                let color = Color(hex: UInt32(habit.colorHex))
                let done = habit.todayCount >= habit.goal
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: habit.symbol)
                            .font(.footnote)
                            .foregroundStyle(color)
                        Spacer()
                        StreakBadgeView(count: habit.streak)
                    }
                    Spacer(minLength: 0)
                    Text(habit.name)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(progressText(habit))
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(done ? color : .secondary)
                        Spacer(minLength: 4)
                        Button(intent: ToggleCheckIntent(habitID: habit.id)) {
                            ZStack {
                                Circle()
                                    .fill(done ? color : Color.primary.opacity(0.08))
                                    .frame(width: 34, height: 34)
                                Image(systemName: done ? "checkmark" : "plus")
                                    .font(.footnote.bold())
                                    .foregroundStyle(done ? .white : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(done ? "\(habit.name)取消打卡" : "\(habit.name)打卡")
                    }
                }
            } else {
                emptyView
            }
        }
    }

    /// 小尺寸角标进度文案（弹性显示周进度，其余显示今日进度）
    private func progressText(_ habit: WidgetSnapshot.HabitInfo) -> String {
        habit.flexible
            ? "\(habit.weeklyDone)/\(habit.weeklyGoal)"
            : (habit.todayCount >= habit.goal ? "✓" : "\(habit.todayCount)/\(habit.goal)")
    }

    private var emptyView: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.grid.3x3.topleft.filled")
                .font(.title3)
                .foregroundStyle(Color.brand)
            Text("还没有习惯")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: 中 / 大：清单

    private var listLayout: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("今天")
                    .font(.headline)
                Spacer()
                Text("\(habits.filter { $0.todayCount >= $0.goal }.count)/\(habits.filter { $0.dueToday }.count)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ForEach(habits, id: \.id) { habit in
                row(habit)
            }
            if family == .systemLarge { Spacer(minLength: 0) }
        }
    }

    private func row(_ habit: WidgetSnapshot.HabitInfo) -> some View {
        let done = habit.todayCount >= habit.goal
        return HStack(spacing: 8) {
            Image(systemName: habit.symbol)
                .font(.caption)
                .foregroundStyle(Color(hex: UInt32(habit.colorHex)))
                .frame(width: 20)
            Text(habit.name)
                .font(.subheadline)
                .lineLimit(1)
            if habit.flexible {
                Text("\(habit.weeklyDone)/\(habit.weeklyGoal)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(habit.weeklyDone >= habit.weeklyGoal ? Color.brand : .secondary)
            }
            Spacer(minLength: 4)
            StreakBadgeView(count: habit.streak)
            Button(intent: ToggleCheckIntent(habitID: habit.id)) {
                ZStack {
                    Circle()
                        .fill(done ? Color(hex: UInt32(habit.colorHex)) : Color.primary.opacity(0.08))
                        .frame(width: 27, height: 27)
                    Image(systemName: done ? "checkmark" : "plus")
                        .font(.caption.bold())
                        .foregroundStyle(done ? .white : .secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? "\(habit.name)取消打卡" : "\(habit.name)打卡")
        }
    }
}

// MARK: - 单习惯格子小组件（长按可换习惯）

struct HabitGridWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "QuiltHabitGrid",
                               intent: SelectHabitIntent.self,
                               provider: QuiltIntentProvider()) { entry in
            HabitGridEntryView(entry: entry)
        }
        .configurationDisplayName("习惯格子")
        .description("近 26 周格子 + 快捷打卡；长按可换习惯")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct HabitGridEntryView: View {
    let entry: HabitIntentEntry

    private var effectiveHabits: [WidgetSnapshot.HabitInfo] { entry.snapshot.habitsForRender() }

    /// 配置选中的习惯；未配置 → 第一个「该做未完成」，否则第一个
    private var habit: WidgetSnapshot.HabitInfo? {
        let all = effectiveHabits
        if let id = entry.habitID, let picked = all.first(where: { $0.id == id }) {
            return picked
        }
        return all.first { $0.dueToday && $0.todayCount < $0.goal } ?? all.first
    }

    var body: some View {
        Group {
            if let habit {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Image(systemName: habit.symbol)
                            .font(.subheadline)
                            .foregroundStyle(Color(hex: UInt32(habit.colorHex)))
                        Text(habit.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if habit.flexible {
                            Text("本周 \(habit.weeklyDone)/\(habit.weeklyGoal)")
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        StreakBadgeView(count: habit.streak)
                        Button(intent: ToggleCheckIntent(habitID: habit.id)) {
                            Image(systemName: habit.todayCount >= habit.goal ? "checkmark.circle.fill" : "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Color(hex: UInt32(habit.colorHex)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(habit.todayCount >= habit.goal ? "\(habit.name)取消打卡" : "\(habit.name)打卡")
                    }
                    WidgetGrid(colorHex: habit.colorHex, cells: entry.snapshot.grids[habit.id] ?? [])
                    Spacer(minLength: 0)
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "square.grid.3x3.topleft.filled")
                        .font(.title3)
                        .foregroundStyle(Color.brand)
                    Text("还没有习惯")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .widgetURL(URL(string: "quilt://today"))
        .containerBackground(for: .widget) {
            Color(uiColor: .systemBackground)
        }
        .padding(2)
    }
}

// MARK: - 小组件内的格子

struct WidgetGrid: View {
    let colorHex: Int
    let cells: [GridCellDTO]

    var body: some View {
        let columns = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
        HStack(alignment: .top, spacing: 2) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                VStack(spacing: 2) {
                    ForEach(Array(column.enumerated()), id: \.element.d) { _, cell in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Self.fill(cell: cell, color: Color(hex: UInt32(colorHex))))
                            .frame(maxHeight: .infinity)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
    }

    static func fill(cell: GridCellDTO, color: Color) -> Color {
        if cell.f { return .primary.opacity(0.03) }
        if !cell.due { return .primary.opacity(0.07) }
        if cell.r >= 1 { return color }
        if cell.r > 0 { return color.opacity(0.3 + 0.5 * cell.r) }
        return .primary.opacity(0.1)
    }
}

struct StreakBadgeView: View {
    let count: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "flame.fill")
                .font(.caption2)
            Text("\(count)")
                .font(.caption2.weight(.bold).monospacedDigit())
        }
        .foregroundStyle(count > 0 ? Color.flame : .secondary)
    }
}

// MARK: - 今日进度小组件（中/大）：完成度环 + 逐习惯进度 + 一键打卡

struct ProgressEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct ProgressProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProgressEntry {
        ProgressEntry(date: Date(), snapshot: SnapshotStore.load())
    }

    func getSnapshot(in context: Context, completion: @escaping (ProgressEntry) -> Void) {
        completion(ProgressEntry(date: Date(), snapshot: SnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProgressEntry>) -> Void) {
        let entry = ProgressEntry(date: Date(), snapshot: SnapshotStore.load())
        completion(Timeline(entries: [entry], policy: .after(nextReloadDate())))
    }
}

/// 出现在进度组件里的习惯：硬性应做的 + 弹性的（弹性显示周进度）
private func progressHabits(in snapshot: WidgetSnapshot) -> [WidgetSnapshot.HabitInfo] {
    snapshot.habitsForRender().filter { $0.dueToday || $0.flexible }
}

private func progressDone(_ h: WidgetSnapshot.HabitInfo) -> Bool {
    h.flexible ? h.weeklyDone >= h.weeklyGoal : h.todayCount >= h.goal
}

private func progressText(_ h: WidgetSnapshot.HabitInfo) -> String {
    if h.flexible { return "\(h.weeklyDone)/\(h.weeklyGoal)" }
    return h.todayCount >= h.goal ? "✓" : "\(h.todayCount)/\(h.goal)"
}

struct TodayProgressWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuiltTodayProgress", provider: ProgressProvider()) { entry in
            ProgressEntryView(entry: entry)
        }
        .configurationDisplayName("今日进度")
        .description("完成度环 + 逐习惯进度，一键打卡")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct ProgressEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ProgressEntry

    private var due: [WidgetSnapshot.HabitInfo] { progressHabits(in: entry.snapshot) }
    private var doneCount: Int { due.filter { progressDone($0) }.count }

    private var rows: [WidgetSnapshot.HabitInfo] {
        Array(due.prefix(family == .systemLarge ? 8 : 4))
    }

    var body: some View {
        Group {
            if due.isEmpty {
                emptyView
            } else if family == .systemMedium {
                HStack(spacing: 12) {
                    ProgressRing(value: doneCount, total: due.count, size: 74)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("今日进度")
                            .font(.headline)
                        ForEach(rows, id: \.id) { habit in
                            progressRow(habit, compact: true)
                        }
                        Spacer(minLength: 0)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("今日进度").font(.headline)
                        Spacer()
                        Text("\(doneCount)/\(due.count)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(doneCount == due.count ? Color.brand : .secondary)
                    }
                    HStack(spacing: 16) {
                        ProgressRing(value: doneCount, total: due.count, size: 96)
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(rows.prefix(4), id: \.id) { progressRow($0, compact: false) }
                        }
                    }
                    ForEach(rows.dropFirst(4), id: \.id) { progressRow($0, compact: false) }
                    Spacer(minLength: 0)
                }
            }
        }
        .widgetURL(URL(string: "quilt://today"))
        .containerBackground(for: .widget) {
            Color(uiColor: .systemBackground)
        }
        .padding(2)
    }

    private func progressRow(_ habit: WidgetSnapshot.HabitInfo, compact: Bool) -> some View {
        let done = progressDone(habit)
        let color = Color(hex: UInt32(habit.colorHex))
        return HStack(spacing: 6) {
            Image(systemName: habit.symbol)
                .font(.caption2)
                .foregroundStyle(color)
                .frame(width: 16)
            Text(habit.name)
                .font(compact ? .caption2 : .caption)
                .lineLimit(1)
            if habit.flexible {
                Text(progressText(habit))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(progressText(habit))
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(done ? color : .secondary)
            Button(intent: ToggleCheckIntent(habitID: habit.id)) {
                ZStack {
                    Circle()
                        .fill(done ? color : Color.primary.opacity(0.08))
                        .frame(width: 26, height: 26)
                    Image(systemName: done ? "checkmark" : "plus")
                        .font(.caption2.bold())
                        .foregroundStyle(done ? .white : .secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? "\(habit.name)取消打卡" : "\(habit.name)打卡")
        }
    }

    private var emptyView: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.pie")
                .font(.title3)
                .foregroundStyle(Color.brand)
            Text("还没有习惯")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 习惯连击小组件（小）：大字连击 + 快捷打卡，可长按选习惯

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "QuiltStreak",
                               intent: SelectHabitIntent.self,
                               provider: QuiltIntentProvider()) { entry in
            StreakEntryView(entry: entry)
        }
        .configurationDisplayName("习惯连击")
        .description("当前连续天数，大字显示 + 快捷打卡")
        .supportedFamilies([.systemSmall])
    }
}

struct StreakEntryView: View {
    let entry: HabitIntentEntry

    /// 配置选中的习惯；未配置 → 连击最高的
    private var habit: WidgetSnapshot.HabitInfo? {
        let all = entry.snapshot.habitsForRender()
        if let id = entry.habitID, let picked = all.first(where: { $0.id == id }) {
            return picked
        }
        return all.max { $0.streak < $1.streak }
    }

    var body: some View {
        Group {
            if let habit {
                let color = Color(hex: UInt32(habit.colorHex))
                let done = habit.todayCount >= habit.goal
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .font(.title3)
                            .foregroundStyle(Color.flame)
                        Text("\(habit.streak)")
                            .font(.system(size: 40, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.flame)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Spacer(minLength: 4)
                        Button(intent: ToggleCheckIntent(habitID: habit.id)) {
                            ZStack {
                                Circle()
                                    .fill(done ? color : Color.primary.opacity(0.08))
                                    .frame(width: 34, height: 34)
                                Image(systemName: done ? "checkmark" : "plus")
                                    .font(.footnote.bold())
                                    .foregroundStyle(done ? .white : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(done ? "\(habit.name)取消打卡" : "\(habit.name)打卡")
                    }
                    Spacer(minLength: 0)
                    Text(habit.name)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    Text("连续 \(habit.streak) 天")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.title3)
                        .foregroundStyle(Color.flame)
                    Text("还没有习惯")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .widgetURL(URL(string: "quilt://today"))
        .containerBackground(for: .widget) {
            Color(uiColor: .systemBackground)
        }
        .padding(2)
    }
}
