import SwiftUI

// MARK: - 新建 / 编辑习惯

struct EditHabitView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: Store
    let habit: Habit?   // nil = 新建

    @State private var name = ""
    @State private var symbol = "checkmark.circle"
    @State private var colorHex = Color.habitPalette[0]
    @State private var isCounter = false
    @State private var dailyGoal = 8
    @State private var repeatMode = 0   // 0 = 每天 · 1 = 自定义星期几 · 2 = 每周 N 次
    @State private var selectedWeekdays: Set<Int> = []
    @State private var timesPerWeek = 3
    @State private var reminderOn = false
    @State private var reminderStyle = 0   // 0 = 固定时间 · 1 = 分次提醒（计数型）
    @State private var reminderTime = Date()
    @State private var pacedStartMinute = HabitMath.pacedDefaultStartMinute
    @State private var pacedEndMinute = 21 * 60

    static let symbols = [
        "checkmark.circle", "figure.run", "figure.walk", "dumbbell.fill",
        "book.closed", "pencil", "keyboard", "brain.head.profile",
        "drop", "water.waves", "moon.zzz", "sun.max",
        "cup.and.saucer", "carrot", "pill", "leaf",
        "music.note", "camera", "film", "gamecontroller",
        "star", "heart", "banknote", "cart",
    ]

    /// 周一为首的展示顺序（Calendar weekday: 1=周日…7=周六）
    private let displayWeekdays = [2, 3, 4, 5, 6, 7, 1]

    /// 周几胶囊的无障碍标签：系统本地化短符号（zh=周一…，en=Mon…）
    private func weekdayA11y(_ weekday: Int) -> String {
        Calendar.current.shortWeekdaySymbols[weekday - 1]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("叫什么 · 长什么样") {
                    TextField("习惯名，如：阅读", text: $name)
                    symbolGrid
                    colorRow
                }
                Section {
                    Picker("打卡方式", selection: $isCounter) {
                        Text("每日勾选").tag(false)
                        Text("每日计数").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if isCounter {
                        Stepper("目标：每天 \(dailyGoal) 次", value: $dailyGoal, in: 2...99)
                    }
                } header: {
                    Text("打卡方式")
                } footer: {
                    Text(isCounter ? "适合喝水、背单词这类一天多次的事" : "适合锻炼、阅读这类一天一次的事")
                }
                Section {
                    Picker("重复", selection: $repeatMode) {
                        Text("每天").tag(0)
                        Text("自定义").tag(1)
                        Text("每周 N 次").tag(2)
                    }
                    .pickerStyle(.segmented)
                    if repeatMode == 1 {
                        weekdayRow
                    }
                    if repeatMode == 2 {
                        Stepper("目标：每周 \(timesPerWeek) 次", value: $timesPerWeek, in: 1...7)
                    }
                } header: {
                    Text("重复")
                } footer: {
                    Text(repeatMode == 2
                         ? "哪天做随意，一周攒够次数就算不断链；不计入今天页的进度环"
                         : "不该做的日子不进格子，也不会断链")
                }
                Section {
                    Toggle("每天提醒", isOn: $reminderOn)
                } header: {
                    Text("提醒")
                }
                if reminderOn {
                    Section {
                        if isCounter {
                            Picker("提醒方式", selection: $reminderStyle) {
                                Text("固定时间").tag(0)
                                Text("分次提醒").tag(1)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: reminderStyle) { _, new in
                                // 切到分次提醒时给默认窗口 08:00–21:00
                                if new == 1 {
                                    pacedStartMinute = HabitMath.pacedDefaultStartMinute
                                    pacedEndMinute = 21 * 60
                                }
                            }
                        }
                        if isCounter, reminderStyle == 1 {
                            TimeRangeRing(startMinute: $pacedStartMinute,
                                          endMinute: $pacedEndMinute)
                                .frame(maxWidth: .infinity)
                            Text("每天在所选时段的段首提醒，最多 6 次")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            DatePicker("提醒时间", selection: $reminderTime,
                                       displayedComponents: .hourAndMinute)
                        }
                    } footer: {
                        if isCounter, reminderStyle == 1 {
                            Text("在所选时间段内均分剩余次数；达标后当天静默")
                        }
                    }
                }
            }
            .navigationTitle(habit == nil ? "新习惯" : "编辑习惯")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: 图标 & 颜色

    private var symbolGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: DS.gapSmall) {
            ForEach(Self.symbols, id: \.self) { s in
                Button {
                    symbol = s
                } label: {
                    Image(systemName: s)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(symbol == s ? .white : Color.habitColor(colorHex))
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: DS.radiusSmall)
                                .fill(symbol == s ? Color.habitColor(colorHex) : Color.primary.opacity(0.05))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(s)
            }
        }
        .padding(.vertical, 4)
    }

    /// 习惯八色板中文名（无障碍标签用，key 走本地化目录）
    static let colorNames: [String.LocalizationValue] = ["苔绿", "蓝", "橘", "红", "紫", "青", "粉", "黄"]

    private var colorRow: some View {
        HStack(spacing: DS.gapSmall) {
            ForEach(Array(Color.habitPalette.enumerated()), id: \.element) { idx, hex in
                Button {
                    colorHex = hex
                } label: {
                    Circle()
                        .fill(Color.habitColor(hex))
                        .frame(width: 30, height: 30)
                        .overlay {
                            if colorHex == hex {
                                Circle().strokeBorder(.white, lineWidth: 2.5)
                                    .shadow(radius: 1.5)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: Self.colorNames[idx]))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var weekdayRow: some View {
        HStack(spacing: DS.gapSmall) {
            ForEach(displayWeekdays, id: \.self) { wd in
                let on = selectedWeekdays.contains(wd)
                Button {
                    if on { selectedWeekdays.remove(wd) } else { selectedWeekdays.insert(wd) }
                } label: {
                    Text(Calendar.current.veryShortWeekdaySymbols[wd - 1])
                        .font(.caption.weight(.bold))
                        .foregroundStyle(on ? .white : .secondary)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle().fill(on ? Color.brand : Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(weekdayA11y(wd))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 保存

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        let mask: Int
        let scheduleKind: Int
        switch repeatMode {
        case 2:
            mask = HabitMath.allWeekdayMask
            scheduleKind = 1
        case 1:
            mask = maskFromSelection()
            scheduleKind = 0
        default:
            mask = HabitMath.allWeekdayMask
            scheduleKind = 0
        }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        let reminderMinute: Int? = reminderOn ? (comps.hour! * 60 + comps.minute!) : nil

        if let habit {
            habit.name = cleanName
            habit.symbol = symbol
            habit.colorHex = colorHex
            habit.isCounter = isCounter
            habit.dailyGoal = dailyGoal
            habit.weekdayMask = mask
            habit.scheduleKind = scheduleKind
            habit.timesPerWeek = timesPerWeek
            habit.reminderMinute = isCounter && reminderStyle == 1 ? pacedEndMinute : reminderMinute
            habit.reminderStyle = isCounter ? reminderStyle : 0
            habit.reminderStartMinute = isCounter && reminderStyle == 1 ? pacedStartMinute : HabitMath.pacedDefaultStartMinute
            store.updateHabit(habit)
        } else {
            let new = Habit(name: cleanName,
                            symbol: symbol,
                            colorHex: colorHex,
                            isCounter: isCounter,
                            dailyGoal: dailyGoal,
                            weekdayMask: mask,
                            scheduleKind: scheduleKind,
                            timesPerWeek: timesPerWeek,
                            reminderMinute: isCounter && reminderStyle == 1 ? pacedEndMinute : reminderMinute,
                            reminderStyle: isCounter ? reminderStyle : 0,
                            reminderStartMinute: isCounter && reminderStyle == 1 ? pacedStartMinute : HabitMath.pacedDefaultStartMinute,
                            sortOrder: store.habits.count)
            store.addHabit(new)
        }
        if reminderOn {
            HabitNotifications.requestAuth()
        }
        HabitNotifications.syncAll(store: store)
        dismiss()
    }

    private func maskFromSelection() -> Int {
        selectedWeekdays.reduce(0) { $0 | (1 << ($1 - 1)) }
    }

    // MARK: 初始化状态

    init(store: Store, habit: Habit?) {
        self.store = store
        self.habit = habit
        if let habit {
            _name = State(initialValue: habit.name)
            _symbol = State(initialValue: habit.symbol)
            _colorHex = State(initialValue: habit.colorHex)
            _isCounter = State(initialValue: habit.isCounter)
            _dailyGoal = State(initialValue: habit.goal)
            if habit.isFlexible {
                _repeatMode = State(initialValue: 2)
                _timesPerWeek = State(initialValue: habit.timesPerWeek)
                _selectedWeekdays = State(initialValue: [])
            } else {
                _repeatMode = State(initialValue: habit.weekdayMask == HabitMath.allWeekdayMask ? 0 : 1)
                _timesPerWeek = State(initialValue: habit.timesPerWeek)
                _selectedWeekdays = State(initialValue: {
                    var set: Set<Int> = []
                    for wd in 1...7 where habit.weekdayMask & (1 << (wd - 1)) != 0 {
                        set.insert(wd)
                    }
                    return set
                }())
            }
            _reminderOn = State(initialValue: habit.reminderMinute != nil)
            _reminderStyle = State(initialValue: habit.reminderStyle)
            if habit.reminderStyle == 1, let end = habit.reminderMinute {
                _pacedStartMinute = State(initialValue: habit.reminderStartMinute)
                _pacedEndMinute = State(initialValue: end)
            }
            _pacedStartMinute = State(initialValue: habit.reminderStartMinute)
            _pacedEndMinute = State(initialValue: habit.reminderMinute ?? 21 * 60)
            _reminderTime = State(initialValue: {
                guard let minute = habit.reminderMinute else { return Date() }
                var comps = DateComponents()
                comps.hour = minute / 60
                comps.minute = minute % 60
                return Calendar.current.date(from: comps) ?? Date()
            }())
        } else {
            let nextColor = Color.habitPalette[store.habits.count % Color.habitPalette.count]
            _colorHex = State(initialValue: nextColor)
        }
    }
}
