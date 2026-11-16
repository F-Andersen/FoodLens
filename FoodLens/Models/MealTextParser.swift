import Foundation

/// Reads nutrition numbers out of a free-text meal description, typed or dictated, for example
/// "Сніданок: вівсянка 50 г, лосось 140 г. Разом 740 ккал; Б 46 г, Ж 31 г, В 72 г, клітковина 10 г".
///
/// Only numbers the user actually wrote are taken; nothing is guessed from food names.
/// When the text has a total ("разом", "всього"…), values after it win; otherwise per-item values are added up.
enum MealTextParser {
    struct Result: Equatable, Sendable {
        var calories: Double?
        /// True when the energy was not written but computed from the macros (4/9/4).
        var caloriesFromMacros = false
        var protein: Double?
        var fat: Double?
        var carbs: Double?
        var fiber: Double?
        var grams: Double?
        var mealType: MealEntry.MealType?
        /// The description without the meal-type prefix and the nutrition summary.
        var name: String

        var hasNutrition: Bool { calories != nil || protein != nil || fat != nil || carbs != nil || fiber != nil }
    }

    enum Field: CaseIterable { case calories, protein, fat, carbs, fiber, grams }

    // MARK: Patterns

    private static let number = #"(\d{1,3}(?:[   ]\d{3})+(?![\d.,])|\d+(?:[.,]\d+)?)"#
    private static let approx = #"(?:~|≈|±|прибл\.?|близько|орієнтовно|приблизно)?\s*"#
    private static let sep = #"\s*[:=\-–—]?\s*"#

    private static func regex(_ pattern: String, caseInsensitive: Bool = true) -> NSRegularExpression {
        // Patterns are constants; a failure here is a programming error caught by the tests.
        try! NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
    }

    private static let wordStart = #"(?<![\p{L}\p{N}])"#
    private static let wordEnd = #"(?![\p{L}])"#

    private static let labelWords: [Field: String] = [
        .calories: #"(?:калорійн\p{L}*|калорі\p{L}*|енергі\p{L}*|ккал|kcal|calories)"#,
        .protein: #"(?:білк\p{L}*|білок|белк\p{L}*|белок|protein)"#,
        .fat: #"(?:жир\p{L}*|fat)"#,
        .carbs: #"(?:вуглевод\p{L}*|углевод\p{L}*|carbs?|carbohydrates?)"#,
        .fiber: #"(?:клітковин\p{L}*|клетчатк\p{L}*|fiber|fibre)"#,
        .grams: #"(?:вага\s+порції|вага|порція|вагою)"#
    ]

    /// Single capital letters are matched case-sensitively, so the preposition "в" is never read as carbohydrates.
    private static let labelLetters: [Field: String] = [.protein: "Б", .fat: "Ж", .carbs: "[ВУ]", .fiber: "К"]

    private static let units: [Field: String] = [
        .calories: #"(?:ккал|kcal|кал(?![\p{L}])|калорі\p{L}*)"#,
        .grams: #"\s*(?:г|гр|g)(?![\p{L}])"#
    ]

