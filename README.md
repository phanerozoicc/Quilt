# Quilt（中文工作名：缀）

> 每天缝一针，别断链。
> —— NetWorth 记钱，Carved 记事，Timebook 记时间，Quilt 记「该做的事，做没做」。

一款**纯本地**的习惯打卡 iOS 应用（v2）：每个习惯是一块布片，每天打卡缝一针，
一年下来是一床 GitHub 式格子拼布。三种节奏（每天 / 指定星期几 / **每周 N 次弹性**）、
勾选与计数双打卡、日级与**周级连击**、30 周年格子、可交互桌面小组件
（今日清单 + **可长按换习惯**的格子组件）、完成后当天静默的提醒。
全部数据只存在本机的 SwiftData 库里（App Group 容器），**零联网、无账号、
无订阅**，JSON 一键导出导入。

## 名字由来

- **Quilt = 拼布**；中文名「缀」——缝缀、连缀：日日连缀，缺一天就是布上一个洞。
- 「别断链」（Don't break the chain）正是习惯方法论的百年俗语，格子即布片。
- 2026-09 检索为**工作名**，与若干在售 App 存在重名可能，上架前再最终确认。

### 备选名（等用户拍板）

| 名字 | 含义 | 备注 |
|---|---|---|
| Chain | 不断链 | 直白，与 Seinfeld 方法同名 |
| Sod / Lawn | 贡献格子=草地 | 中文圈把 GitHub 格子叫「草」 |
| 日课 | 曾国藩日课十二条 | 中文向，海外不通用 |

## 出处（Product Hunt）

- 对标对象：**Mirror: Habit & Activity Tracker** —— Product Hunt 在售的
  纯离线习惯追踪（"Log habits, set goals, and review trends—all offline,
  with no sign-in required"），与本应用约束完全同向。
- 视觉与商业标杆：**HabitKit** —— GitHub 贡献格子风的同品类标杆，
  solo 开发者 2025 年收入约 $602K（grid UI 即本应用的年格子）。
- 选型过程：翻了 2026-09-01～09-08 日榜、8 月/7 月月榜（几乎全是
  需要后端的 AI SaaS，不符合「纯本地」约束）、Menu Bar Apps 主题页与
  历年经典（Dark Noise、CleanShot 等），按「个人日用 + 纯本地可复刻」
  筛出四个候选（习惯打卡/白噪音/截图钉屏/随手收集箱），用户拍板本项。

## 与原品差异化

| | Mirror / HabitKit | Quilt |
|---|---|---|
| 获取 | App Store 订阅/买断 | 本地源码，免费 |
| 云同步 | 部分依赖 | **无**，零联网（无任何网络请求代码） |
| 数据 | 私有库 | SwiftData（App Group）+ **JSON 全量导出/导入** |
| 中文 | ✗ | ✓ 界面、提醒文案全中文 |
| 小组件 | 有 | 今日清单（可逐条打卡）+ 单习惯格子，点击直达 |
| 连击语义 | 各家不一 | 今天没做**不断链**（宽限到当日结束）、非应做日跳过、创建日前不存在 |

## 功能（v2，全部可用）

- [x] **今天页**：进度环 + 应做清单；勾选型一键切换、计数型 +/− 步进；
      连击徽章（🔥n）；非应做日自动划线提示「今天不用」
- [x] **三种节奏（v2）**：每天 / 指定星期几 / **每周 N 次弹性**——哪天做随意，
      一周攒够 N 次不断链（连击按周计）；弹性习惯不计入今天页进度环分母，
      行内显示「本周 x/N」进度，达标变品牌色
- [x] **习惯管理**：计数目标（如喝水 ×8）；8 色板 × 24 图标；**每日提醒
      （完成后当天静默，v2 逐日续链调度）**；拖拽排序；**归档**（保留历史 +
      设置页可恢复）与删除（连带历史，二次确认）
- [x] **习惯详情**：当前连续 / 最长连续（弹性模式单位为**周**）/ 30 天完成率 /
      累计次数四卡；近 30 周 GitHub 式格子（**出现即自动滚到今天**，今天描边）；
      最近 10 条记录
- [x] **统计页**：今日概览（只算硬性应做）、全部习惯合并热力图（近 26 周）、
      各习惯 30 天完成率横条
