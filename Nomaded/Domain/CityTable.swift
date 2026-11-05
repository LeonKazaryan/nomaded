import Foundation

/// The city list's file, `cities.nmcity`: every city in a fixed-size record, its names, and
/// a sorted index of name keys (`CityKey`), compressed with LZFSE. It's read in place:
/// opening it is one decompression, with no parsing, and a search is a binary search over
/// the keys. The geo pipeline writes it with `encode`, compiling this very file.
///
/// Layout after decompression, little-endian:
///
///     header     "NMCT", version, cities, regions, countries, entries    (u32 each)
///     cities     name, nameRu: u32 · latitude, longitude: f32 · population: u32 ·
///                region: u16 · country: u8 · fame << 1 | capital: u8   (24 bytes)
///     regions    name, nameRu: u32                                       (8 bytes)
///     countries  code: 2 × u8 · first city: u32                          (6 bytes)
///     entries    key: u32 · city: u32, top bit set when the key starts
///                at a later word of the name ("york" in "New York")      (8 bytes)
///     text       NUL-terminated UTF-8: names, region names, keys
///
/// Cities are grouped by country, each country's capital first, then biggest first.
/// Entries are sorted by key. Names and keys are offsets into `text`.
struct CityTable: Sendable {
    struct Region: Hashable, Sendable {
        var name: String
        var nameRu: String?
    }

    /// A city as the pipeline (or a test) hands it over.
    struct Row: Sendable {
        var name: String
        var nameRu: String?
        /// More names it's found by: native, older, other spellings. Not shown.
        var aliases: [String]
        var region: Region?
        var countryCode: String
        var latitude: Double
        var longitude: Double
        var population: Int
        var isCapital: Bool
        /// How many languages name it, up to 127: Amalfi in Italy beats the bigger Amalfi in
        /// Colombia, which few outside it know.
        var fame = 0
    }

    private static let magic = Array("NMCT".utf8)
    private static let version: UInt32 = 1
    private static let none = UInt32.max
    private static let laterWord: UInt32 = 1 << 31
    private static let cityStride = 24, regionStride = 8, countryStride = 6, entryStride = 8

    private let bytes: [UInt8]
    let count: Int
    private let regionCount: Int
    let entryCount: Int
    private let cityBase: Int, regionBase: Int, entryBase: Int, textBase: Int
    /// Country codes, by the index cities store.
    private let codes: [String]
    /// Cities of each country, as a range of indices.
    let countries: [String: Range<Int>]

    // MARK: - Reading

    init(compressed: Data) throws {
        guard let data = try? (compressed as NSData).decompressed(using: .lzfse) as Data else { throw CocoaError(.fileReadCorruptFile) }
        try self.init(bytes: [UInt8](data))
    }

    private init(bytes: [UInt8]) throws {
        guard bytes.count >= 24, Array(bytes[0..<4]) == Self.magic, Self.u32(bytes, 4) == Self.version else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.bytes = bytes
        count = Int(Self.u32(bytes, 8))
        regionCount = Int(Self.u32(bytes, 12))
        let countryCount = Int(Self.u32(bytes, 16))
        entryCount = Int(Self.u32(bytes, 20))
        cityBase = 24
        regionBase = cityBase + count * Self.cityStride
        let countryBase = regionBase + regionCount * Self.regionStride
        entryBase = countryBase + countryCount * Self.countryStride
        textBase = entryBase + entryCount * Self.entryStride
        guard textBase <= bytes.count else { throw CocoaError(.fileReadCorruptFile) }

        var codes: [String] = []
        var countries: [String: Range<Int>] = [:]
        for index in 0..<countryCount {
            let at = countryBase + index * Self.countryStride
            let first = Int(Self.u32(bytes, at + 2))
            let end = index + 1 < countryCount ? Int(Self.u32(bytes, at + Self.countryStride + 2)) : count
            let code = String(decoding: bytes[at..<(at + 2)], as: UTF8.self)
            codes.append(code)
            countries[code] = first..<end
        }
        self.codes = codes
        self.countries = countries
    }

