import Foundation

struct FuzzyMatch: Equatable {
    var score: Int
    var indices: [Int]
}

/// Subsequence fuzzy match. Consecutive hits, word starts, and shorter names
/// rank higher so the launcher feels immediate without a dependency.
enum FuzzyMatcher {
    static func match(query: String, candidate: String) -> FuzzyMatch? {
        let queryChars = fold(query, dropWhitespace: true)
        if queryChars.isEmpty {
            return FuzzyMatch(score: 0, indices: [])
        }

        let original = Array(candidate)
        let folded = original.map { foldCharacter($0) }
        var queryIndex = 0
        var indices: [Int] = []
        indices.reserveCapacity(queryChars.count)
        var score = 0
        var run = 0
        var last = -2

        for index in folded.indices {
            if queryIndex == queryChars.count { break }
            guard folded[index] == queryChars[queryIndex] else { continue }

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

        guard queryIndex == queryChars.count else { return nil }
        if indices.count == folded.count {
            score += 48
        } else if let first = indices.first, let end = indices.last, end - first + 1 == indices.count {
            score += 16
        }
        score += max(0, 28 - folded.count)
        return FuzzyMatch(score: score, indices: indices)
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
