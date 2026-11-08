import SwiftUI

// MARK: - 设计系统（Quilt v1）
//
// 原则：8pt 网格、单一品牌色（苔绿，生长之意）+ 习惯八色板、卡片三层质感
// （浅填充 + 发丝描边）、SF Symbols 承载图标、格子是唯一的视觉主角。

enum DS {
    static let pad: CGFloat = 16
    static let gap: CGFloat = 12
    static let gapSmall: CGFloat = 8
    static let radius: CGFloat = 16
    static let radiusSmall: CGFloat = 10
    /// 年格子单元尺寸
    static let cell: CGFloat = 13
    static let cellGap: CGFloat = 3
}

extension Color {
    /// 品牌主色：苔绿
    static let brand = Color(hex: 0x3E9B6C)
    static let brandSoft = Color(hex: 0x7BC49A)
    static let brandDeep = Color(hex: 0x2C7A51)
    /// 连击火焰
    static let flame = Color(hex: 0xE58B45)

    /// 习惯八色板（新建时按已有习惯数量轮转取色）
    static let habitPalette: [Int] = [
        0x3E9B6C, 0x5B8DEF, 0xE58B45, 0xC9524F,
        0x8B6FD8, 0x3FA8B5, 0xD66B93, 0xD9A441,
    ]

    static func habitColor(_ hex: Int) -> Color { Color(hex: UInt32(hex)) }

    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - 卡片

private struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(DS.gap)
            .background(
                RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}

// MARK: - 习惯图标

struct SymbolCircle: View {
    let symbol: String
    let colorHex: Int
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.habitColor(colorHex).opacity(0.16))
            Image(systemName: symbol)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(Color.habitColor(colorHex))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 连击徽章

struct StreakBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: count > 0 ? "flame.fill" : "flame")
                .font(.caption)
            Text("\(count)")
                .font(.caption.weight(.bold).monospacedDigit())
        }
        .foregroundStyle(count > 0 ? Color.flame : Color.secondary.opacity(0.6))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.flame.opacity(count > 0 ? 0.14 : 0.06)))
    }
}

// MARK: - 进度环

struct ProgressRing: View {
    let value: Int
    let total: Int
    var size: CGFloat = 64

    private var progress: Double {
        guard total > 0 else { return 0 }
        return min(Double(value) / Double(total), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(colors: [Color.brandSoft, Color.brand],
                                    center: .center,
                                    startAngle: .degrees(-90),
                                    endAngle: .degrees(-90 + 360 * progress)),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text(total == 0 ? "—" : "\(value)/\(total)")
                .font(.system(size: size * 0.26, weight: .bold, design: .rounded).monospacedDigit())
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 空状态

struct EmptyState: View {
    let symbol: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.brandSoft)
            Text(title).font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DS.pad)
    }
}
