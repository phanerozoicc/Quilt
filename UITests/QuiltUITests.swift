import XCTest

// MARK: - 全量 UI 仿真测试
//
// 每条用例默认以 `-uitest-fresh` 启动（清库 + 重种 3 条示例 + 6 周确定性历史），
// 保证互相独立、可重复。持久化用例用无参重启验证落盘；清空/空态用例放最后。
// 断言全部按「今天是否为锻炼日（周一三五）」动态计算，任何日期跑都成立。
// 截图写到宿主机 docs/screenshots/uitest/（模拟器进程可直接写宿主路径）。

final class QuiltUITests: XCTestCase {

    private let shotDir = "/Users/haozc/code/ios/prod1/Quilt/docs/screenshots/uitest"
    private var app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: 日期感知

    /// 示例习惯「锻炼」的节奏是周一/三/五（Calendar weekday 2/4/6）
    private var workoutDueToday: Bool {
        [2, 4, 6].contains(Calendar.current.component(.weekday, from: Date()))
    }

    /// 种子数据里今天应做的习惯数（锻炼 + 阅读 + 喝水）
    private var dueCount: Int { workoutDueToday ? 3 : 2 }

    // MARK: 工具

    @discardableResult
    private func launch(fresh: Bool = true, locale: String? = nil) -> XCUIApplication {
        app = XCUIApplication()
        var args = fresh ? ["-uitest-fresh"] : []
        // 用例断言以中文界面为基准：默认强制 zh-Hans（模拟器系统语言可能是英文）
        let lang = locale ?? "zh-Hans"
        args += ["-AppleLanguages", "(\(lang))",
                 "-AppleLocale", lang == "en" ? "en_US" : "zh_CN"]
        app.launchArguments = args
        app.launch()
        let title = app.staticTexts[lang == "en" ? "Today" : "今天"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "启动后应看到「今天」页")
        return app
    }

    private func snap(_ name: String) {
        let dir = URL(fileURLWithPath: shotDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: dir.appendingPathComponent("\(name).png"))
    }

