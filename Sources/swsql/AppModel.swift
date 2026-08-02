import Combine
import Foundation
import SWSQLCore

/// All of the application's state, owned by the main queue.
///
/// Everything the UI renders is derived from these properties. `DatabaseService`
/// delivers its callbacks on the main queue, so no property here is ever touched
/// from the database thread.
final class AppModel: ObservableObject {
    enum ConnectionState: Equatable {
        /// No connection target chosen yet: the setup screen is asking for a URL.
        case unconfigured
        case connecting
        case connected(DatabaseService.ConnectionInfo)
        case failed(PostgresError)
    }

    /// Which pane occupies the main area.
    enum Pane: Equatable {
        case data
        case structure
        case rowDetail
        case history
        case help
    }

    enum StatusKind: Equatable {
        case info
        case success
        case failure
    }

    // MARK: - Connection

    @Published private(set) var connectionState: ConnectionState = .connecting

    // MARK: - Catalog

    @Published private(set) var objects: [DatabaseObject] = []
    @Published private(set) var objectFilter: String = ""
    @Published private(set) var selectedObject: DatabaseObject?
    @Published private(set) var structureColumns: [ColumnDescription] = []

    // MARK: - Query

    @Published private(set) var result: QueryResult?
    /// Preferred column widths for `result`, measured once when it arrives.
    /// Re-measuring on every redraw would mean re-scanning hundreds of rows just
    /// to move the cursor down one line.
    @Published private(set) var naturalColumnWidths: [Int] = []
    @Published private(set) var queryError: PostgresError?
    @Published private(set) var lastStatement: String = ""
    @Published private(set) var isRunning = false
    @Published private(set) var history: [String] = []

    // MARK: - Presentation

    @Published private(set) var pane: Pane = .data
    @Published private(set) var status: String = "connecting…"
    @Published private(set) var statusKind: StatusKind = .info

    /// First row of the page currently built into the grid.
    ///
    /// A page is exactly one screenful. Building every row of a large result would
    /// not scale, and a page taller than the screen would mean pressing ↓ dozens of
    /// times to reach the buttons underneath the grid. One screenful keeps the
    /// controls a single keystroke below the last visible row.
    @Published private(set) var pageStart = 0
    /// Leftmost visible column of the result grid.
    @Published private(set) var columnOffset = 0

    /// Row the user last moved onto, as an index into `result.rows`.
    ///
    /// Deliberately not `@Published`. Moving between rows happens on every arrow
    /// key, and publishing it would rebuild the whole view tree each time just to
    /// restate where the cursor is. SwiftTUI already repaints the two rows whose
    /// highlight changed, which is the only visible difference.
    private(set) var focusedRow = 0


    /// Objects built into the sidebar at once. Beyond this the filter is the way
    /// to find something, rather than a control per relation in a large schema.
    static let objectListLimit = 400

    /// Rows the grid can draw, updated by the view from its measured height.
    private(set) var visibleRowCapacity = 10

    /// Objects shown in the sidebar after the filter is applied.
    var filteredObjects: [DatabaseObject] {
        guard !objectFilter.isEmpty else { return objects }
        let needle = objectFilter.lowercased()
        return objects.filter {
            $0.name.lowercased().contains(needle) || $0.schema.lowercased().contains(needle)
        }
    }

    var rowCount: Int { result?.rows.count ?? 0 }

    /// Rows built into the grid at once: one screenful.
    var pageSize: Int { visibleRowCapacity }

    /// Absolute indices of the rows currently built into the grid.
    var pageRange: Range<Int> {
        let end = min(pageStart + pageSize, rowCount)
        guard pageStart < end else { return 0..<0 }
        return pageStart..<end
    }

    var pageCount: Int {
        max(1, Int(ceil(Double(rowCount) / Double(pageSize))))
    }

    var pageNumber: Int {
        pageStart / pageSize + 1
    }

    var hasMorePages: Bool { rowCount > pageSize }

    // MARK: - Setup

    private let database: DatabaseService
    private let store: ConnectionStore

    /// Where to connect. Nil until the user pastes a URL on the setup screen.
    private var target: ConnectionTarget?

    /// The libpq environment/defaults target, used by the "environment defaults"
    /// escape hatch on the setup screen so the psql-style path stays reachable.
    private let environmentDefaults: ConnectionTarget

    /// The raw string the user pasted, held until the connection it describes
    /// actually succeeds - so a typo'd host is never persisted as if it worked.
    private var pendingSave: String?

    /// Rows fetched for a table preview. Enough to be useful, small enough to stay snappy.
    private let previewLimit = 500

    init(
        database: DatabaseService,
        store: ConnectionStore,
        target: ConnectionTarget?,
        environmentDefaults: ConnectionTarget
    ) {
        self.database = database
        self.store = store
        self.target = target
        self.environmentDefaults = environmentDefaults

        if target == nil {
            connectionState = .unconfigured
            setStatus("paste a PostgreSQL connection URL to begin", kind: .info)
        }
    }