    private static func patterns(for field: Field) -> [NSRegularExpression] {
        var result: [NSRegularExpression] = []
        let unit = field == .calories ? "" : #"(?:\s*(?:г|гр|g)(?![\p{L}]))?"#
        if let words = labelWords[field] {
            result.append(regex(wordStart + words + wordEnd + sep + approx + number + unit))
        }
        if let letter = labelLetters[field] {
            result.append(regex(wordStart + letter + wordEnd + sep + approx + number + unit, caseInsensitive: false))
        }
        switch field {
        case .calories:
            result.append(regex(approx + number + #"\s*"# + units[.calories]!))
        case .protein, .fat, .carbs, .fiber:
            // "46 г білка"
            result.append(regex(number + #"\s*(?:г|гр|g)\s+"# + labelWords[field]!))
        case .grams:
            break
        }
        return result
    }

    private static let compiled: [Field: [NSRegularExpression]] =
        Dictionary(uniqueKeysWithValues: Field.allCases.map { ($0, patterns(for: $0)) })

    /// "Б/Ж/В 46/31/72", "БЖВ: 46 / 31 / 72", "БЖУ 46/31/72".
    private static let triple = regex(wordStart + #"(?:Б\s*/?\s*Ж\s*/?\s*[ВУ])"# + sep
                                      + number + #"\s*(?:г)?\s*/\s*"# + number + #"\s*(?:г)?\s*/\s*"# + number,
                                      caseInsensitive: false)

    private static let totalKeyword = regex(wordStart + #"(?:разом|всього|усього|загалом|сумарно|в\s+сумі|итого|всего|total)"# + wordEnd)

    private static let mealPrefix = regex(#"^\s*(сніданок|обід|вечеря|перекус|полуденок|завтрак|ужин|обед)\s*[:\-–—,.]\s*"#)

    // MARK: Parsing

    static func parse(_ text: String) -> Result {
        let ns = text as NSString
        let whole = NSRange(location: 0, length: ns.length)
        var result = Result(name: text.trimmingCharacters(in: .whitespacesAndNewlines))
        var spans: [NSRange] = []

        if let match = mealPrefix.firstMatch(in: text, range: whole) {
            let word = ns.substring(with: match.range(at: 1)).lowercased()
            result.mealType = switch word {
            case "сніданок", "завтрак": .breakfast
            case "обід", "обед": .lunch
            case "вечеря", "ужин": .dinner
            default: .snack
            }
            spans.append(match.range)
        }

        let totalStart = totalKeyword.matches(in: text, range: whole).last?.range.location
        let tripleRange = triple.matches(in: text, range: whole).last?.range

        func values(_ field: Field) -> Double? {
            var found: [(location: Int, value: Double, range: NSRange)] = []
            for pattern in compiled[field] ?? [] {
                for match in pattern.matches(in: text, range: whole) {
                    let numberRange = match.range(at: 1)
                    guard numberRange.location != NSNotFound,
                          let value = Self.value(ns.substring(with: numberRange)) else { continue }
                    // Numbers inside "Б/Ж/В 35/12/60" belong to the triple only.
                    if let tripleRange, NSIntersectionRange(tripleRange, match.range).length > 0 { continue }
                    // The same number found by two patterns counts once.
                    if found.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) { continue }
                    found.append((numberRange.location, value, match.range))
                }
            }
            if field == .protein || field == .fat || field == .carbs, let triple = tripleValues(field) {
                found.append(triple)
            }
            guard !found.isEmpty else { return nil }
            spans.append(contentsOf: found.map(\.range))
            if let totalStart, let total = found.filter({ $0.location > totalStart }).min(by: { $0.location < $1.location }) {
                return total.value
            }
            return field == .grams ? found.last?.value : found.reduce(0) { $0 + $1.value }
        }

        func tripleValues(_ field: Field) -> (location: Int, value: Double, range: NSRange)? {
            guard let match = triple.matches(in: text, range: whole).last else { return nil }
            let group = field == .protein ? 1 : field == .fat ? 2 : 3
            guard let value = Self.value(ns.substring(with: match.range(at: group))) else { return nil }
            return (match.range(at: group).location, value, match.range)
        }

        result.calories = values(.calories)
        result.protein = values(.protein)
        result.fat = values(.fat)
        result.carbs = values(.carbs)
        result.fiber = values(.fiber)
        result.grams = values(.grams)

        if result.calories == nil, let p = result.protein, let f = result.fat, let c = result.carbs {
            result.calories = (p * MacroEnergy.protein + f * MacroEnergy.fat + c * MacroEnergy.carbs).rounded()
            result.caloriesFromMacros = true
        }
        result.name = cleanedName(text, removing: spans, totalStart: totalStart)
        return result
    }

    /// Accepts "46", "46,5", "46.5" and "1 200".
    static func value(_ raw: String) -> Double? {
        let digits = raw.replacingOccurrences(of: "[ \u{00A0}\u{202F}]", with: "", options: .regularExpression)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(digits), value.isFinite, value >= 0, value < 100_000 else { return nil }
        return value
    }

    /// Drops the meal prefix and every sentence that carries the nutrition numbers, keeping the food description.
    /// If the numbers sit inside the only sentence ("Борщ 300 ккал"), only the matched parts are removed.
    private static func cleanedName(_ text: String, removing spans: [NSRange], totalStart: Int?) -> String {
        let ns = text as NSString
        guard !spans.isEmpty else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        var keep = Array(repeating: true, count: ns.length)
        let prefix = spans.first { $0.location == 0 && mealPrefix.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))?.range == $0 }
        if let prefix { for i in prefix.location..<NSMaxRange(prefix) { keep[i] = false } }

        let nutritionSpans = spans.filter { $0 != prefix }
        let sentences = sentenceRanges(in: ns)
        var removedSentence = false
        for sentence in sentences {
            let carriesNumbers = nutritionSpans.contains { NSIntersectionRange($0, sentence).length > 0 }
                || (totalStart.map { NSLocationInRange($0, sentence) } ?? false)
            guard carriesNumbers else { continue }
            let othersKept = sentences.contains { other in
                other != sentence && !nutritionSpans.contains { NSIntersectionRange($0, other).length > 0 }
                    && !(totalStart.map { NSLocationInRange($0, other) } ?? false)
                    && !ns.substring(with: other).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).isEmpty
            }
            if othersKept {
                for i in sentence.location..<NSMaxRange(sentence) { keep[i] = false }
                removedSentence = true
            }
        }
        if !removedSentence {
            for span in nutritionSpans { for i in span.location..<NSMaxRange(span) { keep[i] = false } }
        }

        var chars: [unichar] = []
        for i in 0..<ns.length where keep[i] { chars.append(ns.character(at: i)) }
        var name = String(utf16CodeUnits: chars, count: chars.count)
        name = name.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([,.;])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"([,;])\s*(?=[,;.]|$)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;:-–—")))
        if let first = name.first, first.isLowercase { name = first.uppercased() + name.dropFirst() }
        return name.isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines) : name
    }

    /// Sentences end at ". ", "; " or the end of the text. Decimal points such as "2.5" do not split.
    private static func sentenceRanges(in text: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var start = 0
        let length = text.length
        var i = 0
        while i < length {
            let c = text.character(at: i)
            let isEnd = (c == 0x2E || c == 0x3B || c == 0x21 || c == 0x3F)
                && (i + 1 == length || CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(text.character(at: i + 1)) ?? " "))
            if isEnd {
                ranges.append(NSRange(location: start, length: i + 1 - start))
                start = i + 1
            }
            i += 1
        }
        if start < length { ranges.append(NSRange(location: start, length: length - start)) }
        return ranges
    }
}

/// Fills form fields from parsed text without overwriting what the user typed by hand:
/// a field is updated only while it is empty or still holds the value the parser put there.
struct AutoFillTracker: Equatable, Sendable {
    private var applied: [MealTextParser.Field: Double] = [:]
    private(set) var mealType: MealEntry.MealType?

    /// Returns the value the field should take now.
    mutating func update(_ field: MealTextParser.Field, current: Double, parsed: Double?) -> Double {
        let previous = applied[field]
        let untouched = current == 0 || current == previous
        guard untouched else { return current }
        if let parsed {
            applied[field] = parsed
            return parsed
        }
        // The number was deleted from the text: clear the value the parser had filled.
        if previous != nil, current == previous {
            applied[field] = nil
            return 0
        }
        return current
    }

    mutating func updateMealType(current: MealEntry.MealType, initial: MealEntry.MealType,
                                 parsed: MealEntry.MealType?) -> MealEntry.MealType {
        guard current == initial || current == mealType else { return current }
        guard let parsed else {
            if let previous = mealType, current == previous { mealType = nil; return initial }
            return current
        }
        mealType = parsed
        return parsed
    }
}
