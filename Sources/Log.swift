import Foundation

/// Appends a line to ~/Library/Logs/TeleDrop.log.
func log(_ message: String) {
    let line = "\(Date().formatted(.iso8601)) \(message)\n"
    let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/TeleDrop.log")
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    } else {
        try? line.write(to: url, atomically: true, encoding: .utf8)
    }
}