    // MARK: - Choosing a connection

    /// Accepts a pasted connection URL (a `postgres://` URI, a libpq keyword
    /// string, or a bare database name), then connects. The string is remembered
    /// for next launch only once the connection it describes succeeds.
    func configure(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            setStatus("paste a connection URL, e.g. postgres://user@host:5432/dbname", kind: .failure)
            return
        }

        let parsed: ConnectionTarget.Invocation
        do {
            parsed = try ConnectionTarget.parse(arguments: [trimmed])
        } catch let error as ConnectionTarget.ParseError {
            setStatus(error.description, kind: .failure)
            return
        } catch {
            setStatus("\(error)", kind: .failure)
            return
        }

        switch parsed {
        case .connect(let target), .connectUsingDefaults(let target):
            self.target = target
            self.pendingSave = trimmed
            start()
        case .help, .version:
            setStatus("that does not look like a connection URL", kind: .failure)
        }
    }

    /// Connects the psql way, via libpq's own environment and defaults, without
    /// saving anything. Reached by submitting an empty URL on the setup screen.
    func useEnvironmentDefaults() {
        target = environmentDefaults
        pendingSave = nil
        start()
    }

    /// Returns to the setup screen to enter a different URL, e.g. to fix a wrong host.
    func reconfigure() {
        guard !isRunning else {
            setStatus("a statement is already running - cancel it first", kind: .failure)
            return
        }
        pendingSave = nil
        connectionState = .unconfigured
        setStatus("paste a PostgreSQL connection URL", kind: .info)
    }

    var isDisconnected: Bool {
        if case .failed = connectionState { return true }
        return false
    }

    /// Opens the connection, or opens it again after the server went away.
    ///
    /// A long lived client outlives server restarts, failovers and idle timeouts,
    /// so losing the connection has to be recoverable without restarting swsql.
    func start() {
        guard let target else { return }
        guard !isRunning else { return }
        connectionState = .connecting
        result = nil
        naturalColumnWidths = []
        queryError = nil
        setStatus("connecting…", kind: .info)

        database.connect(to: target) { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .success(let info):
                self.connectionState = .connected(info)
                self.setStatus("connected to \(info.database) (server \(info.serverVersion))\(self.persistPendingURL())", kind: .success)
                self.reloadObjects()
            case .failure(let error):
                self.connectionState = .failed(error)
                self.setStatus(error.summary, kind: .failure)
            }
        }
    }

    /// Saves the pasted URL now that it has proven it can connect. Returns a note
    /// to append to the status line: empty when there was nothing to save, or a
    /// warning if the save itself failed - a save failure must not lose the
    /// working connection the user already has.
    private func persistPendingURL() -> String {
        guard let pending = pendingSave else { return "" }
        pendingSave = nil
        do {
            try store.save(pending)
            return ""
        } catch {
            return "  ·  could not save the URL: \(error.localizedDescription)"
        }
    }

    // MARK: - Catalog

    func reloadObjects() {
        database.execute(Catalog.objectsSQL) { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .success(let result):
                self.objects = Catalog.parseObjects(result)
                if self.objects.isEmpty {
                    self.setStatus("no user tables or views in this database", kind: .info)
                }
            case .failure(let error):
                self.setStatus("could not list objects: \(error.summary)", kind: .failure)
            }
        }
    }

    func setObjectFilter(_ text: String) {
        objectFilter = text.trimmingCharacters(in: .whitespaces)
        let matches = filteredObjects.count
        if objectFilter.isEmpty {
            setStatus("filter cleared - \(objects.count) objects", kind: .info)
        } else {
            setStatus("\(matches) \(matches == 1 ? "object matches" : "objects match") \"\(objectFilter)\"", kind: matches == 0 ? .failure : .info)
        }
    }

    /// Selects an object by its schema-qualified name.
    ///
    /// SwiftTUI builds a button's action once and never refreshes it, so an action
    /// that captured a position would keep pointing at whatever was in that
    /// position when the button was first created. Resolving by identifier here
    /// keeps the behaviour correct as the list is filtered and reloaded.
    func selectObject(id: String) {
        guard let object = objects.first(where: { $0.id == id }) else { return }
        select(object)
    }

    /// Loads a preview of the relation and its column definitions.
    func select(_ object: DatabaseObject) {
        guard !isRunning else {
            setStatus("a statement is already running - cancel it first", kind: .failure)
            return
        }
        selectedObject = object
        structureColumns = []

        let relation = "\(object.schema).\(object.name)"
        let limit = previewLimit

        beginRun(describedAs: "SELECT * FROM \(relation) LIMIT \(limit)")

        database.perform({ connection -> (QueryResult, [ColumnDescription]) in
            let qualified = "\(connection.quoteIdentifier(object.schema)).\(connection.quoteIdentifier(object.name))"
            let rows = try connection.execute("SELECT * FROM \(qualified) LIMIT \(limit)")
            // A failure to describe the relation should not hide the data, so the
            // structure lookup is best effort.
            let structure = (try? connection.execute(
                Catalog.columnsSQL(relationLiteral: connection.quoteLiteral(relation))
            )).map(Catalog.parseColumns) ?? []
            return (rows, structure)
        }, completion: { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .success(let (rows, structure)):
                self.structureColumns = structure
                self.finishRun(with: rows)
            case .failure(let error):
                self.finishRun(with: error)
            }
        })
    }

    // MARK: - Query execution

    func run(_ sql: String) {
        let statement = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !statement.isEmpty else { return }
        guard !isRunning else {
            setStatus("a statement is already running - cancel it first", kind: .failure)
            return
        }

        selectedObject = nil
        structureColumns = []
        remember(statement)
        beginRun(describedAs: statement)

        database.execute(statement) { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .success(let result): self.finishRun(with: result)
            case .failure(let error): self.finishRun(with: error)
            }
        }
    }

    func cancel() {
        guard isRunning else { return }
        if let failure = database.cancelRunningQuery() {
            setStatus("could not cancel: \(failure)", kind: .failure)
        } else {
            setStatus("cancel requested…", kind: .info)
        }
    }

    private func beginRun(describedAs statement: String) {
        isRunning = true
        lastStatement = statement
        queryError = nil
        result = nil
        naturalColumnWidths = []
        pageStart = 0
        columnOffset = 0
        focusedRow = 0
        pane = .data
        setStatus("running…", kind: .info)
    }

    private func finishRun(with result: QueryResult) {
        isRunning = false
        self.result = result
        naturalColumnWidths = GridLayout.naturalWidths(columns: result.columns, rows: result.rows)
        queryError = nil

        var message = result.summary
        if let notice = result.notices.first {
            message += "  ·  \(notice)"
        }
        setStatus(message, kind: .success)
    }

    private func finishRun(with error: PostgresError) {
        isRunning = false
        result = nil
        naturalColumnWidths = []
        queryError = error
        setStatus(error.summary, kind: .failure)

        if error.kind == .connection {
            connectionState = .failed(error)
        }
    }

    private func remember(_ statement: String) {
        history.removeAll { $0 == statement }
        history.insert(statement, at: 0)
        if history.count > 50 { history.removeLast(history.count - 50) }
    }

    // MARK: - Panes

    func show(_ pane: Pane) {
        // Structure and row detail only make sense with something to show.
        switch pane {
        case .structure where structureColumns.isEmpty:
            setStatus("select a table in the sidebar to see its structure", kind: .info)
        case .rowDetail where rowCount == 0:
            setStatus("no rows to inspect", kind: .info)
        default:
            self.pane = pane
        }
    }

    func toggleHelp() {
        pane = pane == .help ? .data : .help
    }

    func toggleStructure() {
        show(pane == .structure ? .data : .structure)
    }

    func toggleHistory() {
        show(pane == .history ? .data : .history)
    }

    func returnToData() {
        pane = .data
    }

    /// Opens the detail view for a row of the current page.
    func openRowDetail(row index: Int) {
        guard index < rowCount else { return }
        focusedRow = index
        show(.rowDetail)
    }

    func runHistoryEntry(at index: Int) {
        guard index < history.count else { return }
        run(history[index])
    }

    // MARK: - Viewport

    /// Tells the model how many rows the grid can actually draw, which is what a
    /// page is measured in.
    func setViewport(rows: Int) {
        let rows = max(1, rows)
        guard rows != visibleRowCapacity else { return }
        visibleRowCapacity = rows
        // A resize changes the page size, so the window may now run past the end.
        pageStart = min(pageStart, max(0, rowCount - rows))
    }

    /// Records that the keyboard moved onto a row, so the detail pane and the
    /// position readout know where the user is.
    func focusRow(_ index: Int) {
        guard index < rowCount else { return }
        focusedRow = index
    }

    /// Moves the page window to start at `row`, clamped so the last page is still full.
    func scrollPage(to row: Int) {
        let start = min(max(0, row), max(0, rowCount - pageSize))
        guard start != pageStart else { return }
        pageStart = start
        focusedRow = start
    }

    func nextPage() { scrollPage(to: pageStart + pageSize) }
    func previousPage() { scrollPage(to: pageStart - pageSize) }

    func scrollColumns(by delta: Int) {
        guard let result, !result.columns.isEmpty else { return }
        columnOffset = min(max(0, columnOffset + delta), result.columns.count - 1)
    }

    // MARK: - Status

    func setStatus(_ message: String, kind: StatusKind) {
        status = message
        statusKind = kind
    }
}
