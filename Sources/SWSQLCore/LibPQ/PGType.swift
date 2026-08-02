import Foundation

/// Built-in type OIDs.
///
/// Only the stable, built-in OIDs are hard coded here. Anything else - extension
/// types, domains, user defined enums and composites - is resolved from
/// `pg_type` at runtime and cached, so swsql never has to guess.
public enum PGType {
    public static let names: [UInt32: String] = [
        16: "bool",
        17: "bytea",
        18: "char",
        19: "name",
        20: "int8",
        21: "int2",
        23: "int4",
        24: "regproc",
        25: "text",
        26: "oid",
        114: "json",
        142: "xml",
        600: "point",
        601: "lseg",
        602: "path",
        603: "box",
        604: "polygon",
        628: "line",
        700: "float4",
        701: "float8",
        718: "circle",
        790: "money",
        829: "macaddr",
        869: "inet",
        650: "cidr",
        1000: "_bool",
        1001: "_bytea",
        1005: "_int2",
        1007: "_int4",
        1009: "_text",
        1015: "_varchar",
        1016: "_int8",
        1021: "_float4",
        1022: "_float8",
        1042: "bpchar",
        1043: "varchar",
        1082: "date",
        1083: "time",
        1114: "timestamp",
        1184: "timestamptz",
        1186: "interval",
        1266: "timetz",
        1560: "bit",
        1562: "varbit",
        1700: "numeric",
        2249: "record",
        2950: "uuid",
        2951: "_uuid",
        3220: "pg_lsn",
        3614: "tsvector",
        3615: "tsquery",
        3802: "jsonb",
        3807: "_jsonb",
        3904: "int4range",
        3906: "numrange",
        3908: "tsrange",
        3910: "tstzrange",
        3912: "daterange",
        3926: "int8range"
    ]

    private static let numericOIDs: Set<UInt32> = [
        20,  // int8
        21,  // int2
        23,  // int4
        26,  // oid
        700, // float4
        701, // float8
        790, // money
        1700 // numeric
    ]

    public static func isNumeric(oid: UInt32) -> Bool {
        numericOIDs.contains(oid)
    }

    /// Name for a well known OID, or `nil` when it needs a catalog lookup.
    public static func name(for oid: UInt32) -> String? {
        names[oid]
    }
}
