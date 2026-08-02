import Foundation

/// A relation the user can browse: table, view, materialised view or foreign table.
public struct DatabaseObject: Equatable, Identifiable {
    public enum Kind: String, Equatable {
        case table = "r"
        case partitionedTable = "p"
        case view = "v"
        case materializedView = "m"
        case foreignTable = "f"

        /// Short marker shown in the sidebar.
        public var symbol: String {
            switch self {
            case .table: return "▤"
            case .partitionedTable: return "▥"
            case .view: return "◫"
            case .materializedView: return "◪"
            case .foreignTable: return "▧"
            }
        }

        public var label: String {
            switch self {
            case .table: return "table"
            case .partitionedTable: return "partitioned table"
            case .view: return "view"
            case .materializedView: return "materialized view"
            case .foreignTable: return "foreign table"
            }
        }
    }

    public var schema: String
    public var name: String
    public var kind: Kind
    /// Planner estimate from `pg_class.reltuples`; -1 when never analysed.
    public var estimatedRows: Int

    public var id: String { "\(schema).\(name)" }

    public init(schema: String, name: String, kind: Kind, estimatedRows: Int) {
        self.schema = schema
        self.name = name
        self.kind = kind
        self.estimatedRows = estimatedRows
    }
}

/// One column of a relation, as shown in the structure pane.
public struct ColumnDescription: Equatable, Identifiable {
    public var name: String
    public var type: String
    public var isNotNull: Bool
    public var defaultValue: String?
    public var isPrimaryKey: Bool

    public var id: String { name }

    public init(name: String, type: String, isNotNull: Bool, defaultValue: String?, isPrimaryKey: Bool) {
        self.name = name
        self.type = type
        self.isNotNull = isNotNull
        self.defaultValue = defaultValue
        self.isPrimaryKey = isPrimaryKey
    }
}

/// Introspection queries and the parsing of their results.
///
/// Kept separate from the connection so the parsing can be tested against
/// synthetic `QueryResult` values without a live server.
public extension Array where Element == ColumnDescription {
    /// Presents a relation's structure as an ordinary result set.
    ///
    /// Reusing the grid machinery means the structure pane gets the same column
    /// sizing, truncation and alignment as query output, for free.
    func asResult() -> QueryResult {
        // Ordered by how much a reader needs each field; the default expression is
        // both the longest and the least urgent, so it goes last.
        let columns = [
            ResultColumn(name: "column", typeOID: 25, typeName: "text"),
            ResultColumn(name: "type", typeOID: 25, typeName: "text"),
            ResultColumn(name: "key", typeOID: 25, typeName: "text"),
            ResultColumn(name: "nullable", typeOID: 25, typeName: "text"),
            ResultColumn(name: "default", typeOID: 25, typeName: "text")
        ]
        let rows: [[String?]] = map { column in
            [
                column.name,
                column.type,
                column.isPrimaryKey ? "pk" : "",
                column.isNotNull ? "not null" : "",
                column.defaultValue ?? ""
            ]
        }
        return QueryResult(columns: columns, rows: rows)
    }
}

public enum Catalog {
    /// Every user visible relation, ordered for display.
    public static let objectsSQL = """
        SELECT n.nspname AS schema,
               c.relname AS name,
               c.relkind::text AS kind,
               c.reltuples::bigint AS estimated_rows
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relkind IN ('r', 'p', 'v', 'm', 'f')
          AND n.nspname NOT IN ('pg_catalog', 'information_schema')
          AND n.nspname NOT LIKE 'pg_toast%'
          AND n.nspname NOT LIKE 'pg_temp%'
        ORDER BY n.nspname, c.relname
        """

    public static func parseObjects(_ result: QueryResult) -> [DatabaseObject] {
        let schemaIndex = result.columns.firstIndex { $0.name == "schema" }
        let nameIndex = result.columns.firstIndex { $0.name == "name" }
        let kindIndex = result.columns.firstIndex { $0.name == "kind" }
        let rowsIndex = result.columns.firstIndex { $0.name == "estimated_rows" }

        guard let schemaIndex, let nameIndex, let kindIndex else { return [] }

        return result.rows.compactMap { row in
            guard
                let schema = row[safe: schemaIndex] ?? nil,
                let name = row[safe: nameIndex] ?? nil,
                let kindCode = row[safe: kindIndex] ?? nil,
                let kind = DatabaseObject.Kind(rawValue: kindCode)
            else { return nil }

            let estimate = rowsIndex.flatMap { row[safe: $0] ?? nil }.flatMap(Double.init).map(Int.init) ?? -1
            return DatabaseObject(schema: schema, name: name, kind: kind, estimatedRows: estimate)
        }
    }

    /// Columns of one relation. `relation` must already be a quoted SQL literal
    /// holding the schema-qualified name, e.g. `'public.users'`.
    public static func columnsSQL(relationLiteral: String) -> String {
        """
        SELECT a.attname AS name,
               format_type(a.atttypid, a.atttypmod) AS type,
               a.attnotnull AS not_null,
               COALESCE(pg_get_expr(d.adbin, d.adrelid), '') AS default_value,
               EXISTS (
                   SELECT 1 FROM pg_index i
                   WHERE i.indrelid = a.attrelid AND i.indisprimary AND a.attnum = ANY (i.indkey)
               ) AS is_primary_key
        FROM pg_attribute a
        LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
        WHERE a.attrelid = \(relationLiteral)::regclass
          AND a.attnum > 0
          AND NOT a.attisdropped
        ORDER BY a.attnum
        """
    }

    public static func parseColumns(_ result: QueryResult) -> [ColumnDescription] {
        result.rows.compactMap { row in
            guard let name = row[safe: 0] ?? nil, let type = row[safe: 1] ?? nil else { return nil }
            let notNull = (row[safe: 2] ?? nil) == "t"
            let defaultValue = (row[safe: 3] ?? nil).flatMap { $0.isEmpty ? nil : $0 }
            let isPrimaryKey = (row[safe: 4] ?? nil) == "t"
            return ColumnDescription(
                name: name,
                type: type,
                isNotNull: notNull,
                defaultValue: defaultValue,
                isPrimaryKey: isPrimaryKey
            )
        }
    }
}

extension Array {
    /// Bounds-checked access, so a malformed or unexpected result set degrades
    /// into missing values rather than a crash.
    public subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
