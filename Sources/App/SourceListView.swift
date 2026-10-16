import AppKit
import SwiftUI

/// AppKit owns row selection, drag sessions and menus. Meter/preview refreshes
/// must not reload the table or interrupt an in-flight native drag.
struct SourceListView: NSViewRepresentable {
    @ObservedObject var model: StudioModel
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> NSScrollView {
        let table = SourceTable()
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("source")))
        table.headerView = nil; table.rowHeight = 34
        table.intercellSpacing = NSSize(width: 0, height: 1)
        table.backgroundColor = .clear; table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.allowsEmptySelection = true; table.allowsMultipleSelection = false
        table.dataSource = context.coordinator; table.delegate = context.coordinator
        table.registerForDraggedTypes([Coordinator.dragType])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        table.setAccessibilityLabel("Fontes da cena. Arraste para reordenar.")
        table.menuProvider = { [weak coordinator = context.coordinator] row in coordinator?.menu(row: row) }
        context.coordinator.table = table
        let scroll = NSScrollView(); scroll.documentView = table
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        context.coordinator.update(model)
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) { context.coordinator.update(model) }

    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        static let dragType = NSPasteboard.PasteboardType("com.dantetesta.DanteLive.scene-item")
        var model: StudioModel
        weak var table: NSTableView?
        var rows: [[String: Any]] = []
        private var scene = ""
        private var signature = ""
        private var synchronizing = false
        private var drag: (token: String, scene: String, ids: [Int64], row: Int)?
        init(model: StudioModel) { self.model = model }
        func update(_ model: StudioModel) {
            self.model = model
            let next = Array(model.listedSources.reversed())
            let nextSignature = jsonString(next.map { ["id":$0.sceneItemID,"name":$0.string("name"),"type":$0.string("type"),"visible":$0.flag("visible",true),"locked":$0.flag("locked")] as [String:Any] })
            synchronizing = true
            defer { synchronizing = false }
            if scene != model.sceneName || signature != nextSignature {
                scene = model.sceneName; signature = nextSignature; rows = next
                table?.reloadData()
            } else { rows = next }
            let selected = rows.firstIndex { $0.sceneItemID == model.selectedItem }
            if table?.selectedRow != (selected ?? -1) {
                table?.selectRowIndexes(selected.map { IndexSet(integer:$0) } ?? [], byExtendingSelection:false)
            }
        }
        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !synchronizing, let table else { return }
            model.selectedItem = rows.indices.contains(table.selectedRow) ? rows[table.selectedRow].sceneItemID : nil
        }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard rows.indices.contains(row) else { return nil }
            let item = rows[row], id = item.sceneItemID, scene = self.scene
            let cell = (tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("source-cell"), owner:nil) as? SourceCell) ?? SourceCell()
            cell.configure(item)
            cell.visibility.actionBody = { [weak model] in
                _ = model?.command("item.visible", ["scene":scene,"id":id,"value":!item.flag("visible",true)])
            }
            cell.lock.actionBody = { [weak model] in
                _ = model?.command("item.locked", ["scene":scene,"id":id,"value":!item.flag("locked")])
            }
            return cell
        }
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard rows.indices.contains(row) else { return nil }
            let token = UUID().uuidString
            drag = (token, scene, rows.map(\.sceneItemID), row)
            let writer = NSPasteboardItem(); writer.setString(token, forType:Self.dragType)
            return writer
        }
        private func valid(_ info: NSDraggingInfo) -> Bool { valid(source:info.draggingSource,pasteboard:info.draggingPasteboard) }
        func valid(source: Any?, pasteboard: NSPasteboard) -> Bool {
            guard let drag, let origin = source as? NSTableView,
                  origin === table, drag.scene == model.sceneName,
                  drag.ids == model.listedSources.reversed().map(\.sceneItemID) else { return false }
            return pasteboard.string(forType:Self.dragType) == drag.token
        }
        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
            guard (0...rows.count).contains(row), valid(info) else { return [] }
            tableView.setDropRow(row, dropOperation:.above)
            return .move
        }
        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation operation: NSTableView.DropOperation) -> Bool {
            drop(source:info.draggingSource,pasteboard:info.draggingPasteboard,row:row)
        }
        func drop(source: Any?, pasteboard: NSPasteboard, row: Int) -> Bool {
            guard (0...rows.count).contains(row), valid(source:source,pasteboard:pasteboard), let drag else { return false }
            model.moveSources(in: drag.scene, ids: drag.ids, from: IndexSet(integer:drag.row), to:row)
            self.drag = nil
            return true
        }
        func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { drag = nil }
        func menu(row: Int) -> NSMenu? {
            guard rows.indices.contains(row) else { return nil }
            let item = rows[row], id = item.sceneItemID, scene = self.scene
            let ids = rows.map(\.sceneItemID), model = self.model
            let menu = NSMenu(); menu.autoenablesItems = false
            func add(_ menu: NSMenu, _ title: String, enabled: Bool = true, action: @escaping () -> Void) {
                let entry = SourceMenuItem(title: title, body: action); entry.isEnabled = enabled; menu.addItem(entry)
            }
            add(menu,"Propriedades…") {
                model.selectedItem = id; model.inspectorRevision += 1
                if isCameraSource(item.string("type")) {
                    model.cameraSourceName = item.string("name"); model.showingCamera = true
                } else { model.showingProperties = true }
            }
            add(menu,"Filtros…") { model.selectedItem = id; model.inspectorRevision += 1; model.showingFilters = true }
            add(menu,"Renomear…") { model.askName(title:"Renomear fonte",initial:item.string("name")) {
                _ = model.command("source.rename",["name":item.string("name"),"newName":$0])
            } }
            menu.addItem(.separator())
            add(menu,item.flag("visible",true) ? "Ocultar" : "Mostrar") { _ = model.command("item.visible",["scene":scene,"id":id,"value":!item.flag("visible",true)]) }
            add(menu,item.flag("locked") ? "Desbloquear" : "Bloquear") { _ = model.command("item.locked",["scene":scene,"id":id,"value":!item.flag("locked")]) }
            let transform = NSMenu(); transform.autoenablesItems = false
            for (title, operation) in [("Ajustar ao canvas","item.fit"),("Centralizar","item.center"),("Tamanho original (100%)","item.native")] {
                add(transform,title,enabled:!item.flag("locked") && item.number("width") > 0 && item.number("height") > 0) { _ = model.command(operation,["scene":scene,"id":id]) }
            }
            let transformItem = NSMenuItem(title:"Transformar",action:nil,keyEquivalent:""); transformItem.submenu = transform; menu.addItem(transformItem)
            let order = NSMenu(); order.autoenablesItems = false
            add(order,"Mover para cima",enabled:row > 0) { model.moveSources(in:scene,ids:ids,from:IndexSet(integer:row),to:row-1) }
            add(order,"Mover para baixo",enabled:row < ids.count-1) { model.moveSources(in:scene,ids:ids,from:IndexSet(integer:row),to:row+2) }
            order.addItem(.separator())
            add(order,"Trazer à frente",enabled:row > 0) { model.moveSources(in:scene,ids:ids,from:IndexSet(integer:row),to:0) }
            add(order,"Enviar ao fundo",enabled:row < ids.count-1) { model.moveSources(in:scene,ids:ids,from:IndexSet(integer:row),to:ids.count) }
            let orderItem = NSMenuItem(title:"Ordenar",action:nil,keyEquivalent:""); orderItem.submenu = order; menu.addItem(orderItem)
            menu.addItem(.separator())
            add(menu,"Remover…") { model.removeSource(id:id,scene:scene) }
            return menu
        }
    }
}

