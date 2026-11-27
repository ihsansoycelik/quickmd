import Foundation

/// Turning a file's bytes into a note and back without changing what
/// the user didn't touch: the encoding, a byte order mark and the line
/// breaks all round-trip. Files that aren't text, or that only decode
/// by losing characters, are refused instead of opened and later
/// overwritten with damage.
struct TextFile: Equatable {
    /// The note, with `\n` line breaks only and no byte order mark.
    var text: String
    var encoding: String.Encoding = .utf8
    var hasBOM = false
    var lineEnding = "\n"

    private static let utf8BOM: [UInt8] = [0xEF, 0xBB, 0xBF]

    static func decode(_ data: Data) throws -> TextFile {
        let bytes = [UInt8](data.prefix(3))
        var file: TextFile
        if bytes.count >= 2, bytes[0] == 0xFF && bytes[1] == 0xFE || bytes[0] == 0xFE && bytes[1] == 0xFF {
            // UTF-16 with its mark. The byte order is kept as found (plain
            // `.utf16` would write the host's order back), and the encoder
            // writes the mark back.
            let encoding: String.Encoding = bytes[0] == 0xFF ? .utf16LittleEndian : .utf16BigEndian
            guard let text = String(data: data.dropFirst(2), encoding: encoding) else { throw CocoaError(.fileReadCorruptFile) }
            file = TextFile(text: text, encoding: encoding, hasBOM: true)
        } else {
            guard !looksBinary(data) else { throw CocoaError(.fileReadCorruptFile) }
            if let utf8 = String(data: data, encoding: .utf8) {
                file = TextFile(text: utf8, encoding: .utf8, hasBOM: bytes == utf8BOM)
            } else {
                var converted: NSString?
                var lossy = ObjCBool(false)
                let raw = NSString.stringEncoding(
                    for: data, encodingOptions: [.allowLossyKey: false], convertedString: &converted, usedLossyConversion: &lossy
                )
                guard raw != 0, let converted, !lossy.boolValue else {
                    throw CocoaError(.fileReadInapplicableStringEncoding)
                }
                file = TextFile(text: converted as String, encoding: String.Encoding(rawValue: raw))
            }
        }
        if file.text.hasPrefix("\u{FEFF}") { file.text.removeFirst() }
        file.lineEnding = dominantLineEnding(file.text)
        if file.text.utf8.contains(0x0D) {
            file.text = file.text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        }
        return file
    }

    /// `text` (with `\n` breaks) in this file's encoding, mark and breaks.
    func encode(_ text: String) throws -> Data {
        let output = lineEnding == "\n" ? text : text.replacingOccurrences(of: "\n", with: lineEnding)
        if let data = output.data(using: encoding) {
            guard hasBOM else { return data }
            switch encoding {
            case .utf8: return Data(Self.utf8BOM) + data
            case .utf16LittleEndian: return Data([0xFF, 0xFE]) + data
            case .utf16BigEndian: return Data([0xFE, 0xFF]) + data
            default: return data
            }
        }
        // A character the old encoding can't hold: UTF-8 rather than loss.
        guard let data = output.data(using: .utf8) else { throw CocoaError(.fileWriteInapplicableStringEncoding) }
        return data
    }

    /// NUL bytes, or many control characters, in the first 8 KB.
    static func looksBinary(_ data: Data) -> Bool {
        let head = data.prefix(8192)
        guard !head.isEmpty else { return false }
        var controls = 0
        for byte in head {
            if byte == 0 { return true }
            if byte < 0x20 && byte != 0x09 && byte != 0x0A && byte != 0x0D && byte != 0x0C && byte != 0x1B { controls += 1 }
        }
        return controls * 20 > head.count
    }

    /// The most common break, so a single stray CRLF in an LF file
    /// doesn't turn every line of it into CRLF on save.
    static func dominantLineEnding(_ text: String) -> String {
        var crlf = 0, lf = 0, cr = 0
        var previousCR = false
        for byte in text.utf8 {
            if byte == 0x0A {
                if previousCR { crlf += 1; cr -= 1 } else { lf += 1 }
            } else if byte == 0x0D {
                cr += 1
            }
            previousCR = byte == 0x0D
        }
        if crlf > lf && crlf >= cr { return "\r\n" }
        if cr > lf && cr > crlf { return "\r" }
        return "\n"
    }
}
