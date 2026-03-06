import Foundation

let fm = FileManager.default
let basePath = "/Users/jebinjames/Documents/QuickView/quickview_mac/SilkySnip/Resources"
guard let enumerator = fm.enumerator(atPath: basePath) else { exit(1) }

let keyToAdd = "\"btn_cancel_all\" = \"Cancel All\";"

for case let file as String in enumerator {
    if file.hasSuffix("Localizable.strings") {
        let fullPath = basePath + "/" + file
        do {
            var content = try String(contentsOfFile: fullPath, encoding: .utf8)
            if !content.contains("\"btn_cancel_all\"") {
                content += "\n\(keyToAdd)\n"
                try content.write(toFile: fullPath, atomically: true, encoding: .utf8)
                print("Updated \(file)")
            }
        } catch {
            print("Error updating \(file): \(error)")
        }
    }
}
