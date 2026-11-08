import SwiftUI
import UniformTypeIdentifiers

// MARK: - 设置：数据导出/导入 + 关于

struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @State private var exportURL: URL?
    @State private var importing = false
    @State private var confirmClear = false
    @State private var alertTitle: String?
    @State private var alertMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // ShareLink 直接做行：点行即弹系统分享面板（避免 sheet 槽位冲突）
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("导出全部数据（JSON）", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        LabeledContent("导出", value: String(localized: "生成中…"))
                    }
                    Button {
                        importing = true
                    } label: {
                        Label("导入数据（覆盖现有）", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("数据")
                } footer: {
                    Text("数据只存在本机的 App Group 容器里。导出的是普通 JSON，导入会覆盖现有全部习惯与打卡。")
                }

                Section {
                    Button("清空全部数据", role: .destructive) { confirmClear = true }
                }

                if !store.archivedHabits.isEmpty {
                    Section("已归档（保留历史，可恢复）") {
                        ForEach(store.archivedHabits) { habit in
                            HStack(spacing: DS.gapSmall) {
                                SymbolCircle(symbol: habit.symbol, colorHex: habit.colorHex, size: 30)
                                Text(habit.name)
                                    .font(.callout)
                                Spacer()
                                Button("恢复") { store.archive(habit, false) }
                                    .buttonStyle(.bordered)
                                Button("删除", role: .destructive) {
                                    HabitNotifications.cancel(for: habit)
                                    store.delete(habit)
                                }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                Section("关于") {
                    LabeledContent("版本", value: "1.0 (Quilt · 缀)")
                    LabeledContent("存储", value: String(localized: "本机 SwiftData"))
                    LabeledContent("网络", value: String(localized: "零联网"))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Quilt，中文叫「缀」。每个习惯是一块布片，每天打卡缝一针，一年下来是一床只属于你的拼布。")
                            .font(.callout)
                        Text("对标 Product Hunt 上的 Mirror（纯离线习惯追踪）与 HabitKit（GitHub 式格子），本地化复刻：无账号、无云端、无订阅。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("设置")
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [UTType.json],
                          allowsMultipleSelection: false) { result in
                guard case let .success(urls) = result, let url = urls.first else { return }
                let secured = url.startAccessingSecurityScopedResource()
                defer { if secured { url.stopAccessingSecurityScopedResource() } }
                do {
                    try store.importJSON(from: url)
                    showAlert(String(localized: "导入成功"), String(localized: "已覆盖现有数据"))
                } catch {
                    showAlert(String(localized: "导入失败"), error.localizedDescription)
                }
            }
            .confirmationDialog("确定清空全部习惯与打卡历史？此操作不可撤销。",
                                isPresented: $confirmClear, titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    HabitNotifications.cancelAll(for: store.habits + store.archivedHabits)
                    store.clearAllData()
                }
            }
            .onAppear {
                // 每次进设置页生成新鲜导出文件（个人规模数据量，毫秒级）
                if exportURL == nil { exportURL = store.exportJSON() }
            }
        }
        .alert(alertTitle ?? "", isPresented: Binding(
            get: { alertTitle != nil },
            set: { if !$0 { alertTitle = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func showAlert(_ title: String, _ message: String) {
        alertTitle = title
        alertMessage = message
    }
}
