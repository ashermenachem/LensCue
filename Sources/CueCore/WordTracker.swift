import Foundation

public struct ScriptWord: Sendable {
    public let text: String
    public let normalized: String
    public let range: NSRange
}

public struct WordTracker: Sendable {
    public private(set) var words: [ScriptWord] = []
    public private(set) var position = 0
    private var lastTranscript = ""
    public init(script: String) {
        let ns = script as NSString
        let regex = try! NSRegularExpression(pattern: "[\\p{L}\\p{N}]+(?:['’][\\p{L}\\p{N}]+)*")
        words = regex.matches(in: script, range: NSRange(location: 0, length: ns.length)).map {
            let text = ns.substring(with: $0.range)
            return ScriptWord(text: text, normalized: Self.normalize(text), range: $0.range)
        }
    }
    public static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US")).replacingOccurrences(of: "’", with: "'")
    }
    public mutating func seek(_ index: Int) { position = max(0, min(index, words.count)); lastTranscript = "" }
    public mutating func newUtterance() { lastTranscript = "" }
    @discardableResult public mutating func follow(_ transcript: String) -> Int {
        guard transcript != lastTranscript else { return position }
        lastTranscript = transcript
        let spoken = WordTracker(script: transcript).words.map(\.normalized)
        guard !spoken.isEmpty, !words.isEmpty else { return position }
        let tail = Array(spoken.suffix(10))
        var bestScore = 0.0
        var bestEnd = position
        // Search nearby, allowing missed words and recognition revisions without large jumps.
        for end in max(1, position - 10)...min(words.count, max(1, position + 65)) {
            var j = end - 1
            var matched = 0
            var misses = 0
            for token in tail.reversed() {
                if j >= 0 && words[j].normalized == token { matched += 1; j -= 1 }
                else if j > 0 && words[j-1].normalized == token { matched += 1; j -= 2; misses += 1 }
                else { misses += 1 }
            }
            let distance = abs(end - position)
            let score = Double(matched) * 3 - Double(misses) * 1.2 - Double(distance) * 0.025
            let required = tail.count == 1 ? (distance <= 4 ? 1 : 2) : 2
            if matched >= required && score > bestScore { bestScore = score; bestEnd = end }
        }
        // Partial transcripts can be revised; never rewind unless the reader explicitly seeks.
        if bestScore > 0 { position = max(position, bestEnd) }
        return position
    }
}

public struct VoiceGate: Sendable {
    public private(set) var level: Double = 0
    private var lastVoice: Double = -.infinity
    public init() {}
    public mutating func update(rms: Double, time: Double, threshold: Double) -> Bool {
        level = level * 0.55 + rms * 0.45
        if level > threshold { lastVoice = time }
        return time - lastVoice < 0.35
    }
}
