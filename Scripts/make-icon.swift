import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

// MARK: - Quilt 应用图标生成脚本（黑白版）
//
// 设计语言：深炭黑渐变底 + 斜向缝线虚线 + 4×4 白色布片格子（深浅不一）
// + 一格反白打黑勾（今天缝了一针 = 视觉焦点）。
// 用法：swift make-icon.swift <输出.png 路径>

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size,
                    bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

// --- 背景：左上到右下的深炭黑渐变 ---
let bgColors = [rgb(0x3A3A3C), rgb(0x0B0B0C)] as CFArray
let gradient = CGGradient(colorsSpace: space, colors: bgColors, locations: [0, 1])!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: 0, y: size),
                       end: CGPoint(x: size, y: 0),
                       options: [])

// --- 缝线：两条斜向虚线（右上传方向的针脚）---
ctx.saveGState()
ctx.setStrokeColor(rgb(0xFFFFFF, 0.10))
ctx.setLineWidth(12)
ctx.setLineCap(.round)
ctx.setLineDash(phase: 0, lengths: [6, 34])
for offset in [CGFloat(-140), CGFloat(180)] {
    ctx.move(to: CGPoint(x: offset, y: -60))
    ctx.addLine(to: CGPoint(x: CGFloat(size) + 60, y: CGFloat(size) - offset))
}
ctx.strokePath()
ctx.restoreGState()

// --- 4×4 布片格子 ---
let margin: CGFloat = 208
let gap: CGFloat = 30
let cell = (CGFloat(size) - margin * 2 - gap * 3) / 4
let radius: CGFloat = 34

// 深浅矩阵：模拟一周周真实的打卡数据（无两连相同，右下渐密）
let shades: [[CGFloat]] = [
    [0.32, 0.58, 0.34, 0.72],
    [0.55, 0.85, 0.62, 0.38],
    [0.36, 0.66, 0.85, 0.60],
    [0.68, 0.42, 0.78, 0.92],
]

// 焦点格：第 2 行第 2 列（0 起）= 火焰橙 + 白勾
let accentRow = 1, accentCol = 2

for r in 0..<4 {
    for c in 0..<4 {
        let x = margin + CGFloat(c) * (cell + gap)
        // 屏幕坐标 y 向下翻转（第 0 行画在顶部）
        let y = CGFloat(size) - margin - cell - CGFloat(r) * (cell + gap)
        let rect = CGRect(x: x, y: y, width: cell, height: cell)
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius,
                          transform: nil)

        if r == accentRow, c == accentCol {
            // 反白焦点格：白底黑勾
            ctx.setFillColor(rgb(0xF5F5F5))
            ctx.addPath(path)
            ctx.fillPath()
            ctx.setStrokeColor(rgb(0x111111))
            ctx.setLineWidth(26)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            let p = CGPoint(x: x, y: y)
            ctx.move(to: CGPoint(x: p.x + cell * 0.26, y: p.y + cell * 0.52))
            ctx.addLine(to: CGPoint(x: p.x + cell * 0.44, y: p.y + cell * 0.32))
            ctx.addLine(to: CGPoint(x: p.x + cell * 0.76, y: p.y + cell * 0.70))
            ctx.strokePath()
        } else {
            ctx.setFillColor(rgb(0xFFFFFF, shades[r][c]))
            ctx.addPath(path)
            ctx.fillPath()
        }
    }
}

// --- 写出 PNG ---
let image = ctx.makeImage()!
let outURL = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "AppIcon1024.png")
guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL,
                                                 UTType.png.identifier as CFString, 1, nil) else {
    FileHandle.standardError.write("创建 PNG 目标失败：\(outURL.path)\n".data(using: .utf8)!)
    exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else {
    FileHandle.standardError.write("写 PNG 失败：\(outURL.path)\n".data(using: .utf8)!)
    exit(1)
}
print("已生成 \(outURL.path)")
