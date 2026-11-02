import XCTest
@testable import CueCore
final class TrackerTests: XCTestCase {
    let script = "Welcome to my presentation. Today we will explore the ocean and discover a whole new world together. Thank you for listening."
    func testPartialResultsAndPauses() {
        var t = WordTracker(script: script)
        XCTAssertEqual(t.follow("welcome to my presentation"), 4)
        XCTAssertEqual(t.follow("welcome to my presentation"), 4)
        XCTAssertEqual(t.follow("welcome to my presentation today we will"), 7)
        t.newUtterance()
        XCTAssertEqual(t.follow("explore the ocean"), 10)
    }
    func testOffScriptDoesNotRunAway() {
        var t = WordTracker(script: script)
        XCTAssertEqual(t.follow("something entirely unrelated bananas"), 0)
        XCTAssertEqual(t.follow("thank you for listening"), 21)
    }
    func testRevisionDoesNotRewindAndSeekWorks() {
        var t = WordTracker(script: script)
        t.follow("welcome to my presentation today we will")
        XCTAssertEqual(t.follow("welcome to my presentation"), 7)
        t.seek(0)
        XCTAssertEqual(t.follow("welcome to my"), 3)
    }
    func testUnicodeAndEmpty() {
        XCTAssertEqual(WordTracker(script: "Don’t forget café.").words.map(\.normalized), ["don't", "forget", "cafe"])
        var t = WordTracker(script: "")
        XCTAssertEqual(t.follow("hello"), 0)
    }
    func testSilenceGate() {
        var gate = VoiceGate()
        XCTAssertFalse(gate.update(rms: 0, time: 0, threshold: 0.01))
        XCTAssertTrue(gate.update(rms: 0.1, time: 1, threshold: 0.01))
        for n in 1...20 { _ = gate.update(rms: 0, time: 1 + Double(n) * 0.1, threshold: 0.01) }
        XCTAssertFalse(gate.update(rms: 0, time: 4, threshold: 0.01))
    }
}
