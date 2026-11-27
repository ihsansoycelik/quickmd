import Foundation
import Testing
@testable import QuickMD

/// Bytes in, bytes out: what the user didn't touch must not change.
struct TextFileTests {
    func roundTrip(_ bytes: [UInt8]) throws -> [UInt8] {
        let file = try TextFile.decode(Data(bytes))
        return [UInt8](try file.encode(file.text))
    }

    @Test func utf8BOMIsKept() throws {
        let bytes: [UInt8] = [0xEF, 0xBB, 0xBF] + Array("# Hi\n".utf8)
        let file = try TextFile.decode(Data(bytes))
        #expect(file.text == "# Hi\n")
        #expect(try roundTrip(bytes) == bytes)
    }

    @Test func plainUTF8HasNoBOMAdded() throws {
        let bytes = Array("a\nb".utf8)
        #expect(try roundTrip(bytes) == bytes)
    }

    @Test func strayCRLFDoesNotConvertWholeFile() throws {
        let file = try TextFile.decode(Data("a\r\nb\nc\nd\n".utf8))
        #expect(file.lineEnding == "\n")
        #expect(file.text == "a\nb\nc\nd\n")
    }

    @Test func crlfFileStaysCRLF() throws {
        let bytes = Array("a\r\nb\r\n".utf8)
        #expect(try roundTrip(bytes) == bytes)
    }

    @Test func oldMacCR() throws {
        let file = try TextFile.decode(Data("a\rb\rc".utf8))
        #expect(file.lineEnding == "\r")
        #expect(file.text == "a\nb\nc")
    }

    @Test func utf16WithBOM() throws {
        let data = "Ünlü ✓\n".data(using: .utf16)!
        let file = try TextFile.decode(data)
        #expect(file.text == "Ünlü ✓\n")
        #expect(try TextFile.decode(try file.encode(file.text)).text == "Ünlü ✓\n")
    }

    @Test func utf16ByteOrderIsKept() throws {
        let text = "Ünlü ✓\r\n"
        for (mark, encoding) in [([UInt8(0xFE), 0xFF], String.Encoding.utf16BigEndian), ([0xFF, 0xFE], .utf16LittleEndian)] {
            let bytes = mark + [UInt8](text.data(using: encoding)!)
            let file = try TextFile.decode(Data(bytes))
            #expect(file.text == "Ünlü ✓\n")
            #expect(try roundTrip(bytes) == bytes)
        }
    }

    @Test func binaryIsRefused() {
        #expect(throws: (any Error).self) { try TextFile.decode(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D])) }
        var random = SystemRandomNumberGenerator()
        var refused = 0
        for _ in 0..<200 {
            let data = Data((0..<300).map { _ in UInt8.random(in: 0...255, using: &random) })
            if (try? TextFile.decode(data)) == nil { refused += 1 }
        }
        #expect(refused == 200)
    }

    @Test func latinFileKeepsItsEncoding() throws {
        let data = "Çağrı şöyle\n".data(using: .windowsCP1254)!
        let file = try TextFile.decode(data)
        #expect(file.text.contains("şöyle"))
        #expect(try file.encode(file.text) == data)
    }

    @Test func emptyFile() throws {
        #expect(try TextFile.decode(Data()).text == "")
    }
}