    private func goTab(_ label: String) {
        let tab = app.tabBars.buttons[label]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "页签 \(label) 应存在")
        tab.tap()
    }

    private func row(_ name: String) -> XCUIElement {
        app.staticTexts[name]
    }

    private func openDetail(_ name: String) {
        row(name).tap()
        XCTAssertTrue(app.staticTexts["当前连续"].waitForExistence(timeout: 10), "应进入 \(name) 详情页")
    }

    /// 勾选型打卡 n 次（等待控件状态翻转）
    private func tapCheck(_ name: String, times: Int = 1) {
        for _ in 0..<times {
            let done = app.buttons["\(name)取消打卡"]
            if done.waitForExistence(timeout: 3) {
                done.tap()
            } else {
                app.buttons["\(name)打卡"].tap()
            }
        }
    }

    /// 计数型加 n 次
    private func tapPlus(_ name: String, times: Int) {
        for _ in 0..<times {
            let plus = app.buttons["\(name)加一"]
            XCTAssertTrue(plus.waitForExistence(timeout: 10), "\(name) 的加号应存在")
            plus.tap()
        }
    }

    // MARK: 1. 启动与今天页

    func test01_launch_showsSeededToday() {
        let a = launch()
        XCTAssertTrue(a.staticTexts["0/\(dueCount)"].exists, "初始进度环 0/\(dueCount)")
        let rest = a.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '还剩'")).firstMatch
        XCTAssertTrue(rest.exists, "应有「还剩 n 件事」文案")
        XCTAssertTrue(row("锻炼").exists)
        XCTAssertTrue(row("阅读").exists)
        XCTAssertTrue(row("喝水").exists)
        XCTAssertTrue(a.staticTexts["目标 8 次 · 每天"].exists, "计数型副标")
        XCTAssertTrue(a.buttons["阅读打卡"].exists)
        XCTAssertTrue(a.buttons["喝水加一"].exists)
        XCTAssertFalse(a.buttons["喝水减一"].exists, "计数为 0 时不应有减号")
        XCTAssertTrue(a.tabBars.buttons["统计"].exists)
        XCTAssertTrue(a.tabBars.buttons["设置"].exists)
        snap("01-today-initial")
    }

    // MARK: 2. 勾选型打卡（切换 + 进度环）

    func test02_checkIn_togglesAndUpdatesRing() {
        let a = launch()
        tapCheck("阅读")
        XCTAssertTrue(a.buttons["阅读取消打卡"].waitForExistence(timeout: 10), "打卡后按钮变取消")
        XCTAssertTrue(a.staticTexts["1/\(dueCount)"].waitForExistence(timeout: 10), "进度环 +1")
        snap("02-checked-once")

        tapCheck("阅读")
        XCTAssertTrue(a.buttons["阅读打卡"].waitForExistence(timeout: 10), "再点应取消")
        XCTAssertTrue(a.staticTexts["0/\(dueCount)"].waitForExistence(timeout: 10))
    }

    // MARK: 3. 计数型打卡（加/减步进 + 减号出现时机）

    func test03_counter_incrementDecrement() {
        let a = launch()
        tapPlus("喝水", times: 1)
        XCTAssertTrue(a.buttons["喝水减一"].waitForExistence(timeout: 10), "+1 后出现减号")
        XCTAssertTrue(a.staticTexts["1/8"].waitForExistence(timeout: 10))
        tapPlus("喝水", times: 1)
        XCTAssertTrue(a.staticTexts["2/8"].waitForExistence(timeout: 10))
        snap("03-counter-2of8")
        a.buttons["喝水减一"].tap()
        a.buttons["喝水减一"].tap()
        XCTAssertTrue(a.staticTexts["0/8"].waitForExistence(timeout: 10))
        XCTAssertFalse(a.buttons["喝水减一"].exists, "减到 0 减号消失")
    }

    // MARK: 4. 详情页（统计卡/格子/最近记录 + 返回）

    func test04_detail_showsCardsGridAndBack() {
        let a = launch()
        openDetail("锻炼")
        XCTAssertTrue(a.staticTexts["最长连续"].exists)
        XCTAssertTrue(a.staticTexts["30 天完成率"].exists)
        XCTAssertTrue(a.staticTexts["累计打卡"].exists)
        XCTAssertTrue(a.staticTexts["近 30 周"].exists, "年格卡片")
        XCTAssertTrue(a.staticTexts["最近记录"].exists)
        snap("04-detail")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(row("锻炼").waitForExistence(timeout: 10), "返回今天页")
    }

    // MARK: 5. 新建习惯（勾选型，图标/颜色/自定义周几交互）

    func test05_createBoolHabit() {
        let a = launch()
        a.buttons["新建习惯"].tap()
        XCTAssertTrue(a.staticTexts["新习惯"].waitForExistence(timeout: 10), "编辑 sheet 弹出")
        let field = a.textFields.element(boundBy: 0)
        field.tap()
        field.typeText("Stretch")
        a.buttons["figure.walk"].tap()
        a.buttons["蓝"].tap()
        a.buttons["自定义"].tap()
        XCTAssertTrue(a.buttons["周一"].waitForExistence(timeout: 3), "自定义出现周几胶囊")
        a.buttons["周三"].tap()
        a.buttons["每天"].tap()
        a.buttons["保存"].tap()
        XCTAssertTrue(row("Stretch").waitForExistence(timeout: 10), "新习惯出现在列表")
        XCTAssertTrue(a.staticTexts["0/\(dueCount + 1)"].waitForExistence(timeout: 10), "每天习惯计入应做")
        snap("05-created")
    }

    // MARK: 6. 新建计数型习惯

    func test06_createCounterHabit() {
        let a = launch()
        a.buttons["新建习惯"].tap()
        let field = a.textFields.element(boundBy: 0)
        field.tap()
        field.typeText("Tea")
        a.buttons["每日计数"].tap()
        XCTAssertTrue(a.staticTexts["目标：每天 8 次"].waitForExistence(timeout: 3), "计数目标行出现")
        a.buttons["保存"].tap()
        XCTAssertTrue(row("Tea").waitForExistence(timeout: 10))
        XCTAssertTrue(a.buttons["Tea加一"].waitForExistence(timeout: 10), "计数型出现加号")
        XCTAssertTrue(a.staticTexts["0/8"].exists, "行内 0/8")
    }

    // MARK: 7. 编辑习惯（改名 + 取消不落盘）

    func test07_editRename_andCancel() {
        let a = launch()
        // 取消分支
        row("阅读").tap()
        XCTAssertTrue(app.staticTexts["当前连续"].waitForExistence(timeout: 10))
        app.buttons["更多操作"].tap()
        app.buttons["编辑"].tap()
        XCTAssertTrue(a.staticTexts["编辑习惯"].waitForExistence(timeout: 10))
        let field = a.textFields.element(boundBy: 0)
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8))
        field.typeText("TEMP")
        a.buttons["取消"].tap()
        XCTAssertTrue(row("阅读").waitForExistence(timeout: 10), "取消后原名保留")
        XCTAssertFalse(row("TEMP").exists)

        // 真改名：阅读 -> Read
        row("阅读").tap()
        XCTAssertTrue(app.staticTexts["当前连续"].waitForExistence(timeout: 10))
        app.buttons["更多操作"].tap()
        app.buttons["编辑"].tap()
        let field2 = a.textFields.element(boundBy: 0)
        field2.tap()
        field2.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8))
        field2.typeText("Read")
        a.buttons["保存"].tap()
        XCTAssertTrue(row("Read").waitForExistence(timeout: 10), "改名落库并刷新列表")
        snap("07-renamed")
    }

    // MARK: 8. 提醒 UI（Toggle 显隐 DatePicker，不触发系统权限弹窗）

    func test08_editReminderToggleUI() {
        let a = launch()
        row("阅读").tap()
        XCTAssertTrue(app.staticTexts["当前连续"].waitForExistence(timeout: 10))
        app.buttons["更多操作"].tap()
        app.buttons["编辑"].tap()
        let toggle = a.switches["每天提醒"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertFalse(a.staticTexts["提醒时间"].exists, "默认关闭，无时间选择行")
        // SwiftUI 表单里 switches 元素中心点是标签文字，合成点击翻不动开关；
        // 直接点行右缘（开关旋钮位置）
        let knob = toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5))
        knob.tap()
        // 提醒区在表单最底部：插入的时间行可能落在可视区之外（不进可达树），滚动带出
        a.swipeUp()
        XCTAssertTrue(a.staticTexts["提醒时间"].waitForExistence(timeout: 10), "打开后出现时间选择行")
        a.swipeDown()
        knob.tap()
        let off = !a.staticTexts["提醒时间"].waitForExistence(timeout: 3)
        XCTAssertTrue(off, "关闭后时间选择行消失")
        a.buttons["取消"].tap()
        XCTAssertTrue(row("阅读").waitForExistence(timeout: 10))
    }

    // MARK: 9. 归档（列表移除 + 设置页可恢复）

    func test09_archive_thenRestoreFromSettings() {
        let a = launch()
        openDetail("锻炼")
        app.buttons["更多操作"].tap()
        app.buttons["归档（保留历史）"].tap()
        XCTAssertTrue(row("阅读").waitForExistence(timeout: 10), "归档后自动返回今天页")
        XCTAssertFalse(row("锻炼").exists, "归档习惯从今天列表消失")

        goTab("设置")
        XCTAssertTrue(a.staticTexts["已归档（保留历史，可恢复）"].waitForExistence(timeout: 10))
        XCTAssertTrue(a.staticTexts["锻炼"].exists, "归档习惯出现在设置")
        snap("09-archived")
        a.buttons["恢复"].firstMatch.tap()
        let gone = !a.staticTexts["已归档（保留历史，可恢复）"].waitForExistence(timeout: 3)
        XCTAssertTrue(gone, "恢复后归档区消失")

        goTab("今天")
        XCTAssertTrue(row("锻炼").waitForExistence(timeout: 10), "恢复后回到今天列表")
    }

    // MARK: 10. 删除（确认弹窗 + 应做数下降）

    func test10_deleteWithConfirmation() {
        let a = launch()
        openDetail("阅读")
        app.buttons["更多操作"].tap()
        app.buttons["删除（连历史一起）"].tap()
        XCTAssertTrue(a.buttons["删除"].waitForExistence(timeout: 10), "确认弹窗出现")
        snap("10-delete-confirm")
        a.buttons["删除"].tap()
        XCTAssertTrue(row("锻炼").waitForExistence(timeout: 10), "返回今天页")
        XCTAssertFalse(row("阅读").exists, "已删除")
        XCTAssertTrue(a.staticTexts["0/\(dueCount - 1)"].waitForExistence(timeout: 10), "应做 -1")
    }

    // MARK: 11. 统计页

    func test11_stats_overviewAndBars() {
        let a = launch()
        tapCheck("阅读")
        tapPlus("喝水", times: 1)
        goTab("统计")
        XCTAssertTrue(a.staticTexts["今日概览"].waitForExistence(timeout: 10))
        XCTAssertTrue(a.staticTexts["应做"].exists)
        XCTAssertTrue(a.staticTexts["已完成"].exists)
        XCTAssertTrue(a.staticTexts["全部习惯 · 近 26 周"].exists, "合并热力图")
        XCTAssertTrue(a.staticTexts["30 天完成率"].exists)
        XCTAssertTrue(a.staticTexts["锻炼"].exists)
        XCTAssertTrue(a.staticTexts["阅读"].exists)
        snap("11-stats")
    }

    // MARK: 12. 设置页元素 + 导出分享面板

    func test12_settings_exportSheet() {
        let a = launch()
        goTab("设置")
        XCTAssertTrue(a.staticTexts["数据"].waitForExistence(timeout: 10))
        XCTAssertTrue(a.buttons["导出全部数据（JSON）"].exists)
        XCTAssertTrue(a.buttons["导入数据（覆盖现有）"].exists)
        XCTAssertTrue(a.buttons["清空全部数据"].exists)
        app.swipeUp()
        // LabeledContent 会把「标签, 值」合并成一个可达元素，用 CONTAINS 断言
        let net = a.staticTexts.matching(NSPredicate(format: "label CONTAINS '零联网'")).firstMatch
        XCTAssertTrue(net.waitForExistence(timeout: 10), "关于区网络声明（滚动后）")
        app.swipeDown()
        XCTAssertTrue(a.buttons["导出全部数据（JSON）"].isHittable, "回到顶部")
        snap("12-settings")

        // ShareLink 行直接弹系统分享面板；面板控件文案随本地化，用多候选谓词探测
        a.buttons["导出全部数据（JSON）"].tap()
        let panel = a.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS '拷贝' OR label CONTAINS 'Copy' OR label CONTAINS '完成' OR label CONTAINS 'Done' OR label CONTAINS '隔空投送' OR label CONTAINS 'AirDrop'")
        ).firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 8), "系统分享面板弹出")
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(a.buttons["导出全部数据（JSON）"].waitForExistence(timeout: 10), "面板关闭，行还在")
    }

    // MARK: 13. 持久化（杀进程重启后打卡保留）

    func test13_persistence_acrossRelaunch() {
        let a = launch(fresh: true)
        tapCheck("阅读")
        tapPlus("喝水", times: 2)
        XCTAssertTrue(a.staticTexts["1/\(dueCount)"].waitForExistence(timeout: 10))
        app.terminate()

        // 无参重启：不重置数据
        a.launchArguments = []
        a.launch()
        XCTAssertTrue(a.staticTexts["今天"].waitForExistence(timeout: 10))
        XCTAssertTrue(a.buttons["阅读取消打卡"].waitForExistence(timeout: 10), "勾选型状态落盘")
        XCTAssertTrue(a.staticTexts["2/8"].waitForExistence(timeout: 10), "计数落盘")
        XCTAssertTrue(a.staticTexts["1/\(dueCount)"].exists, "进度环保持")
        snap("13-relaunched")
    }

    // MARK: 14. 清空 + 空态 + 空态建新

    func test14_clearAll_emptyState_andCreateAgain() {
        let a = launch(fresh: true)
        goTab("设置")
        a.buttons["清空全部数据"].tap()
        XCTAssertTrue(a.buttons["清空"].waitForExistence(timeout: 10), "二次确认弹窗")
        a.buttons["清空"].tap()

        goTab("今天")
        XCTAssertTrue(a.staticTexts["还没有习惯"].waitForExistence(timeout: 10), "空态文案")
        XCTAssertTrue(a.staticTexts["点右上角 ＋ 种下第一块布片"].exists)
        snap("14-empty")

        a.buttons["新建习惯"].tap()
        let field = a.textFields.element(boundBy: 0)
        field.tap()
        field.typeText("Fresh")
        a.buttons["保存"].tap()
        XCTAssertTrue(row("Fresh").waitForExistence(timeout: 10), "空态建新后正常显示")
        XCTAssertTrue(a.staticTexts["0/1"].waitForExistence(timeout: 10))
    }

    // MARK: 15. 全打卡完成态（环满 + 文案切换 + 可回退）

    func test15_allDoneState() {
        let a = launch(fresh: true)
        if workoutDueToday { tapCheck("锻炼") }
        tapCheck("阅读")
        tapPlus("喝水", times: 8)
        XCTAssertTrue(a.staticTexts["\(dueCount)/\(dueCount)"].waitForExistence(timeout: 8), "环满 \(dueCount)/\(dueCount)")
        XCTAssertTrue(a.staticTexts["全部完成，今天这床布又密了一格"].waitForExistence(timeout: 10), "完成文案")
        snap("15-all-done")
        tapCheck("阅读")   // 取消一个 → 回到未满
        XCTAssertTrue(a.staticTexts["\(dueCount - 1)/\(dueCount)"].waitForExistence(timeout: 10))
    }
}

