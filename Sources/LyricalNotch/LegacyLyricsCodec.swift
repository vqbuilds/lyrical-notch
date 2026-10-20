import Foundation
import zlib

// QRC protocol tables and word byte order adapted from WXRIW/QQMusicDecoder (MIT).
// Full attribution: docs/QQMusicDecoder-LICENSE.txt. No LDDC implementation is bundled.
enum LegacyLyricsCodec {
    static func inflate(_ bytes: [UInt8]) -> String? {
        guard !bytes.isEmpty, bytes.count <= 2_000_000 else { return nil }
        var output = [UInt8](repeating: 0, count: 2_000_000)
        var length = uLongf(output.count)
        guard uncompress(&output, &length, bytes, uLong(bytes.count)) == Z_OK else { return nil }
        return String(bytes: output.prefix(Int(length)), encoding: .utf8)
    }
    static func krc(_ data: Data) -> String? {
        guard data.starts(with: Array("krc1".utf8)), data.count <= 2_000_000 else { return nil }
        let key: [UInt8] = [64,71,97,119,94,50,116,71,81,54,49,45,206,210,110,105]
        return inflate(data.dropFirst(4).enumerated().map { $0.element ^ key[$0.offset % key.count] })
    }
    static func qrc(_ hex: String) -> String? {
        let chars = Array(hex.utf8)
        guard !chars.isEmpty, chars.count <= 1_000_000, chars.count % 16 == 0 else { return nil }
        var bytes: [UInt8] = []
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard let value = UInt8(String(bytes: chars[i..<i+2], encoding: .utf8) ?? "", radix: 16) else { return nil }
            bytes.append(value)
        }
        let key = Array("!@#)(*$%123ZXC!@!@#)(NHL".utf8)
        let schedules = [Array(keys(Array(key[16..<24])).reversed()), keys(Array(key[8..<16])), Array(keys(Array(key[0..<8])).reversed())]
        var result: [UInt8] = []
        for i in stride(from: 0, to: bytes.count, by: 8) {
            if Task.isCancelled { return nil }
            var block = Array(bytes[i..<i+8])
            for schedule in schedules { block = des(block, schedule) }
            result += block
        }
        return inflate(result)
    }
    private static func permute(_ value: UInt64, _ width: Int, _ table: [Int]) -> UInt64 {
        table.reduce(0) { ($0 << 1) | ((value >> (width - $1)) & 1) }
    }
    private static func swapped(_ bytes: [UInt8]) -> [UInt8] {
        [bytes[3],bytes[2],bytes[1],bytes[0],bytes[7],bytes[6],bytes[5],bytes[4]]
    }
    private static func keys(_ bytes: [UInt8]) -> [UInt64] {
        let raw = swapped(bytes).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let selected = permute(raw, 64, pc1)
        var c = selected >> 28, d = selected & 0xfffffff
        return [1,1,2,2,2,2,2,2,1,2,2,2,2,2,2,1].map { shift in
            c = ((c << shift) | (c >> (28-shift))) & 0xfffffff
            d = ((d << shift) | (d >> (28-shift))) & 0xfffffff
            // QRC intentionally shifts the D-half selection one bit versus standard DES.
            return (permute(c << 4, 32, Array(pc2.prefix(24))) << 24) | permute(d << 4, 32, pc2.suffix(24).map { $0 - 27 })
        }
    }
    private static func des(_ bytes: [UInt8], _ keys: [UInt64]) -> [UInt8] {
        let raw = swapped(bytes).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let initial = permute(raw, 64, ip)
        var left = initial >> 32, right = initial & 0xffffffff
        for key in keys {
            let expanded = permute(right, 32, expansion) ^ key
            var substituted: UInt64 = 0
            for i in 0..<8 {
                let six = Int((expanded >> (42-i*6)) & 63)
                let index = (six & 32) | ((six & 1) << 4) | ((six >> 1) & 15)
                substituted = (substituted << 4) | UInt64(boxes[i][index])
            }
            let next = left ^ permute(substituted, 32, permutation)
            left = right; right = next
        }
        let output = permute((right << 32) | left, 64, inverse)
        return swapped((0..<8).map { UInt8((output >> (56-$0*8)) & 255) })
    }
    private static let ip = (0..<8).flatMap { row in (0..<8).map { 58 + (row % 4)*2 - (row / 4) - $0*8 } }
    private static let inverse: [Int] = {
        var result = [Int](repeating: 0, count: 64)
        for (i, bit) in ip.enumerated() { result[bit-1] = i+1 }
        return result
    }()
    private static let expansion = [32,1,2,3,4,5,4,5,6,7,8,9,8,9,10,11,12,13,12,13,14,15,16,17,16,17,18,19,20,21,20,21,22,23,24,25,24,25,26,27,28,29,28,29,30,31,32,1]
    private static let permutation = [16,7,20,21,29,12,28,17,1,15,23,26,5,18,31,10,2,8,24,14,32,27,3,9,19,13,30,6,22,11,4,25]
    private static let pc1 = [57,49,41,33,25,17,9,1,58,50,42,34,26,18,10,2,59,51,43,35,27,19,11,3,60,52,44,36,63,55,47,39,31,23,15,7,62,54,46,38,30,22,14,6,61,53,45,37,29,21,13,5,28,20,12,4]
    private static let pc2 = [14,17,11,24,1,5,3,28,15,6,21,10,23,19,12,4,26,8,16,7,27,20,13,2,41,52,31,37,47,55,30,40,51,45,33,48,44,49,39,56,34,53,46,42,50,36,29,32]
    private static let boxes: [[Int]] = [[14, 4, 13, 1, 2, 15, 11, 8, 3, 10, 6, 12, 5, 9, 0, 7, 0, 15, 7, 4, 14, 2, 13, 1, 10, 6, 12, 11, 9, 5, 3, 8, 4, 1, 14, 8, 13, 6, 2, 11, 15, 12, 9, 7, 3, 10, 5, 0, 15, 12, 8, 2, 4, 9, 1, 7, 5, 11, 3, 14, 10, 0, 6, 13], [15, 1, 8, 14, 6, 11, 3, 4, 9, 7, 2, 13, 12, 0, 5, 10, 3, 13, 4, 7, 15, 2, 8, 15, 12, 0, 1, 10, 6, 9, 11, 5, 0, 14, 7, 11, 10, 4, 13, 1, 5, 8, 12, 6, 9, 3, 2, 15, 13, 8, 10, 1, 3, 15, 4, 2, 11, 6, 7, 12, 0, 5, 14, 9], [10, 0, 9, 14, 6, 3, 15, 5, 1, 13, 12, 7, 11, 4, 2, 8, 13, 7, 0, 9, 3, 4, 6, 10, 2, 8, 5, 14, 12, 11, 15, 1, 13, 6, 4, 9, 8, 15, 3, 0, 11, 1, 2, 12, 5, 10, 14, 7, 1, 10, 13, 0, 6, 9, 8, 7, 4, 15, 14, 3, 11, 5, 2, 12], [7, 13, 14, 3, 0, 6, 9, 10, 1, 2, 8, 5, 11, 12, 4, 15, 13, 8, 11, 5, 6, 15, 0, 3, 4, 7, 2, 12, 1, 10, 14, 9, 10, 6, 9, 0, 12, 11, 7, 13, 15, 1, 3, 14, 5, 2, 8, 4, 3, 15, 0, 6, 10, 10, 13, 8, 9, 4, 5, 11, 12, 7, 2, 14], [2, 12, 4, 1, 7, 10, 11, 6, 8, 5, 3, 15, 13, 0, 14, 9, 14, 11, 2, 12, 4, 7, 13, 1, 5, 0, 15, 10, 3, 9, 8, 6, 4, 2, 1, 11, 10, 13, 7, 8, 15, 9, 12, 5, 6, 3, 0, 14, 11, 8, 12, 7, 1, 14, 2, 13, 6, 15, 0, 9, 10, 4, 5, 3], [12, 1, 10, 15, 9, 2, 6, 8, 0, 13, 3, 4, 14, 7, 5, 11, 10, 15, 4, 2, 7, 12, 9, 5, 6, 1, 13, 14, 0, 11, 3, 8, 9, 14, 15, 5, 2, 8, 12, 3, 7, 0, 4, 10, 1, 13, 11, 6, 4, 3, 2, 12, 9, 5, 15, 10, 11, 14, 1, 7, 6, 0, 8, 13], [4, 11, 2, 14, 15, 0, 8, 13, 3, 12, 9, 7, 5, 10, 6, 1, 13, 0, 11, 7, 4, 9, 1, 10, 14, 3, 5, 12, 2, 15, 8, 6, 1, 4, 11, 13, 12, 3, 7, 14, 10, 15, 6, 8, 0, 5, 9, 2, 6, 11, 13, 8, 1, 4, 10, 7, 9, 5, 0, 15, 14, 2, 3, 12], [13, 2, 8, 4, 6, 15, 11, 1, 10, 9, 3, 14, 5, 0, 12, 7, 1, 15, 13, 8, 10, 3, 7, 4, 12, 5, 6, 11, 0, 14, 9, 2, 7, 11, 4, 1, 9, 12, 14, 2, 0, 6, 10, 13, 15, 3, 5, 8, 2, 1, 14, 7, 4, 10, 8, 13, 15, 12, 9, 0, 3, 5, 6, 11]]
}