@MainActor private final class SourceTable: NSTableView {
    var menuProvider: ((Int) -> NSMenu?)?
    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?(row(at:convert(event.locationInWindow,from:nil))) }
}
@MainActor private final class SourceMenuItem: NSMenuItem {
    let body: () -> Void
    init(title: String, body: @escaping () -> Void) {
        self.body = body; super.init(title:title,action:#selector(invoke),keyEquivalent:""); target = self
    }
    required init(coder: NSCoder) { fatalError("Not used") }
    @objc private func invoke() { body() }
}
@MainActor private final class SourceButton: NSButton {
    var actionBody: (() -> Void)?
    init() { super.init(frame:.zero); isBordered = false; target = self; action = #selector(invoke) }
    required init?(coder: NSCoder) { fatalError("Not used") }
    @objc private func invoke() { actionBody?() }
}
@MainActor private final class SourceCell: NSTableCellView {
    let label = NSTextField(labelWithString:"")
    let icon = NSImageView()
    let visibility = SourceButton(), lock = SourceButton()
    override init(frame frameRect: NSRect) {
        super.init(frame:frameRect); identifier = NSUserInterfaceItemIdentifier("source-cell")
        label.lineBreakMode = .byTruncatingTail; label.font = .systemFont(ofSize:NSFont.systemFontSize)
        for view in [icon,label,visibility,lock] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view); view.centerYAnchor.constraint(equalTo:centerYAnchor).isActive = true }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo:leadingAnchor,constant:8),icon.widthAnchor.constraint(equalToConstant:20),icon.heightAnchor.constraint(equalToConstant:20),
            label.leadingAnchor.constraint(equalTo:icon.trailingAnchor,constant:8),label.trailingAnchor.constraint(equalTo:visibility.leadingAnchor,constant:-8),
            visibility.widthAnchor.constraint(equalToConstant:24),visibility.heightAnchor.constraint(equalToConstant:24),
            lock.leadingAnchor.constraint(equalTo:visibility.trailingAnchor,constant:4),lock.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-6),lock.widthAnchor.constraint(equalToConstant:24),lock.heightAnchor.constraint(equalToConstant:24)
        ])
        textField = label; imageView = icon
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    func configure(_ item: [String:Any]) {
        let name = item.string("name"); label.stringValue = name
        icon.image = NSImage(systemSymbolName:iconForSource(item.string("type")),accessibilityDescription:nil)
        visibility.image = NSImage(systemSymbolName:item.flag("visible",true) ? "eye" : "eye.slash",accessibilityDescription:nil)
        lock.image = NSImage(systemSymbolName:item.flag("locked") ? "lock.fill" : "lock.open",accessibilityDescription:nil)
        visibility.toolTip = item.flag("visible",true) ? "Ocultar" : "Mostrar"; visibility.setAccessibilityLabel("\(visibility.toolTip!) \(name)")
        lock.toolTip = item.flag("locked") ? "Desbloquear" : "Bloquear"; lock.setAccessibilityLabel("\(lock.toolTip!) \(name)")
    }
}