    func name(_ city: Int) -> String { text(u32(cityBase + city * Self.cityStride)) }
    func nameRu(_ city: Int) -> String? { optionalText(u32(cityBase + city * Self.cityStride + 4)) }
    func latitude(_ city: Int) -> Double { Double(f32(cityBase + city * Self.cityStride + 8)) }
    func longitude(_ city: Int) -> Double { Double(f32(cityBase + city * Self.cityStride + 12)) }
    func population(_ city: Int) -> Int { Int(u32(cityBase + city * Self.cityStride + 16)) }
    func isCapital(_ city: Int) -> Bool { bytes[cityBase + city * Self.cityStride + 23] & 1 != 0 }
    func fame(_ city: Int) -> Int { Int(bytes[cityBase + city * Self.cityStride + 23] >> 1) }

    func countryCode(_ city: Int) -> String { codes[Int(bytes[cityBase + city * Self.cityStride + 22])] }

    /// The country as the file numbers them: cheaper to compare than its code.
    func countryIndex(of city: Int) -> Int { Int(bytes[cityBase + city * Self.cityStride + 22]) }

    /// The number a country goes by in `countryIndex(of:)`.
    func countryIndex(_ code: String) -> Int? { codes.firstIndex(of: code) }

    func region(_ city: Int) -> Region? {
        let at = cityBase + city * Self.cityStride + 20
        let index = Int(bytes[at]) | Int(bytes[at + 1]) << 8
        guard index != 0xFFFF, index < regionCount else { return nil }
        let base = regionBase + index * Self.regionStride
        return Region(name: text(u32(base)), nameRu: optionalText(u32(base + 4)))
    }

    /// An entry's city, and whether its key starts at a later word of the name.
    func entry(_ index: Int) -> (city: Int, isLaterWord: Bool) {
        let city = u32(entryBase + index * Self.entryStride + 4)
        return (Int(city & ~Self.laterWord), city & Self.laterWord != 0)
    }

    /// Whether an entry's key is `key` itself, not just a longer one starting with it.
    func entry(_ index: Int, isExactly key: [UInt8]) -> Bool {
        bytes[textBase + Int(u32(entryBase + index * Self.entryStride)) + key.count] == 0
    }

