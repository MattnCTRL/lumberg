import AppKit
import LumbergCore

// lumberg-ascii [face] [neutral|pleased|displeased]   print the portrait
// lumberg-ascii icon <out.png>                        write the 1024 px app icon

let args = CommandLine.arguments

if args.count >= 3, args[1] == "icon" {
    let size = 1024
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    ctx.addPath(CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil))
    ctx.clip()
    ctx.setFillColor(CGColor(red: 0.078, green: 0.071, blue: 0.055, alpha: 1))
    ctx.fill(tile)

    let lines = AsciiPortrait.render(cols: 44, rows: 23, view: AsciiPortrait.faceView, mood: .neutral)
    let font = NSFont.monospacedSystemFont(ofSize: 27, weight: .heavy)
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    style.minimumLineHeight = 29
    style.maximumLineHeight = 29
    let text = NSAttributedString(string: lines.joined(separator: "\n"), attributes: [
        .font: font, .paragraphStyle: style,
        .foregroundColor: NSColor(red: 0.918, green: 0.886, blue: 0.804, alpha: 1),
    ])
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    text.draw(in: CGRect(x: 100, y: 205, width: 824, height: 680))

    // Swingline-red desk edge.
    ctx.setFillColor(CGColor(red: 0.886, green: 0.251, blue: 0.184, alpha: 1))
    ctx.fill(CGRect(x: 100, y: 100, width: 824, height: 84))
    NSGraphicsContext.current = nil

    guard let image = ctx.makeImage(),
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { exit(1) }
    try png.write(to: URL(fileURLWithPath: args[2]))
    exit(0)
}

let face = args.contains("face")
let mood = Mood(rawValue: args.last ?? "") ?? .neutral
let lines = face
    ? AsciiPortrait.render(cols: 40, rows: 21, view: AsciiPortrait.faceView, mood: mood)
    : AsciiPortrait.render(cols: 110, rows: 52, mood: mood)
print(lines.joined(separator: "\n"))
