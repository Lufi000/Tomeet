import Foundation
import Testing
@testable import Tomeet

struct ReaderLocationTests {
    @Test func encodeDecodeRoundTrip() {
        let location = ReaderLocation(chapterIndex: 3, charOffset: 4821)
        #expect(location.encoded == "3:4821")
        #expect(ReaderLocation(encoded: location.encoded) == location)
        #expect(ReaderLocation(encoded: "0:0") == ReaderLocation(chapterIndex: 0, charOffset: 0))
    }

    @Test func decodeRejectsMalformed() {
        #expect(ReaderLocation(encoded: "") == nil)
        #expect(ReaderLocation(encoded: ":") == nil)
        #expect(ReaderLocation(encoded: "3:") == nil)
        #expect(ReaderLocation(encoded: ":5") == nil)
        #expect(ReaderLocation(encoded: "a:5") == nil)
        #expect(ReaderLocation(encoded: "3:b") == nil)
        #expect(ReaderLocation(encoded: "-1:5") == nil)
        #expect(ReaderLocation(encoded: "3:-1") == nil)
        #expect(ReaderLocation(encoded: "3::2") == nil)
    }

    @Test func clampToBounds() {
        let lengths = [100, 200, 300]
        #expect(ReaderLocation(chapterIndex: 5, charOffset: 999)
            .clamped(chapterCount: 3, chapterLengths: lengths)
            == ReaderLocation(chapterIndex: 2, charOffset: 300))
        #expect(ReaderLocation(chapterIndex: 1, charOffset: 350)
            .clamped(chapterCount: 3, chapterLengths: lengths)
            == ReaderLocation(chapterIndex: 1, charOffset: 200))
        #expect(ReaderLocation(chapterIndex: 0, charOffset: 0).clamped(chapterCount: 3, chapterLengths: lengths)
            == ReaderLocation(chapterIndex: 0, charOffset: 0))
        #expect(ReaderLocation(chapterIndex: -2, charOffset: -7)
            .clamped(chapterCount: 3, chapterLengths: lengths)
            == ReaderLocation(chapterIndex: 0, charOffset: 0))
        #expect(ReaderLocation(chapterIndex: 2, charOffset: 300)
            .clamped(chapterCount: 0, chapterLengths: [])
            == ReaderLocation(chapterIndex: 0, charOffset: 0))
    }
}