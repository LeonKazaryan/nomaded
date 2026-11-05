import Foundation

/// A place name boiled down so that spellings, scripts and languages meet: plain Latin
/// letters, no case, accents or punctuation, and the letter pairs that languages write
/// differently collapsed. "Шымкент" and "Shymkent" are both "simkent", "Шейх" and "Sheikh"
/// both "seih", "Alma-Ata" "almaata".
///
/// The geo pipeline compiles this very file (Tools/GeoPipeline links to it): the bundled
/// city list is searched by keys made there, so they must come out the same as the query's.
enum CityKey {
    /// The whole name's key.
    static func key(_ name: String) -> String {
        words(name).joined()
    }

    /// Each word's key, in order: "Sharm el-Sheikh" → ["sarm", "el", "seih"].
    static func words(_ name: String) -> [String] {
        let latin = name.unicodeScalars.allSatisfy(\.isASCII) ? name : name.applyingTransform(toASCII, reverse: false) ?? name
        var words: [String] = []
        var word: [UInt8] = []
        for byte in latin.utf8 {
            switch byte {
            case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "0")...UInt8(ascii: "9"):
                word.append(byte)
            case UInt8(ascii: "A")...UInt8(ascii: "Z"):
                word.append(byte + 32)
            // Apostrophes join: "L'Aquila", and the soft sign Russian-Latin writes as one.
            case UInt8(ascii: "'"), UInt8(ascii: "`"):
                continue
            default:
                if !word.isEmpty { words.append(skeleton(word)) }
                word.removeAll(keepingCapacity: true)
            }
        }
        if !word.isEmpty { words.append(skeleton(word)) }
        return words
    }

    /// Cyrillic the way English writes it (BGN: "Шымкент" → "Shymkent", not ISO's "Šymkent"),
    /// every other script in Latin, then plain ASCII.
    private static let toASCII = StringTransform("Russian-Latin/BGN; Any-Latin; Latin-ASCII")

    /// Letter groups that one sound gets in different languages, longest first. "ye" and
    /// "yo" are how Russian-Latin writes е and ё after a vowel: "Боровое" is "Borovoye".
    private static let pairs: [(from: [UInt8], to: [UInt8])] = [
        ("shch", "s"), ("sch", "s"), ("tch", "c"), ("kh", "h"), ("sh", "s"), ("zh", "z"), ("ch", "c"), ("ye", "e"), ("yo", "o"),
        ("ts", "c"), ("tz", "c"), ("ph", "f"), ("ck", "k"),
    ].map { (Array($0.0.utf8), Array($0.1.utf8)) }

    /// One word: the pairs above, single letters that stand for one another ("y"/"j" → "i",
    /// "w" → "v", "q" → "k", "x" → "ks"), then no letter twice in a row ("Lauterbrunnen").
    private static func skeleton(_ word: [UInt8]) -> String {
        var out: [UInt8] = []
        out.reserveCapacity(word.count + 2)
        func append(_ bytes: [UInt8]) {
            for byte in bytes where out.last != byte { out.append(byte) }
        }
        var i = 0
        outer: while i < word.count {
            for (from, to) in pairs where word.count - i >= from.count && word[i..<(i + from.count)].elementsEqual(from) {
                append(to)
                i += from.count
                continue outer
            }
            switch word[i] {
            case UInt8(ascii: "y"), UInt8(ascii: "j"): append([UInt8(ascii: "i")])
            case UInt8(ascii: "w"): append([UInt8(ascii: "v")])
            case UInt8(ascii: "q"): append([UInt8(ascii: "k")])
            case UInt8(ascii: "x"): append([UInt8(ascii: "k"), UInt8(ascii: "s")])
            default: append([word[i]])
            }
            i += 1
        }
        return String(decoding: out, as: UTF8.self)
    }
}
