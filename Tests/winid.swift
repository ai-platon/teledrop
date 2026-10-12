// Prints the window id of TeleDrop's setup window (layer 0); exits 1 if it is not open.
import CoreGraphics
import Foundation
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
guard let w = list.first(where: { $0[kCGWindowOwnerName as String] as? String == "TeleDrop" && $0[kCGWindowLayer as String] as? Int == 0 }) else { exit(1) }
print(w[kCGWindowNumber as String]!)