    /// Every entry whose key starts with `prefix`: its city, the city's country (as
    /// `countryIndex(of:)` numbers it), whether the key starts at a later word, and whether
    /// it's `prefix` exactly. One pass over raw memory: a letter or two match thousands.
    func forEachEntry(withPrefix prefix: [UInt8], _ body: (_ city: Int, _ country: Int, _ isLaterWord: Bool, _ isExact: Bool) -> Void) {
        let range = entries(withPrefix: prefix)
        guard !range.isEmpty else { return }
        bytes.withUnsafeBytes { raw in
            for index in range {
                let at = entryBase + index * Self.entryStride
                let city = UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: at + 4, as: UInt32.self))
                let key = Int(UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: at, as: UInt32.self)))
                let number = Int(city & ~Self.laterWord)
                body(number, Int(raw[cityBase + number * Self.cityStride + 22]), city & Self.laterWord != 0, raw[textBase + key + prefix.count] == 0)
            }
        }
    }

    /// The entries whose keys start with `prefix`.
    func entries(withPrefix prefix: [UInt8]) -> Range<Int> {
        func compare(_ index: Int) -> Int {
            var at = textBase + Int(u32(entryBase + index * Self.entryStride))
            for byte in prefix {
                let key = bytes[at]
                if key != byte { return key == 0 || key < byte ? -1 : 1 }
                at += 1
            }
            return 0
        }
        var low = 0, high = entryCount
        while low < high {
            let middle = (low + high) / 2
            if compare(middle) < 0 { low = middle + 1 } else { high = middle }
        }
        var end = low
        var top = entryCount
        while end < top {
            let middle = (end + top) / 2
            if compare(middle) == 0 { end = middle + 1 } else { top = middle }
        }
        return low..<end
    }

    private func text(_ offset: UInt32) -> String {
        let start = textBase + Int(offset)
        var end = start
        while bytes[end] != 0 { end += 1 }
        return String(decoding: bytes[start..<end], as: UTF8.self)
    }

    private func optionalText(_ offset: UInt32) -> String? {
        offset == Self.none ? nil : text(offset)
    }

    private func u32(_ at: Int) -> UInt32 { Self.u32(bytes, at) }
    private func f32(_ at: Int) -> Float { Float(bitPattern: u32(at)) }

    private static func u32(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
    }

    // MARK: - Writing

    /// The file for these cities: grouped by country, each country's capital first, then
    /// biggest first; every name and alias indexed by its key and by each later word's.
    static func encode(_ rows: [Row]) throws -> Data {
        // Down to the coordinates, so the same rows always make the same file.
        let rows = rows.sorted {
            ($0.countryCode, $0.isCapital ? 0 : 1, -$0.population, $0.name, $0.latitude, $0.longitude)
                < ($1.countryCode, $1.isCapital ? 0 : 1, -$1.population, $1.name, $1.latitude, $1.longitude)
        }
        var text: [UInt8] = []
        var strings: [String: UInt32] = [:]
        func intern(_ string: String) -> UInt32 {
            if let offset = strings[string] { return offset }
            let offset = UInt32(text.count)
            text += Array(string.utf8) + [0]
            strings[string] = offset
            return offset
        }

        var regions: [Region] = []
        var regionIndex: [Region: Int] = [:]
        let codes = Array(Set(rows.map(\.countryCode))).sorted()
        let countryIndex = Dictionary(uniqueKeysWithValues: codes.enumerated().map { ($1, $0) })
        guard codes.count <= 255, codes.allSatisfy({ $0.utf8.count == 2 }) else { throw CocoaError(.fileWriteInvalidFileName) }

        var cities: [UInt8] = []
        var entries: [(key: [UInt8], text: UInt32, city: UInt32)] = []
        for (index, row) in rows.enumerated() {
            var region = UInt16(0xFFFF)
            if let r = row.region {
                if regionIndex[r] == nil {
                    regionIndex[r] = regions.count
                    regions.append(r)
                }
                region = UInt16(regionIndex[r]!)
            }
            append32(&cities, intern(row.name))
            append32(&cities, row.nameRu.map(intern) ?? none)
            append32(&cities, Float(row.latitude).bitPattern)
            append32(&cities, Float(row.longitude).bitPattern)
            append32(&cities, UInt32(clamping: row.population))
            cities += [UInt8(region & 0xFF), UInt8(region >> 8), UInt8(countryIndex[row.countryCode]!), UInt8(min(row.fame, 127)) << 1 | (row.isCapital ? 1 : 0)]

            // Every spelling once as a whole name, then each later word that isn't one already.
            let names = ([row.name] + [row.nameRu].compactMap { $0 } + row.aliases).map { CityKey.words($0).map { Array($0.utf8) } }
            var keys = Set<[UInt8]>()
            var later: [(key: [UInt8], text: UInt32)] = []
            for words in names {
                let key = words.flatMap { $0 }
                guard !key.isEmpty, keys.insert(key).inserted else { continue }
                let offset = intern(String(decoding: key, as: UTF8.self))
                entries.append((key, offset, UInt32(index)))
                var start = words.first?.count ?? 0
                for word in words.dropFirst() {
                    later.append((Array(key[start...]), offset + UInt32(start)))
                    start += word.count
                }
            }
            var seen = keys
            for suffix in later where seen.insert(suffix.key).inserted {
                entries.append((suffix.key, suffix.text, UInt32(index) | laterWord))
            }
        }
        entries.sort { $0.key == $1.key ? $0.city < $1.city : $0.key.lexicographicallyPrecedes($1.key) }

        var out = magic
        for value in [version, UInt32(rows.count), UInt32(regions.count), UInt32(codes.count), UInt32(entries.count)] { append32(&out, value) }
        out += cities
        for region in regions {
            append32(&out, intern(region.name))
            append32(&out, region.nameRu.map(intern) ?? none)
        }
        let sizes = Dictionary(grouping: rows, by: \.countryCode).mapValues(\.count)
        var first = 0
        for code in codes {
            out += Array(code.utf8)
            append32(&out, UInt32(first))
            first += sizes[code] ?? 0
        }
        for entry in entries {
            append32(&out, entry.text)
            append32(&out, entry.city)
        }
        out += text
        guard let compressed = try? (Data(out) as NSData).compressed(using: .lzfse) as Data else { throw CocoaError(.fileWriteUnknown) }
        return compressed
    }

    private static func append32(_ bytes: inout [UInt8], _ value: UInt32) {
        bytes += [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 24)]
    }
}