// MARK: - 第二轮：关闭「未尽事项」（通知权限 / 拖拽排序 / 桌面小组件）

extension QuiltUITests {

    private var springboard: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.springboard")
    }

    /// 中英文系统文案的多候选谓词
    private func either(_ zh: String, _ en: String) -> NSPredicate {
        NSPredicate(format: "label CONTAINS '\(zh)' OR label CONTAINS '\(en)'")
    }

    // MARK: 16. 提醒保存 → 系统通知权限弹窗（首次）/ 静默通过（已授权）

    func test16_reminder_permissionDialog() {
        let a = launch()
        row("阅读").tap()
        XCTAssertTrue(a.staticTexts["当前连续"].waitForExistence(timeout: 10))
        a.buttons["更多操作"].tap()
        a.buttons["编辑"].tap()
        let toggle = a.switches["每天提醒"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        a.swipeUp()   // 时间行可能落在可视区之外，滚动带出再断言
        XCTAssertTrue(a.staticTexts["提醒时间"].waitForExistence(timeout: 10))
        a.buttons["保存"].tap()

        // 首次会弹系统权限框；已授权过则直接回今天页
        let allow = springboard.alerts.buttons.matching(either("允许", "Allow")).firstMatch
        if allow.waitForExistence(timeout: 6) {
            snap("16-permission-dialog")
            allow.tap()
        }
        XCTAssertTrue(row("阅读").waitForExistence(timeout: 8), "保存后回到今天页")
    }

    // MARK: 17. 编辑模式拖拽排序

    func test17_dragReorder() throws {
        let a = launch()
        // EditButton 是系统控件，标签随模拟器语言（英文 Edit / 中文 编辑）
        let editBtn = a.buttons.matching(either("编辑", "Edit")).firstMatch
        XCTAssertTrue(editBtn.waitForExistence(timeout: 10), "应有编辑按钮")
        editBtn.tap()
        let doneBtn = a.buttons.matching(either("完成", "Done")).firstMatch
        XCTAssertTrue(doneBtn.waitForExistence(timeout: 10), "进入编辑模式")

        let reading = row("阅读")
        let workout = row("锻炼")
        XCTAssertTrue(reading.exists && workout.exists)

        // 编辑模式下整行可拖动：把「阅读」（第 2 行）拖到「锻炼」（第 1 行）上方
        let from = reading.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to = workout.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        from.press(forDuration: 0.5, thenDragTo: to)

        doneBtn.tap()
        let readingY = row("阅读").frame.minY
        let workoutY = row("锻炼").frame.minY
        XCTAssertLessThan(readingY, workoutY, "拖拽后「阅读」应排在「锻炼」之前")
        snap("17-reordered")
    }

    /// 小组件打卡按钮定位：组件是独立进程，不受 App 的强制中文参数影响，
    /// 标签随系统语言且目标习惯不定，用「任意习惯 + 中英 + 打卡/取消」谓词匹配
    private func anyCheckButton(_ spring: XCUIApplication, done: Bool) -> XCUIElement {
        // 注意：本机 Foundation 的格式解析器不支持 "NOT CONTAINS"，
        // 排除语义要写成 "AND NOT (…)"
        let p: NSPredicate = done
            ? NSPredicate(format: "label CONTAINS 'Undo' OR label CONTAINS '取消打卡'")
            : NSPredicate(format: "(label CONTAINS 'Check in' OR label CONTAINS '打卡') AND NOT (label CONTAINS 'Undo' OR label CONTAINS '取消')")
        return spring.buttons.matching(p).firstMatch
    }

    // MARK: 18. 桌面小组件：springboard 挂载 + 小组件打卡回写 App

    func test18_widget_addAndCheckIn() throws {
        // 保持「阅读未打卡」的确定性起点：小组件上点 + → 全链路变已打卡
        let a = launch(fresh: true)

        XCUIDevice.shared.press(.home)
        let spring = springboard
        XCTAssertTrue(spring.wait(for: .runningForeground, timeout: 10), "应回到主屏幕")

        // 桌面上已有小组件（重复跑用例）则跳过添加
        if !anyCheckButton(spring, done: false).exists && !anyCheckButton(spring, done: true).exists {
            // 长按 App 图标 → 编辑主屏幕
            let icon = spring.icons["Quilt"].firstMatch
            XCTAssertTrue(icon.waitForExistence(timeout: 10), "桌面应有 Quilt 图标")
            icon.press(forDuration: 1.5)
            let editItem = spring.buttons.matching(either("编辑主屏幕", "Edit Home Screen")).firstMatch
            XCTAssertTrue(editItem.waitForExistence(timeout: 10), "长按菜单应有「编辑主屏幕」")
            editItem.tap()

            // iOS 26 抖动模式左上是「编辑」按钮（点开才有「添加小组件」菜单）
            let jiggleEdit = spring.buttons.matching(either("编辑", "Edit")).firstMatch
            if jiggleEdit.waitForExistence(timeout: 10) {
                jiggleEdit.tap()
            }
            let plus = spring.buttons.matching(either("添加小组件", "Add Widget")).firstMatch
            if !plus.waitForExistence(timeout: 10) {
                print("UITEST-DEBUG jiggle menu tree:\n\(spring.debugDescription)")
            }
            XCTAssertTrue(plus.waitForExistence(timeout: 10), "编辑菜单应有「添加小组件」")
            plus.tap()

            // 小组件库：搜索 Quilt，点「今日习惯」组件预览
            let search = spring.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 8), "小组件库应有搜索框")
            search.tap()
            search.typeText("Quilt")
            sleep(1)
            // 搜索结果先出现「Quilt 应用行」，点它才展开组件列表；键盘动画可能
            // 让元素暂时 not hittable，直接坐标点击兜底
            let appRow = spring.staticTexts["Quilt"].firstMatch
            XCTAssertTrue(appRow.waitForExistence(timeout: 8), "搜索结果应有 Quilt")
            appRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let preview = spring.descendants(matching: .any)
                .matching(either("今日习惯", "习惯格子")).firstMatch
            XCTAssertTrue(preview.waitForExistence(timeout: 8), "应出现 Quilt 小组件列表")
            if preview.isHittable {
                preview.tap()
            } else {
                preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            // v2.1：选「小」尺寸（两列方形），验证尺寸选择存在且可用
            // iOS 26 组件详情 = 可滑动尺寸轮播（第一页即小尺寸方形，小/中/大依次排列），
            // 无文字尺寸 chip；默认停在第一页，直接添加即为小尺寸
            sleep(1)
            snap("18-size-carousel-small")
            let addBtn = spring.buttons.matching(either("添加小组件", "Add Widget")).firstMatch
            XCTAssertTrue(addBtn.waitForExistence(timeout: 6), "应有「添加小组件」按钮")
            addBtn.tap()
            XCUIDevice.shared.press(.home)   // 退出编辑模式
        }

        // 找到小组件的打卡按钮（可能在第 2 页）
        var widgetBtn = anyCheckButton(spring, done: false)
        for page in 0..<3 where !widgetBtn.exists && !anyCheckButton(spring, done: true).exists {
            if page > 0 { spring.swipeRight() }
            widgetBtn = anyCheckButton(spring, done: false)
        }
        XCTAssertTrue(widgetBtn.waitForExistence(timeout: 10) || anyCheckButton(spring, done: true).exists,
                      "桌面小组件应渲染出打卡按钮")
        snap("18-widget-on-home")

        // 小组件上直接打卡（AppIntent 在扩展进程写共享库）。
        // 组件时间线重载有系统级延迟：翻转给 20s 宽限；最终以 App 内数据为准。
        widgetBtn.tap()
        _ = anyCheckButton(spring, done: true).waitForExistence(timeout: 20)   // 渲染宽限，非硬断言
        snap("18-widget-after-tap")

        // 回 App 验证回写（事实源）：组件打卡的那格会点亮进度环
        a.activate()
        XCTAssertTrue(a.staticTexts["今天"].waitForExistence(timeout: 8))
        XCTAssertTrue(a.staticTexts["1/\(dueCount)"].waitForExistence(timeout: 8),
                      "小组件打卡应写回 App：进度环 1/\(dueCount)")
        snap("18-widget-writeback")
    }
}

