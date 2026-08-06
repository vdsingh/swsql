import Combine
import Foundation
import SWSQLCore
import SwiftTUI

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
        case connections
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

    /// A cell of the result, addressed absolutely (row index and the column's
    /// `sourceIndex`) so paging and column scrolling never move it off target.
    struct CellAddress: Equatable {
        var row: Int
        var column: Int
    }

    /// The cell highlighted for copying, or nil when nothing is highlighted.
    @Published private(set) var selectedCell: CellAddress?


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
    private let store: ConnectionsStore

    /// Where to connect. Nil until a connection is chosen on the setup screen.
    private var target: ConnectionTarget?

    /// The libpq environment/defaults target, used by the "environment defaults"
    /// escape hatch on the setup screen so the psql-style path stays reachable.
    private let environmentDefaults: ConnectionTarget

    /// Rows fetched for a table preview. Enough to be useful, small enough to stay snappy.
    private let previewLimit = 500

    /// How the app opens: on a saved connection, on an ad-hoc one from the command
    /// line, or on the setup screen because nothing is saved yet.
    enum Initial {
        case saved(SavedConnection)
        case ephemeral(ConnectionTarget)
        case setup
    }

    init(
        database: DatabaseService,
        store: ConnectionsStore,
        connections: [SavedConnection],
        initial: Initial,
        environmentDefaults: ConnectionTarget
    ) {
        self.database = database
        self.store = store
        self.connections = connections
        self.environmentDefaults = environmentDefaults

        switch initial {
        case .saved(let connection):
            activeConnection = connection
            target = Self.target(for: connection.connectionString)
            if target == nil {
                connectionState = .unconfigured
                setStatus("saved connection \"\(connection.name)\" has an invalid URL - add it again", kind: .failure)
            }
        case .ephemeral(let ephemeralTarget):
            target = ephemeralTarget
        case .setup:
            connectionState = .unconfigured
            setStatus("add a PostgreSQL connection to begin", kind: .info)
        }
    }

    // MARK: - Connections

    @Published private(set) var connections: [SavedConnection] = []

    /// The saved connection currently in use, when there is one. Nil for an
    /// environment-defaults or command-line connection. Drives the prod banner.
    @Published private(set) var activeConnection: SavedConnection?

    /// Which way the setup screen is taking connection details: a single URL box,
    /// or the individual fields (host, port, …) for people who would rather not
    /// assemble a connection string themselves.
    enum SetupInput: Equatable {
        case url
        case fields
    }

    /// The name and production flag being entered on the setup screen. The URL
    /// field commits them; these hold the parts the single-line fields cannot show.
    @Published private(set) var draftName: String = ""
    @Published private(set) var draftIsProduction = false

    /// Whether the setup screen is asking for a URL or the individual fields.
    @Published private(set) var draftInput: SetupInput = .url

    /// The individual connection fields, entered when `draftInput` is `.fields`.
    /// Each is optional: a blank one is left out of the connection string so libpq
    /// falls back to its own default, the same as omitting a command-line flag.
    @Published private(set) var draftHost: String = ""
    @Published private(set) var draftPort: String = ""
    @Published private(set) var draftUser: String = ""
    @Published private(set) var draftPassword: String = ""
    @Published private(set) var draftDatabase: String = ""

    /// The connection row the switcher is currently on, tracked as focus moves so
    /// the remove key knows which one "the highlighted connection" means. Only
    /// meaningful while the connections pane is open; reset whenever it closes.
    @Published private(set) var focusedConnectionName: String?

    /// A connection the user has asked to remove, held while we wait for a y/n
    /// confirmation. Removing is irreversible and one of these may be production,
    /// so it never happens on a single keystroke.
    @Published private(set) var pendingRemovalName: String?

    /// True while the switcher is waiting for the user to confirm a removal.
    var isConfirmingRemoval: Bool { pendingRemovalName != nil }

    /// True while connected to a connection the user tagged as production.
    var isConnectedToProduction: Bool {
        guard case .connected = connectionState else { return false }
        return activeConnection?.isProduction == true
    }

    func setDraftName(_ text: String) {
        draftName = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !draftName.isEmpty { setStatus("name set to \"\(draftName)\"", kind: .info) }
    }

    func toggleDraftProduction() {
        setDraftProduction(!draftIsProduction)
    }

    func setDraftProduction(_ isProduction: Bool) {
        guard draftIsProduction != isProduction else { return }
        draftIsProduction = isProduction
        setStatus(isProduction ? "this connection will be marked as production" : "marked as non-production", kind: .info)
    }

    /// Switches the setup screen to the URL box, keeping any fields already typed
    /// so toggling back and forth never loses input.
    func useURLInput() {
        guard draftInput != .url else { return }
        draftInput = .url
        setStatus("enter a connection URL", kind: .info)
    }

    /// Switches the setup screen to the individual fields.
    func useFieldsInput() {
        guard draftInput != .fields else { return }
        draftInput = .fields
        setStatus("fill in the fields, then press connect", kind: .info)
    }

    func setDraftHost(_ text: String) { draftHost = trimmedField(text); reportField("host", draftHost) }
    func setDraftPort(_ text: String) { draftPort = trimmedField(text); reportField("port", draftPort) }
    func setDraftUser(_ text: String) { draftUser = trimmedField(text); reportField("user", draftUser) }
    func setDraftDatabase(_ text: String) { draftDatabase = trimmedField(text); reportField("database", draftDatabase) }

    /// The password is stored verbatim (never echoed in the status line) so a value
    /// with intentional spaces survives, and so it is not read back out loud.
    func setDraftPassword(_ text: String) {
        draftPassword = text
        if !draftPassword.isEmpty { setStatus("password set", kind: .info) }
    }

    func clearDraftHost() { draftHost = ""; setStatus("type a host and press ⏎", kind: .info) }
    func clearDraftPort() { draftPort = ""; setStatus("type a port and press ⏎", kind: .info) }
    func clearDraftUser() { draftUser = ""; setStatus("type a user and press ⏎", kind: .info) }
    func clearDraftPassword() { draftPassword = ""; setStatus("type a password and press ⏎", kind: .info) }
    func clearDraftDatabase() { draftDatabase = ""; setStatus("type a database and press ⏎", kind: .info) }

    private func trimmedField(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func reportField(_ label: String, _ value: String) {
        if !value.isEmpty { setStatus("\(label) set to \"\(value)\"", kind: .info) }
    }

    /// Adds the connection described on the setup screen and connects to it. It is
    /// saved only once it actually connects, so a typo is never persisted.
    func addConnection(url input: String) {
        let connectionString = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !connectionString.isEmpty else {
            setStatus("enter a connection URL, e.g. postgres://user@host:5432/dbname", kind: .failure)
            return
        }
        guard Self.target(for: connectionString) != nil else {
            setStatus("that does not look like a connection URL", kind: .failure)
            return
        }
        let name = draftName.isEmpty ? SavedConnection.defaultName(for: connectionString) : draftName
        attempt(SavedConnection(name: name, connectionString: connectionString, isProduction: draftIsProduction))
    }

    /// Adds the connection described by the individual setup fields and connects
    /// to it. Assembles a libpq keyword string from the parts, then follows the
    /// same path as a URL, so it is likewise saved only once it actually connects.
    func addConnectionFromFields() {
        let connectionString = ConnectionTarget.keywordString(
            host: draftHost,
            port: draftPort,
            user: draftUser,
            password: draftPassword,
            database: draftDatabase
        )
        guard !connectionString.isEmpty else {
            setStatus("fill in at least one field, e.g. a host or database name", kind: .failure)
            return
        }
        let name = draftName.isEmpty ? SavedConnection.defaultName(for: connectionString) : draftName
        attempt(SavedConnection(name: name, connectionString: connectionString, isProduction: draftIsProduction))
    }

    /// Switches to a saved connection by name.
    func connect(named name: String) {
        guard let connection = ConnectionList.first(named: name, in: connections) else { return }
        returnToData()
        attempt(connection)
    }

    /// Records that the switcher's focus moved onto a connection row, so the
    /// remove key can act on it. Moving onto a different row abandons a
    /// half-started removal, so a stray "y" can never delete the row you just
    /// moved to instead of the one you meant.
    func focusConnection(_ name: String) {
        guard focusedConnectionName?.caseInsensitiveCompare(name) != .orderedSame else { return }
        focusedConnectionName = name
        cancelRemoval(silently: true)
    }

    /// Focus left the connection rows (onto the Add button), so nothing is
    /// targeted for removal any more.
    func clearConnectionFocus() {
        focusedConnectionName = nil
        cancelRemoval(silently: true)
    }

    /// Asks to remove the highlighted connection, entering the confirm step. A
    /// no-op unless a row is actually highlighted in the switcher.
    func requestRemoveFocusedConnection() {
        guard pane == .connections else { return }
        guard let name = focusedConnectionName,
              let connection = ConnectionList.first(named: name, in: connections) else {
            setStatus("highlight a connection with ↑↓ first, then press d to remove it", kind: .info)
            return
        }
        pendingRemovalName = connection.name
        let tag = connection.isProduction ? " (⚠ PRODUCTION)" : ""
        setStatus("remove \"\(connection.name)\"\(tag)?  press y to confirm, n to keep it", kind: .failure)
    }

    /// Confirms the pending removal: drops it from the saved list and persists.
    /// A live session on that connection is left untouched - removing only forgets
    /// it for next time, it does not disconnect you.
    func confirmRemoval() {
        guard let name = pendingRemovalName else { return }
        pendingRemovalName = nil
        guard ConnectionList.first(named: name, in: connections) != nil else { return }
        connections = ConnectionList.removing(name, from: connections)
        if focusedConnectionName?.caseInsensitiveCompare(name) == .orderedSame {
            focusedConnectionName = nil
        }
        do {
            try store.save(connections)
            setStatus("removed \"\(name)\" from saved connections", kind: .success)
        } catch {
            setStatus("removed \"\(name)\", but could not update the saved file: \(error.localizedDescription)", kind: .failure)
        }
    }

    /// Abandons a pending removal. `silently` is for the incidental cancellations
    /// (moving to another row, leaving the pane) that should not talk over the
    /// last status message.
    func cancelRemoval(silently: Bool = false) {
        guard pendingRemovalName != nil else { return }
        pendingRemovalName = nil
        if !silently { setStatus("kept the connection", kind: .info) }
    }

    /// Clears the switcher's transient selection state. Called whenever the pane
    /// opens or closes so a removal can never be left half-started across visits.
    private func resetConnectionSelection() {
        focusedConnectionName = nil
        cancelRemoval(silently: true)
    }

    /// Connects the psql way, via libpq's own environment and defaults, without
    /// saving anything. Reached by submitting an empty URL on the setup screen.
    func useEnvironmentDefaults() {
        activeConnection = nil
        target = environmentDefaults
        clearDraft()
        start()
    }

    /// Opens the setup screen to add another connection, keeping the saved ones.
    func beginAddConnection() {
        guard !isRunning else {
            setStatus("a statement is already running - cancel it first", kind: .failure)
            return
        }
        // The setup screen replaces the whole UI, so close the switcher on the
        // way in: a lingering .connections pane keeps the global d/D remove
        // shortcut (and a pending removal's y/n capture) live while the URL
        // field is being typed into.
        returnToData()
        clearDraft()
        connectionState = .unconfigured
        setStatus("add a PostgreSQL connection", kind: .info)
    }

    /// Leaves the add screen without adding, reconnecting to where we were. Only
    /// meaningful when at least one connection is already saved.
    func cancelAdd() {
        guard let connection = activeConnection ?? connections.first else { return }
        attempt(connection)
    }

    /// Points the model at `connection` and connects, resetting the per-database
    /// view state so the old catalog and results don't linger under the new one.
    private func attempt(_ connection: SavedConnection) {
        guard !isRunning else {
            setStatus("a statement is already running - cancel it first", kind: .failure)
            return
        }
        guard let resolved = Self.target(for: connection.connectionString) else {
            setStatus("connection \"\(connection.name)\" has an invalid URL", kind: .failure)
            return
        }
        activeConnection = connection
        target = resolved
        clearDraft()
        objects = []
        columnReferences = []
        dismissCompletions()
        selectedObject = nil
        structureColumns = []
        objectFilter = ""
        start()
    }

    private func clearDraft() {
        draftName = ""
        draftIsProduction = false
        draftInput = .url
        draftHost = ""
        draftPort = ""
        draftUser = ""
        draftPassword = ""
        draftDatabase = ""
    }

    /// Clears just the name so its field reappears for re-entry (the `change` link
    /// on the setup screen), leaving the production choice untouched.
    func clearDraftName() {
        draftName = ""
        setStatus("type a new name and press ⏎", kind: .info)
    }

    /// Parses a saved or entered connection string into a libpq target.
    private static func target(for connectionString: String) -> ConnectionTarget? {
        guard let invocation = try? ConnectionTarget.parse(arguments: [connectionString]) else { return nil }
        switch invocation {
        case .connect(let target), .connectUsingDefaults(let target): return target
        case .help, .version: return nil
        }
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
                self.setStatus("connected to \(info.database) (server \(info.serverVersion))\(self.persistActiveConnection())", kind: .success)
                self.reloadObjects()
            case .failure(let error):
                self.connectionState = .failed(error)
                self.setStatus(error.summary, kind: .failure)
            }
        }
    }

    /// Saves the active connection now that it has proven it can connect, moving it
    /// to the front of the most-recently-used list. Returns a note to append to the
    /// status line; a save failure must not lose the working connection.
    private func persistActiveConnection() -> String {
        guard let active = activeConnection else { return "" }
        connections = ConnectionList.upsert(active, into: connections)
        do {
            try store.save(connections)
            return ""
        } catch {
            return "  ·  could not save the connection: \(error.localizedDescription)"
        }
    }

    // MARK: - Catalog

    func reloadObjects() {
        database.execute(Catalog.objectsSQL) { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .success(let result):
                self.objects = Catalog.parseObjects(result)
                self.rebuildVocabulary()
                self.loadColumnsForCompletion()
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

    // MARK: - SQL editor

    /// The multi-line SQL editor's text. The editor owns it and writes into this
    /// handle as the user types; the model reads it to run or format, and pushes
    /// new text in (formatting, recalling a statement) via `document.set`.
    let document = EditorDocument()

    /// Runs the statement the cursor is in - or the one just before it when the
    /// cursor sits between statements. Bound to the editor's Ctrl-R and Run button.
    func runCurrentQuery() {
        guard let statement = SQLStatementSplitter.statement(in: document.text, atCursor: document.cursorOffset) else { return }
        run(statement.text)
    }

    func clearEditor() {
        guard !isRunning else {
            setStatus("a statement is already running - cancel it first", kind: .failure)
            return
        }
        document.set("")
        setStatus("editor cleared", kind: .info)
    }

    /// Pretty-prints the editor's SQL in place.
    func formatQuery() {
        let trimmed = document.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            setStatus("nothing to format", kind: .info)
            return
        }
        document.set(SQLFormatter.format(document.text))
        setStatus("formatted", kind: .success)
    }

    // MARK: - Autocomplete

    @Published private(set) var completions: [CompletionItem] = []
    @Published private(set) var completionIndex = 0
    var hasCompletions: Bool { !completions.isEmpty }

    /// Cached completion vocabulary, rebuilt when the catalog changes.
    private var vocabulary: [CompletionItem] = []
    private var columnReferences: [(table: String, column: String)] = []

    private static let completionKeywords = [
        "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "NULL", "AS", "ON", "IN", "IS", "LIKE",
        "BETWEEN", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "FULL", "CROSS", "GROUP", "ORDER",
        "BY", "HAVING", "LIMIT", "OFFSET", "UNION", "ALL", "DISTINCT", "INSERT", "INTO", "VALUES",
        "UPDATE", "SET", "DELETE", "RETURNING", "WITH", "CASE", "WHEN", "THEN", "ELSE", "END",
        "ASC", "DESC", "EXISTS",
    ]

    /// Called by the editor whenever the text under the cursor changes.
    func editorLineChanged(_ linePrefix: String) {
        let items = SQLCompletion.complete(linePrefix: linePrefix, vocabulary: vocabulary)
        guard items != completions else { return }
        completions = items
        completionIndex = 0
    }

    /// Handles a key the editor forwarded because the completion menu is open.
    /// Returns whether it was consumed (false lets the editor handle the key).
    func handleMenuKey(_ key: TextEditorMenuKey) -> Bool {
        guard hasCompletions else { return false }
        switch key {
        case .up: completionIndex = max(0, completionIndex - 1)
        case .down: completionIndex = min(completions.count - 1, completionIndex + 1)
        case .accept:
            document.complete(with: completions[completionIndex].text)
            dismissCompletions()
        case .dismiss:
            dismissCompletions()
        }
        return true
    }

    func dismissCompletions() {
        completions = []
        completionIndex = 0
    }

    /// The Escape key, as a global "back": close the completion menu if it is
    /// open, otherwise return from an auxiliary pane (structure, row detail,
    /// history, connections, help) to the result grid, otherwise clear the
    /// highlighted cell.
    func handleEscape() {
        if isConfirmingRemoval {
            cancelRemoval()
        } else if hasCompletions {
            dismissCompletions()
        } else if pane != .data {
            returnToData()
        } else if selectedCell != nil {
            clearCellSelection()
        }
    }

    private func rebuildVocabulary() {
        var items = Self.completionKeywords.map { CompletionItem(text: $0, detail: "keyword", kind: .keyword) }
        for object in objects {
            let kind: CompletionItem.Kind = (object.kind == .view || object.kind == .materializedView) ? .view : .table
            items.append(CompletionItem(text: object.name, detail: "\(object.schema) · \(object.kind.label)", kind: kind))
        }
        var seen = Set<String>()
        for reference in columnReferences where seen.insert(reference.column.lowercased()).inserted {
            items.append(CompletionItem(text: reference.column, detail: "column", kind: .column))
        }
        vocabulary = items
    }

    /// Loads every column name once per connection, for autocomplete. Best effort.
    private func loadColumnsForCompletion() {
        database.execute(Catalog.allColumnsSQL) { [weak self] outcome in
            guard let self else { return }
            if case .success(let result) = outcome {
                self.columnReferences = Catalog.parseColumnReferences(result)
                self.rebuildVocabulary()
            }
        }
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
        selectedCell = nil
        pane = .data
        dismissCompletions()
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

    func toggleConnections() {
        resetConnectionSelection()
        pane = pane == .connections ? .data : .connections
    }

    func returnToData() {
        resetConnectionSelection()
        pane = .data
    }

    /// Opens the detail view for a row of the current page.
    func openRowDetail(row index: Int) {
        guard index < rowCount else { return }
        focusedRow = index
        show(.rowDetail)
    }

    /// Loads a previous statement into the editor so it can be reviewed or edited
    /// before running - now possible because the editor can be pre-filled.
    func recall(at index: Int) {
        guard index < history.count else { return }
        document.set(history[index])
        returnToData()
        setStatus("loaded into the editor - ⌃R or Run ▶ to execute", kind: .info)
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

    // MARK: - Cell selection

    /// Highlights a cell the mouse clicked, so ⌃Y (or a terminal ⌘C remap) can
    /// copy its full value - the underlying text, not the truncated display.
    func selectCell(row: Int, column: Int) {
        guard let result, row < result.rows.count, column < result.columns.count else { return }
        focusedRow = row
        let cell = CellAddress(row: row, column: column)
        guard selectedCell != cell else { return }
        selectedCell = cell
        setStatus("highlighted \(result.columns[column].name) · row \(row + 1)  -  ⌃Y (or a ⌘C remap) copies, esc clears", kind: .info)
    }

    func clearCellSelection() {
        guard selectedCell != nil else { return }
        selectedCell = nil
    }

    /// Copies the highlighted cell's raw value to the system clipboard.
    func copySelectedCell() {
        guard let cell = selectedCell, let result,
              cell.row < result.rows.count, cell.column < result.columns.count else {
            setStatus("click a cell to highlight it first, then ⌃Y (or a ⌘C remap) copies it", kind: .info)
            return
        }
        let column = result.columns[cell.column].name
        guard let value = result.rows[cell.row][safe: cell.column] ?? nil else {
            setStatus("\(column) · row \(cell.row + 1) is NULL - nothing to copy", kind: .info)
            return
        }
        if let failure = Clipboard.copy(value) {
            setStatus(failure, kind: .failure)
        } else {
            let length = "\(value.count) \(value.count == 1 ? "character" : "characters")"
            setStatus("copied \(column) · row \(cell.row + 1) (\(length))", kind: .success)
        }
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
