import Compression
import Foundation

enum GzipDecoder {
    static func decode(_ data: Data, expectedSize: Int, maximumSize: Int) throws -> Data {
        guard data.count >= 18,
              data[data.startIndex] == 0x1f,
              data[data.startIndex + 1] == 0x8b,
              data[data.startIndex + 2] == 0x08 else {
            throw BlocklistUpdateError.invalidGzip
        }

        let flags = data[data.startIndex + 3]
        guard flags & 0xe0 == 0, expectedSize > 0, expectedSize <= maximumSize else {
            throw BlocklistUpdateError.invalidGzip
        }

        var bodyStart = data.startIndex + 10
        do {
            if flags & 0x04 != 0 {
                guard bodyStart + 2 <= data.endIndex else { throw BlocklistUpdateError.invalidGzip }
                let extraLength = Int(data[bodyStart]) | (Int(data[bodyStart + 1]) << 8)
                bodyStart += 2 + extraLength
            }
            if flags & 0x08 != 0 { bodyStart = try skipCString(in: data, from: bodyStart) }
            if flags & 0x10 != 0 { bodyStart = try skipCString(in: data, from: bodyStart) }
            if flags & 0x02 != 0 { bodyStart += 2 }
        } catch {
            throw BlocklistUpdateError.invalidGzip
        }

        let trailerStart = data.endIndex - 8
        guard bodyStart < trailerStart else { throw BlocklistUpdateError.invalidGzip }
        let deflate = data.subdata(in: bodyStart..<trailerStart)
        var decoded = Data(count: expectedSize)
        let decodedCount = decoded.withUnsafeMutableBytes { destination in
            deflate.withUnsafeBytes { source in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!,
                    destination.count,
                    source.bindMemory(to: UInt8.self).baseAddress!,
                    source.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard decodedCount == expectedSize else { throw BlocklistUpdateError.invalidGzip }

        let expectedCRC = littleEndianUInt32(data, at: trailerStart)
        let expectedISize = littleEndianUInt32(data, at: trailerStart + 4)
        guard crc32(decoded) == expectedCRC, UInt32(decoded.count) == expectedISize else {
            throw BlocklistUpdateError.invalidGzip
        }
        return decoded
    }

    private static func skipCString(in data: Data, from start: Int) throws -> Int {
        guard start < data.endIndex else { throw BlocklistUpdateError.invalidGzip }
        guard let end = data[start...].firstIndex(of: 0) else { throw BlocklistUpdateError.invalidGzip }
        return end + 1
    }

    private static func littleEndianUInt32(_ data: Data, at index: Int) -> UInt32 {
        UInt32(data[index]) |
            (UInt32(data[index + 1]) << 8) |
            (UInt32(data[index + 2]) << 16) |
            (UInt32(data[index + 3]) << 24)
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0)
            }
        }
        return crc ^ 0xffffffff
    }
}