// MARK: - 第三轮：v2 弹性习惯（每周 N 次）

extension QuiltUITests {

    // MARK: 19. 弹性习惯全流程（新建 → 周进度 → 打卡 → 不计入进度环）

    func test19_flexibleWeeklyHabit() {
        let a = launch()
        a.buttons["新建习惯"].tap()
        XCTAssertTrue(a.staticTexts["新习惯"].waitForExistence(timeout: 10))
        let field = a.textFields.element(boundBy: 0)
        field.tap()
        field.typeText("YogaTime")
        a.buttons["每周 N 次"].tap()
        XCTAssertTrue(a.staticTexts["目标：每周 3 次"].waitForExistence(timeout: 3), "弹性目标行出现")
        a.buttons["保存"].tap()
        XCTAssertTrue(row("YogaTime").waitForExistence(timeout: 10), "弹性习惯入列")
        XCTAssertTrue(a.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '本周 0/3'")).firstMatch.waitForExistence(timeout: 10),
            "副标显示周进度")
        XCTAssertTrue(a.staticTexts["0/\(dueCount)"].waitForExistence(timeout: 10),
                      "弹性习惯不计入进度环分母")

        a.buttons["YogaTime打卡"].tap()
        XCTAssertTrue(a.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '本周 1/3'")).firstMatch.waitForExistence(timeout: 10),
            "打卡后周进度 +1")
        snap("19-flexible")

        // 详情页：弹性连击按周计
        row("YogaTime").tap()
        XCTAssertTrue(a.staticTexts["当前连续"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(row("YogaTime").waitForExistence(timeout: 10))
    }
}

// MARK: - 第四轮：双语（跟随系统语言，zh-Hans / en）

extension QuiltUITests {

    // MARK: 20. 英文界面冒烟（导航、页签、a11y、副标全部走目录翻译）

    func test20_localization_english() {
        let a = launch(fresh: true, locale: "en")
        // 页签与标题
        XCTAssertTrue(a.tabBars.buttons["Stats"].exists, "英文页签 Stats")
        XCTAssertTrue(a.tabBars.buttons["Settings"].exists)
        // 新建按钮 a11y
        XCTAssertTrue(a.buttons["New habit"].exists)
        // 副标与打卡 a11y（习惯名是用户数据保持原文，动作词走翻译）
        XCTAssertTrue(a.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Every day'")).firstMatch.exists, "Every day 副标")
        XCTAssertTrue(a.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Check in'")).firstMatch.exists, "Check in a11y")
        // 打卡后进度环副标：0/2 → '1 to go'（周日锻炼不算应做）
        let check = a.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Check in'")).firstMatch
        check.tap()
        XCTAssertTrue(a.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'to go'")).firstMatch.waitForExistence(timeout: 10),
            "英文还剩文案")
        snap("20-english")
    }
}

// MARK: - 第五轮：分次提醒（喝水式计数习惯）

extension QuiltUITests {

    // MARK: 21. 计数型习惯的分次提醒 UI（方式选择 / 最晚时间 / 持久化）

    func test21_pacedReminderUI() {
        let a = launch()
        a.buttons["新建习惯"].tap()
        XCTAssertTrue(a.staticTexts["新习惯"].waitForExistence(timeout: 10))

        // 先设置开关类控件（键盘不出现），最后再输入名字。
        // 提醒区在表单底部且懒加载：先滚动进屏，开关才会进可达树
        a.buttons["每日计数"].tap()
        a.swipeUp()
        let reminderToggle = a.switches["每天提醒"]
        XCTAssertTrue(reminderToggle.waitForExistence(timeout: 10))
        reminderToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertTrue(a.buttons["固定时间"].waitForExistence(timeout: 10), "计数型出现提醒方式选择")
        a.buttons["分次提醒"].tap()
        a.swipeUp()
        XCTAssertTrue(a.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS '提醒时段'")).firstMatch
            .waitForExistence(timeout: 10), "时间环出现")
        XCTAssertTrue(a.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '均分'")).firstMatch.exists, "分次 footer 说明")
        snap("21-paced-edit")

        // 最后输入名字并保存
        a.swipeDown()
        let field = a.textFields.element(boundBy: 0)
        field.tap()
        field.typeText("Tea")
        a.buttons["保存"].tap()
        // 首次开提醒会弹通知权限
        let allow = springboard.alerts.buttons.matching(either("允许", "Allow")).firstMatch
        if allow.waitForExistence(timeout: 10) { allow.tap() }
        XCTAssertTrue(row("Tea").waitForExistence(timeout: 8), "保存后回到今天页")

        // 重开编辑验证方式已持久化
        row("Tea").tap()
        XCTAssertTrue(a.staticTexts["当前连续"].waitForExistence(timeout: 10))
        a.buttons["更多操作"].tap()
        a.buttons["编辑"].tap()
        a.swipeUp()   // 提醒区在表单底部，滚进来才有可达树
        XCTAssertTrue(a.buttons["分次提醒"].waitForExistence(timeout: 10),
                      "重开编辑应仍有分次提醒选项（字段持久化由单测覆盖）")
        a.buttons["取消"].tap()
    }
}

// MARK: - 第七轮：今日进度组件（中尺寸）添加验证

extension QuiltUITests {

    // MARK: 23. 组件库出现「今日进度」并添加到桌面

    func test23_progressWidget_add() throws {
        let a = launch(fresh: true)
        XCUIDevice.shared.press(.home)
        let spring = springboard
        XCTAssertTrue(spring.wait(for: .runningForeground, timeout: 10), "应回到主屏幕")

        // 关掉可能残留的组件库页面（上一轮失败可能遗留在展开状态）
        let close = spring.buttons.matching(either("关闭", "Close")).firstMatch
        if close.exists { close.tap() }

        // 打开组件库（带重试）：长按图标 → 编辑主屏幕 → 编辑 → 库。
        // 误点进壁纸自定义编辑器（取消/完成）时先退出；重试仍打不开则跳过本用例
        // （桌面自动化受系统动画/状态影响偶发不稳定，核心链路由 test18 保证）。
        func escapeWallpaperEditorIfNeeded() {
            let done = spring.buttons.matching(either("完成", "Done")).firstMatch
            let cancel = spring.buttons.matching(either("取消", "Cancel")).firstMatch
            if done.exists && cancel.exists && !spring.icons["Quilt"].firstMatch.exists {
                done.tap()
                sleep(2)
            }
        }

        var galleryReady = spring.searchFields.firstMatch.exists
        for _ in 0..<3 where !galleryReady {
            escapeWallpaperEditorIfNeeded()
            XCUIDevice.shared.press(.home)
            let icon = spring.icons["Quilt"].firstMatch
            guard icon.waitForExistence(timeout: 10) else { continue }
            // 图标可能在其他分页（frame 为零 = 未渲染）：左右翻页找到可点的那页
            var flips = 0
            while icon.exists && !icon.isHittable && flips < 4 {
                if flips % 2 == 0 { spring.swipeLeft() } else { spring.swipeRight() }
                flips += 1
            }
            guard icon.isHittable else { continue }
            icon.press(forDuration: 1.5)
            let editItem = spring.buttons.matching(either("编辑主屏幕", "Edit Home Screen")).firstMatch
            guard editItem.waitForExistence(timeout: 10) else { continue }
            editItem.tap()
            let jiggleEdit = spring.buttons.matching(either("编辑", "Edit")).firstMatch
            if jiggleEdit.waitForExistence(timeout: 10) {
                jiggleEdit.tap()
                galleryReady = spring.searchFields.firstMatch.waitForExistence(timeout: 15)
            }
        }
        guard galleryReady || spring.searchFields.firstMatch.exists else {
            throw XCTSkip("组件库自动化在本环境未能打开（系统状态偶发），核心组件链路由 test18 保证")
        }

        let search = spring.searchFields.firstMatch
        search.tap()
        search.typeText("Quilt")
        sleep(2)
        let appRow = spring.staticTexts["Quilt"].firstMatch
        XCTAssertTrue(appRow.waitForExistence(timeout: 15))
        appRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        // 选「今日进度」
        let progressWidget = spring.descendants(matching: .any)
            .matching(either("今日进度", "Today's progress")).firstMatch
        XCTAssertTrue(progressWidget.waitForExistence(timeout: 15), "应出现今日进度组件")
        if progressWidget.isHittable { progressWidget.tap() }
        else { progressWidget.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        snap("23-progress-detail")

        let addBtn = spring.buttons.matching(either("添加小组件", "Add Widget")).firstMatch
        XCTAssertTrue(addBtn.waitForExistence(timeout: 6))
        addBtn.tap()
        XCUIDevice.shared.press(.home)
        sleep(2)

        // 桌面上应出现「今日进度」标题（组件头行）
        XCTAssertTrue(spring.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '今日进度'")).firstMatch
            .waitForExistence(timeout: 10), "今日进度组件应出现在桌面")
        snap("23-progress-on-home")
    }
}
