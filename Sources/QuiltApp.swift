import SwiftUI
import UserNotifications

@main
struct QuiltApp: App {
    @StateObject private var store: Store
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let args = CommandLine.arguments
        let store: Store
        if args.contains("-uitest-empty") {
            // UI 测试：空库起点
            store = Store(seed: false)
            store.clearAllData()
        } else if args.contains("-uitest-fresh") {
            // UI 测试：确定性示例数据起点（先清再种）
            store = Store(seed: false)
            store.clearAllData()
            store.seedDemo(force: true)
        } else {
            store = AppContext.shared.store
        }
        _store = StateObject(wrappedValue: store)
        store.onSave = { [weak store] in
            guard let store else { return }
            HabitNotifications.syncAll(store: store)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(.brand)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        // 小组件排队的打卡先落库；扩展进程写库后回前台也要整体重拉
                        store.drainPendingCheckIns()
                        store.reload()
                        HabitNotifications.syncAll(store: store)
                    } else if phase == .background {
                        store.writeSnapshot()
                    }
                }
        }
    }
}

@MainActor
final class AppContext {
    static let shared = AppContext()
    let store = Store()
}

// MARK: - 根视图（三页签）

struct RootView: View {
    @EnvironmentObject private var store: Store
    @State private var tab: Int

    init() {
        // 供模拟器截图/UI 验证直接落页
        _tab = State(initialValue: CommandLine.arguments.contains("-uitest-stats") ? 1 : 0)
    }

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("今天", systemImage: "sun.max.fill") }
                .tag(0)
            StatsView()
                .tabItem { Label("统计", systemImage: "chart.bar.fill") }
                .tag(1)
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
                .tag(2)
        }
        .onOpenURL { url in
            // 小组件深链：回到今天页
            if url.scheme == "quilt" { tab = 0 }
        }
    }
}

// HabitNotifications 已移至 Sources/Shared/HabitNotifications.swift（小组件打卡也要重排提醒）
