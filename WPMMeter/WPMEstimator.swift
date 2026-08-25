import Foundation

struct TimedWordBatch: Equatable, Sendable {
    let id: String
    let start: TimeInterval
    let end: TimeInterval
    let wordCount: Int
}

struct WPMEstimator: Sendable {
    static let evidenceHorizon: TimeInterval = 15
    static let minimumSpan: TimeInterval = 3
    static let minimumWords = 5
    static let unavailableAfter: TimeInterval = 5
    static let episodeEndsAfter: TimeInterval = 8
    static let plausibleRange = 40...1_000

    private(set) var batches: [TimedWordBatch] = []
    private(set) var lastWordTime: TimeInterval?

    mutating func replace(_ batch: TimedWordBatch) {
        guard batch.wordCount > 0, batch.end > batch.start else { return }
        batches.removeAll { existing in
            existing.id == batch.id || Self.rangesOverlap(existing, batch)
        }
        batches.append(batch)
        batches.sort { $0.start < $1.start }
        lastWordTime = max(lastWordTime ?? batch.end, batch.end)
        expireEvidence(relativeTo: batch.end)
    }

    mutating func replace(rangeStart: TimeInterval, rangeEnd: TimeInterval, with replacements: [TimedWordBatch]) {
        batches.removeAll { $0.start < rangeEnd && rangeStart < $0.end }
        for replacement in replacements where replacement.wordCount > 0 && replacement.end > replacement.start {
            batches.append(replacement)
        }
        batches.sort { $0.start < $1.start }
        if let newest = replacements.map(\.end).max() {
            lastWordTime = max(lastWordTime ?? newest, newest)
            expireEvidence(relativeTo: newest)
        }
    }

    mutating func value(at time: TimeInterval) -> Int? {
        guard let lastWordTime else { return nil }
        if time - lastWordTime >= Self.episodeEndsAfter {
            reset()
            return nil
        }
        guard time - lastWordTime < Self.unavailableAfter else { return nil }
        expireEvidence(relativeTo: lastWordTime)
        guard let first = batches.first, let last = batches.last else { return nil }

        let span = last.end - first.start
        let words = batches.reduce(0) { $0 + $1.wordCount }
        guard words >= Self.minimumWords, span >= Self.minimumSpan else { return nil }

        let estimate = Int((Double(words) / span * 60).rounded())
        return Self.plausibleRange.contains(estimate) ? estimate : nil
    }

    mutating func reset() {
        batches.removeAll(keepingCapacity: true)
        lastWordTime = nil
    }

    private mutating func expireEvidence(relativeTo time: TimeInterval) {
        let cutoff = time - Self.evidenceHorizon
        batches.removeAll { $0.end <= cutoff }
    }

    private static func rangesOverlap(_ lhs: TimedWordBatch, _ rhs: TimedWordBatch) -> Bool {
        lhs.start < rhs.end && rhs.start < lhs.end
    }
}
