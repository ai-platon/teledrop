// Tiles screenshots into one labelled sheet: contact <out.png> <columns> <label=path>...
import AppKit

let args = CommandLine.arguments
let out = args[1], columns = Int(args[2])!
let items = args.dropFirst(3).compactMap { arg -> (String, NSImage)? in
    let parts = arg.split(separator: "=", maxSplits: 1).map(String.init)
    guard parts.count == 2, let image = NSImage(contentsOfFile: parts[1]) else { return nil }
    return (parts[0], image)
}
let cellW: CGFloat = 520, labelH: CGFloat = 26, pad: CGFloat = 14
let cellH = items.map { cellW * $0.1.size.height / $0.1.size.width }.max() ?? 100
let rows = (items.count + columns - 1) / columns
let size = NSSize(width: CGFloat(columns) * (cellW + pad) + pad, height: CGFloat(rows) * (cellH + labelH + pad) + pad)
let sheet = NSImage(size: size)
sheet.lockFocus()
NSColor(white: 0.12, alpha: 1).setFill()
NSRect(origin: .zero, size: size).fill()
for (i, item) in items.enumerated() {
    let col = CGFloat(i % columns), row = CGFloat(i / columns)
    let x = pad + col * (cellW + pad)
    let top = size.height - pad - row * (cellH + labelH + pad)
    item.0.draw(at: NSPoint(x: x, y: top - 20),
                withAttributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: NSColor.white])
    let h = cellW * item.1.size.height / item.1.size.width
    item.1.draw(in: NSRect(x: x, y: top - labelH - h, width: cellW, height: h))
}
sheet.unlockFocus()
let rep = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print(out)
