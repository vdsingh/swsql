import SWSQLCore
import SwiftTUI

/// The object browser down the left hand side.
///
/// The list lives in a `ScrollView`, so focusing an entry brings it into view and
/// the arrow keys scroll the list. Entries beyond ``AppModel/objectListLimit`` are
/// not built at all; the filter above is the way to reach them.
struct SidebarView: View {
    @ObservedObject var model: AppModel
    let width: Int
    let capacity: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(header).foregroundColor(Theme.accent).bold()
            filterField
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(entries) { object in
                        entryRow(object)
                    }
                    overflowNotice
                }
            }
            // A ScrollView takes whatever width it is proposed, which would let the
            // sidebar grow into the results pane, so both dimensions are pinned.
            .frame(width: Extended(width), height: Extended(capacity))
        }
    }

    private var filterField: some View {
        HStack(spacing: 0) {
            Text(" / ").foregroundColor(Theme.dim)
            TextField(placeholder: "filter, then ⏎") { text in
                model.setObjectFilter(text)
            }
            .frame(width: Extended(max(1, width - 3)))
        }
    }

    private var header: String {
        let all = model.objects.count
        let shown = model.filteredObjects.count
        let title = shown == all ? "Objects \(all)" : "Objects \(shown)/\(all)"
        return DisplayText.pad(" " + title, to: width, alignment: .left)
    }

    private var entries: [DatabaseObject] {
        Array(model.filteredObjects.prefix(AppModel.objectListLimit))
    }

    /// The action carries the object's identifier rather than its position,
    /// because SwiftTUI freezes a button's action when it first builds it and the
    /// list reorders whenever the filter changes.
    private func entryRow(_ object: DatabaseObject) -> some View {
        let id = object.id
        return Button(
            action: { model.selectObject(id: id) },
            label: {
                Text(line(for: object))
                    .foregroundColor(model.selectedObject?.id == id ? Theme.accent : Theme.text)
            }
        )
    }

    @ViewBuilder
    private var overflowNotice: some View {
        if model.filteredObjects.count > AppModel.objectListLimit {
            Text(
                DisplayText.pad(
                    " …\(model.filteredObjects.count - AppModel.objectListLimit) more, use the filter",
                    to: width,
                    alignment: .left
                )
            )
            .foregroundColor(Theme.dim)
        }
    }

    private func line(for object: DatabaseObject) -> String {
        let count = DisplayText.compactCount(object.estimatedRows)
        // One trailing space keeps the estimate off the vertical rule.
        let suffix = count.isEmpty ? " " : " \(count) "
        let available = max(1, width - 3 - suffix.count)
        let name = DisplayText.truncate("\(object.schema).\(object.name)", to: available)
        let body = " \(object.kind.symbol) \(name)"
        return DisplayText.pad(body, to: max(1, width - suffix.count), alignment: .left) + suffix
    }
}