- [x] **桌面小组件**：今日清单（中/大，每行一个 App Intent 打卡按钮）；
      **习惯格子（中，长按可选任意习惯，v2 AppIntentConfiguration）**；
      弹性习惯在组件内显示「本周 x/N」；widgetURL 深链回今天页
- [x] **数据**：JSON 导出（ShareLink 表单行，点行即弹系统分享）/ 导入（覆盖式，
      fileImporter）/ 清空；**已归档管理**（设置页恢复/删除）；
      首启动种入 3 条示例习惯 + 近 6 周确定性历史（设置里可清空重来）
- [x] **无障碍**：全部打卡控件、颜色、图标、周几均有中文显式可达标签
      （屏幕阅读器可用，UI 测试也因此稳定）
- [x] **中英双语（v2）**：跟随系统语言自动切换；开发语言中文，英文全量翻译
      （String Catalog，App 与小组件共用）
- [x] 连击算法：日级（跨月/宽限日/跳过日/创建边界）+ 周级（本周宽限/整周空白/
      周一锚定）全覆盖单测（30/30）

## 已知边界（v2，刻意不做）

- 弹性习惯（每周 N 次）不计入今天页进度环分母（设计决策：环只反映「今天必须做」，
  弹性的进度看行内「本周 x/N」）；弹性习惯的 30 天完成率按「天天可打」折算
- 提醒逐日续链：**连续多天不打开 App，提醒链在第一次触发后停止**（打开即自动续）；
  换取「完成后当天静默」
- 单习惯格子小组件长按换习惯依赖系统组件配置面板（未做 UI 自动化，挂载与打卡
  已由 test18 全覆盖）
- 无 iPad 适配（TARGETED_DEVICE_FAMILY=1）、无 Apple Watch、无 iCloud

## 架构

```
project.yml (XcodeGen)
├─ Quilt.app            Sources/
│   ├─ HabitsMath.swift   纯函数核心：连击/最长链/完成率/格子分桶（零依赖，全量单测）
│   ├─ Models.swift       Habit / CheckIn（SwiftData @Model，级联删除）
│   ├─ Store.swift        唯一数据入口：CRUD/排序/导入导出/快照/示例数据
│   ├─ Shared/            WidgetSnapshot（App↔Widget 共享形状）+ App Group 容器
│   └─ …Views             Theme（设计系统）/ Today / Detail / Edit / Stats / Settings
├─ QuiltWidget.appex    Widget/  时间线读快照 JSON；打卡 Intent 直写共享库
├─ QuiltTests           22 个单测（HabitsMath 11 + Store 11）
└─ QuiltUITests         18 条 XCUITest 全流程用例（真实点击，含截图存档）
```

- 时区约定：所有「天」都是本地时区 `startOfDay`；格子列序固定**周一首**。
- App Group `group.com.haozc.quilt`：共享 SwiftData 库 + 快照 JSON + 种子标记。
- 应用图标：黑白布片格子（CoreGraphics 脚本绘制），改设计后重生成全套尺寸：
  `swift Scripts/make-icon.swift Support/Assets.xcassets/AppIcon.appiconset/AppIcon1024.png`
  再用 sips 缩出 icon-{40,58,60,80,87,120,180}.png（脚本目录有说明；
  本机 actool 会静默忽略单尺寸 1024 新格式，必须用经典多尺寸 iconset）。

## 构建与验证

```bash
xcodegen generate
xcodebuild -project Quilt.xcodeproj -scheme Quilt \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

- **单元 30/30 + UI 仿真 20/20，共 50/50 通过**（Xcode 26 / iPhone 17 Pro 模拟器实测）。
- UI 用例覆盖：启动、勾选/计数打卡、建/改/归档/恢复/删除、详情格子、统计、
  设置与导出分享、杀进程持久化、清空与空态、全打卡完成态、**系统通知权限弹窗、
  编辑模式拖拽排序、桌面小组件全自动挂载 + 组件打卡跨进程回写、弹性习惯全流程、
  英文界面冒烟**（19 条中文用例强制 zh-Hans，1 条英文 locale）。
- 截图：`docs/screenshots/`（人工巡检）+ `docs/screenshots/uitest/`（自动化过程）。
- 设计事实源：`docs/ui-spec.md`；两轮修的 bug 与取证：`docs/test-report.md`。
