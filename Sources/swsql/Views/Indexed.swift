import Foundation

/// Pairs a value with a stable position so plain arrays can drive `ForEach`.
///
/// `enumerated()` produces tuples, and Swift has no key paths into tuples, so a
/// small wrapper is the tidiest way to give unidentifiable elements an identity.
struct Indexed<Value>: Identifiable {
    let id: Int
    let value: Value
}

extension Array {
    var indexed: [Indexed<Element>] {
        enumerated().map { Indexed(id: $0.offset, value: $0.element) }
    }
}
