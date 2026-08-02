# swsql

A PostgreSQL client for the terminal, written in Swift with
[SwiftTUI](https://github.com/rensbreur/SwiftTUI).

```
 swsql  alice@db.internal:5432/shop  ·  PostgreSQL 16.10                    ● ready
 sql> select id, email, balance, settings from users order by id limit 60
 select id, email, balance, settings from users order by id limit 60
 Objects 5                    │   │  id │ email              │ balance │ settings
 / filter, then ⏎             │───┼─────┼────────────────────┼─────────┼──────────────────────
 ◫ public.active_users        │ 1 │   1 │ user1@example.com  │   13.57 │ {"level": 1, "theme"…
 ▤ public.empty_table       0 │ 2 │   2 │ user2@example.com  │   27.14 │ {"level": 2, "theme"…
 ◪ public.order_totals     1k │ 3 │   3 │ user3@example.com  │   40.71 │ {"level": 3, "theme"…
 ▤ public.orders           5k │ 4 │   4 │ user4@example.com  │   54.28 │ ∅
 ▤ public.users            1k │ 5 │   5 │ user5@example.com  │   67.85 │ {"level": 5, "theme"…
                              │  ⇟ ⇞ ◀ ▶ Struct Hist ?  rows 1-28/60  cols 1/4
 60 rows, 4 columns in 2.1 ms
 ↑↓←→ move   ⏎ run / inspect row   ^C quit
```

## What it does

- **Browse** every table, view, materialised view and foreign table in the
  database, with row estimates and a filter.
- **Run** any statement and read the result in an aligned grid, with NULL shown
  as `∅` so it can never be confused with the string `"NULL"`, numbers flushed
  right, and embedded newlines and tabs made visible instead of tearing the
  table apart.
- **Inspect** a single row vertically, which is the only readable way to look at
  a wide record.
- **See structure**: column types, primary keys, nullability and defaults.
- **Cancel** a statement that is taking too long. The interface stays responsive
  while a query runs, and the cancel request goes to the server the same way
  `psql`'s does.
- **Re-run** anything from the statement history.
- **Understand failures**: the error pane shows the server's severity, SQLSTATE,
  message, detail, hint and the character position in the statement.

## Building

swsql links against **libpq**, PostgreSQL's own client library. That is a
deliberate choice: libpq returns every value in text format, so swsql renders
extension types, domains, user-defined enums and composites exactly as the
server formats them, rather than guessing at binary encodings for types it has
never heard of. It also means connection handling - `PGHOST` and friends,
`~/.pgpass`, service files, SSL modes, Kerberos - is the same as `psql`'s,
because it *is* `psql`'s.

```sh
brew install libpq          # macOS
apt install libpq-dev       # Debian / Ubuntu

make release
make install                # installs to /usr/local/bin, override with PREFIX=
```

`make` finds Homebrew's keg-only libpq for you. If you prefer to drive SwiftPM
directly, point it at the directory holding `libpq.pc`:

```sh
export PKG_CONFIG_PATH="$(brew --prefix libpq)/lib/pkgconfig"
swift build -c release
```

Requires Swift 6.0 or later and macOS 13 or later.

## Connecting

```sh
swsql                                 # PG* environment variables and defaults
swsql shop                            # a database by name
swsql postgres://alice@db/shop        # a URI
swsql "host=db user=alice"            # a libpq keyword string
swsql -h db.internal -U alice -d shop # discrete options
```

Anything not given on the command line is resolved by libpq exactly as `psql`
resolves it. Connections are tagged `application_name=swsql`, so they are easy
to pick out in `pg_stat_activity`.

### The setup screen

Run `swsql` with no arguments and nothing saved yet, and it opens on a setup
screen that asks for a connection URL. Paste one - a `postgres://` URI, a libpq
keyword string, or a bare database name - and press `⏎`. Once it connects, the
string is written to `~/.config/swsql/connection` (honouring `XDG_CONFIG_HOME`),
so every later `swsql` with no arguments reconnects to it without a URL or any
`PG*` environment. Only a string that actually connected is saved.

The file can hold a password, so it is written `0600`, the same posture `psql`
requires of `~/.pgpass`. Pressing `⏎` on the empty field falls back to libpq's
environment defaults instead. To change the saved connection later, choose
`Edit URL` from a failed connection, which returns to this screen. A connection
named on the command line is used as-is and is never saved.

## Keys

The interface is driven by moving focus and activating what is focused, either
from the keyboard or with the mouse.

| Key | Does |
| --- | --- |
| `↑ ↓ ← →` | move between the prompt, the sidebar, result rows and the buttons |
| `⏎` | run the statement in the prompt, open a table, inspect a row, press a button |
| `⌫` | delete the last character typed |
| `^C` / `^D` | quit |

The buttons under the results do the rest: `⇟` `⇞` page through a large result,
`◀` `▶` scroll one column at a time, `Struct` shows the selected table's
columns, `Hist` lists earlier statements, `?` opens help, and `Rows` returns to
the grid from any other pane.

The object filter and the SQL prompt are text fields: type, then press `⏎`.

## Mouse

Click a table, a result row or any button to focus and activate it; click a text
field to type into it. The scroll wheel moves the focus up and down, which is how
you scroll the sidebar or the result grid.

Mouse reporting is on whenever swsql is running, so selecting text to copy it
works the way it does in any terminal program that tracks the mouse: hold `⌥` or
`⇧` while dragging. This is why swsql links a small
[fork of SwiftTUI](https://github.com/vdsingh/SwiftTUI) -
the upstream library is keyboard-only, and the fork adds the SGR mouse handling.

## Limits and shape

- Results are capped at 10,000 rows, and table previews fetch 500. A client
  should not fall over because someone selected a billion rows.
- The grid builds one screenful of rows at a time. Paging is explicit so that the
  buttons under the grid are always one keypress below the last visible row.
- Column widths are measured once per result from the first 200 rows and capped
  at 44 characters, so a single JSON blob cannot push every other column off the
  screen.
- Statements are entered on one line. SwiftTUI's text field is single-line and
  cannot be pre-filled, which is also why recalling an earlier statement is done
  through the history pane rather than by pressing `↑` at the prompt.
- Character widths are counted per grapheme cluster, matching how SwiftTUI draws
  cells. Wide CJK glyphs and emoji will therefore sit a little loose in a column.

## Layout

```
Sources/
  CLibPQ/          system library target exposing libpq-fe.h
  SWSQLCore/       everything testable and terminal-independent
    LibPQ/         connection, results, errors, type names
    Layout/        column sizing, span rendering, screen regions
    Catalog.swift  introspection queries and their parsing
  swsql/           the SwiftTUI application: model and views
Tests/SWSQLCoreTests/
```

`SWSQLCore` has no dependency on SwiftTUI, and the layout code has no dependency
on a live connection, so the awkward cases - a column wider than the screen, a
zero-width viewport, a result set that changes shape under a resize - are all
covered by ordinary unit tests.

## Notes on SwiftTUI

Two behaviours of the library shape the code and are worth knowing if you extend
it:

- `Button.updateNode` never refreshes the control's action closure, so a button's
  action is frozen at the moment it is first built. Every action here therefore
  takes an index or no argument at all and resolves what it acts on from the
  model at press time.
- Arrow keys are consumed by focus navigation and never reach a control, so
  anything that would be a shortcut elsewhere is a button here.
