import SwiftUI

// MARK: - 时间段环（双旋钮选起止时间）
//
// 24 小时表盘：顶部 00:00，顺时针一圈。拖动两个旋钮选时间段，
// 选中弧段品牌色高亮，中央显示「开始 – 结束」。5 分钟吸附，不跨天。

struct TimeRangeRing: View {
    @Binding var startMinute: Int   // 0...1439
    @Binding var endMinute: Int     // startMinute + 30 ... 1439
    var diameter: CGFloat = 232

    private enum Knob { case start, end }
    @State private var activeKnob: Knob?

    private let trackWidth: CGFloat = 14
    private let minGap = 30   // 起止最小间隔 30 分钟
    private var radius: CGFloat { diameter / 2 - trackWidth / 2 - 10 }

    private func angleDegree(_ minute: Int) -> Angle {
        .degrees(-90 + Double(minute) / 1440 * 360)
    }

    private func position(for minute: Int, size: CGSize) -> CGPoint {
        let theta = Double(minute) / 1440 * 2 * .pi
        return CGPoint(x: size.width / 2 + radius * sin(theta),
                       y: size.height / 2 - radius * cos(theta))
    }

    private func minute(at location: CGPoint, size: CGSize) -> Int {
        let dx = location.x - size.width / 2
        let dy = location.y - size.height / 2
        var deg = atan2(dx, -dy) * 180 / .pi
        if deg < 0 { deg += 360 }
        return (Int((deg / 360 * 1440 / 5).rounded()) * 5) % 1440   // 5 分钟吸附
    }

    private func circularDistance(_ a: Int, _ b: Int) -> Int {
        let d = abs(a - b) % 1440
        return min(d, 1440 - d)
    }

    private func timeText(_ m: Int) -> String {
        String(format: "%02d:%02d", m / 60, m % 60)
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: trackWidth)
                ArcShape(from: angleDegree(startMinute), to: angleDegree(endMinute))
                    .stroke(Color.brand,
                            style: StrokeStyle(lineWidth: trackWidth, lineCap: .round))
                ForEach(0..<24, id: \.self) { h in
                    Capsule()
                        .fill(Color.primary.opacity(h % 6 == 0 ? 0.3 : 0.15))
                        .frame(width: 2, height: h % 6 == 0 ? 10 : 5)
                        .offset(y: -radius - trackWidth / 2 - 8)
                        .rotationEffect(.degrees(Double(h) / 24 * 360))
                }
                ForEach([0, 6, 12, 18], id: \.self) { h in
                    Text(String(format: "%02d", h))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .position(position(for: h * 60, size: size))
                }
                ringKnob(minute: startMinute, filled: false)
                    .position(position(for: startMinute, size: size))
                ringKnob(minute: endMinute, filled: true)
                    .position(position(for: endMinute, size: size))
                VStack(spacing: 2) {
                    Text("\(timeText(startMinute)) – \(timeText(endMinute))")
                        .font(.callout.weight(.bold).monospacedDigit())
                    Text("提醒时段")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .position(x: size.width / 2, y: size.height / 2)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if activeKnob == nil {
                            let m = minute(at: value.location, size: size)
                            activeKnob = circularDistance(m, startMinute) <= circularDistance(m, endMinute)
                                ? .start : .end
                        }
                        apply(minute(at: value.location, size: size))
                    }
                    .onEnded { _ in activeKnob = nil }
            )
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("提醒时段")
    }

    private func apply(_ m: Int) {
        switch activeKnob {
        case .start:
            startMinute = min(max(m, 0), endMinute - minGap)
        case .end:
            endMinute = min(max(m, startMinute + minGap), 1439)
        case nil:
            break
        }
    }

    private func ringKnob(minute: Int, filled: Bool) -> some View {
        ZStack {
            Circle()
                .fill(filled ? Color.brand : Color(uiColor: .systemBackground))
                .frame(width: 30, height: 30)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            Circle()
                .strokeBorder(filled ? Color.clear : Color.brand, lineWidth: 2.5)
                .frame(width: 30, height: 30)
            Text(timeText(minute))
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(filled ? .white : Color.brand)
        }
    }
}

private struct ArcShape: Shape {
    let from: Angle
    let to: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: rect.width / 2,
                    startAngle: from, endAngle: to, clockwise: false)
        return path
    }
}
