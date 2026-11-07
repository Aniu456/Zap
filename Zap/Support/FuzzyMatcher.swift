import Foundation

struct FuzzyMatch: Equatable {
    var score: Int
    var indices: [Int]
}

/// Subsequence match, plus a short edit-distance fallback so a nearby typo
/// ("Xocode") still finds the intended name. Case and extra spaces are ignored.
enum FuzzyMatcher {
    static func match(query: String, candidate: String) -> FuzzyMatch? {
        let queryChars = fold(query, dropWhitespace: true)
        if queryChars.isEmpty {
            return FuzzyMatch(score: 0, indices: [])
        }

        let original = Array(candidate)
        let folded = original.map { foldCharacter($0) }
        if let subsequence = subsequenceMatch(query: queryChars, original: original, folded: folded) {
            return subsequence
        }
        return typoMatch(query: queryChars, candidate: folded)
    }

    private static func subsequenceMatch(query: [Character], original: [Character], folded: [Character]) -> FuzzyMatch? {
        var queryIndex = 0
        var indices: [Int] = []
        indices.reserveCapacity(query.count)
        var score = 0
        var run = 0
        var last = -2

        for index in folded.indices {
            if queryIndex == query.count { break }
            guard folded[index] == query[queryIndex] else { continue }

            var gain = 2
            if index == 0 {
                gain += 18
            } else if isBoundary(original, index) {
                gain += 12
            }
            if last == index - 1 {
                run += 1
                gain += 8 + run * 2
            } else {
                run = 0
                if last >= 0 {
                    gain -= min(6, index - last - 1)
                }
            }
            score += gain
            indices.append(index)
            last = index
            queryIndex += 1
        }

        guard queryIndex == query.count else { return nil }
        if indices.count == folded.count {
            score += 48
        } else if let first = indices.first, let end = indices.last, end - first + 1 == indices.count {
            score += 16
        }
        score += max(0, 28 - folded.count)
        return FuzzyMatch(score: score, indices: indices)
    }

    /// Used only when the query is not a subsequence. One edit for short names,
    /// two once the query is long enough that a second slip is still "nearby".
    private static func typoMatch(query: [Character], candidate: [Character]) -> FuzzyMatch? {
        let limit = allowedEdits(query.count)
        guard limit > 0 else { return nil }
        let compact = candidate.filter { !$0.isWhitespace }
        guard !compact.isEmpty else { return nil }
        let distance = bestDistance(query: query, candidate: compact, limit: limit)
        guard distance <= limit else { return nil }
        var score = 70 - distance * 22
        if abs(compact.count - query.count) <= distance {
            score += 28
        }
        score += max(0, 16 - compact.count)
        return FuzzyMatch(score: max(1, score), indices: [])
    }

    private static func allowedEdits(_ count: Int) -> Int {
        switch count {
        case ..<3: return 0
        case 3...7: return 1
        default: return 2
        }
    }

    private static func bestDistance(query: [Character], candidate: [Character], limit: Int) -> Int {
        // Preserve whole-name scoring when its distance is already acceptable.
        if candidate.count <= query.count + limit {
            let direct = editDistance(query, candidate)
            if direct <= limit || candidate.count <= query.count { return direct }
        }

        // A zero-cost candidate prefix lets each column start a new substring.
        // Distances within the limit imply the same window lengths as the old
        // sliding-window search. Keep three columns for adjacent transpositions.
        var previous = Array(0...query.count)
        var current = previous
        var beforePrevious = previous
        var best = limit + 1
        for column in candidate.indices {
            current[0] = 0
            for row in 1...query.count {
                let cost = candidate[column] == query[row - 1] ? 0 : 1
                var distance = min(
                    previous[row] + 1,
                    current[row - 1] + 1,
                    previous[row - 1] + cost
                )
                if column > 0, row > 1,
                   candidate[column] == query[row - 2],
                   candidate[column - 1] == query[row - 1] {
                    distance = min(distance, beforePrevious[row - 2] + 1)
                }
                current[row] = distance
            }
            best = min(best, current[query.count])
            if best == 0 { return 0 }
            swap(&beforePrevious, &previous)
            swap(&current, &previous)
        }
        return best
    }

    /// Optimal string alignment: insert, delete, substitute, and adjacent transpose.
    private static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        let n = a.count
        let m = b.count
        if n == 0 { return m }
        if m == 0 { return n }
        var previous = Array(0...m)
        var current = Array(repeating: 0, count: m + 1)
        var beforePrevious = Array(repeating: 0, count: m + 1)
        for i in 1...n {
            current[0] = i
            let aIndex = i - 1
            for j in 1...m {
                let cost = a[aIndex] == b[j - 1] ? 0 : 1
                var value = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                if i > 1, j > 1, a[aIndex] == b[j - 2], a[aIndex - 1] == b[j - 1] {
                    value = min(value, beforePrevious[j - 2] + 1)
                }
                current[j] = value
            }
            beforePrevious = previous
            previous = current
        }
        return previous[m]
    }

    private static func fold(_ text: String, dropWhitespace: Bool) -> [Character] {
        var result: [Character] = []
        result.reserveCapacity(text.count)
        for character in text {
            if dropWhitespace && character.isWhitespace { continue }
            result.append(foldCharacter(character))
        }
        return result
    }

    private static func foldCharacter(_ character: Character) -> Character {
        let lowered = String(character).lowercased()
        return lowered.first ?? character
    }

    private static func isBoundary(_ characters: [Character], _ index: Int) -> Bool {
        guard index > 0 else { return true }
        let previous = characters[index - 1]
        if previous.isWhitespace || previous == "-" || previous == "_" || previous == "." || previous == "/" || previous == "(" {
            return true
        }
        return previous.isLowercase && characters[index].isUppercase
    }
}
