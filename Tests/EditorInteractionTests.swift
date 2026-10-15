import AppKit
import SwiftUI

var appVersion: String { "test" }

@main enum EditorInteractionTests {
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let queue = PropertyEditQueue()
        var edits: [String] = []
        queue.submit(immediate: false) { edits.append("old") }
        queue.submit(immediate: false) { edits.append("latest") }
        try await Task.sleep(for: .milliseconds(400))
        precondition(edits == ["latest"])
        queue.submit(immediate: false) { edits.append("canceled") }; queue.cancel()
        try await Task.sleep(for: .milliseconds(350))
        precondition(edits == ["latest"])
        queue.submit(immediate: false) { edits.append("source-A") }; queue.flush()
        queue.submit(immediate: true) { edits.append("source-B") }
        try await Task.sleep(for: .milliseconds(350))
        precondition(edits == ["latest", "source-A", "source-B"])
        print("PASS: coalesced typing, immediate selections, cancellation and flush exactly once")

        let ids: [Int64] = [3,2,1]
        precondition(SourceOrder.moving(ids, from: [0], to: 3) == [2,1,3])
        precondition(SourceOrder.moving(ids, from: [2], to: 0) == [1,3,2])
        precondition(SourceOrder.moving(ids, from: [0,1], to: 3) == [1,3,2])
        precondition(SourceOrder.moving(ids, from: [1], to: 1) == ids)
        precondition(SourceOrder.moving(ids, from: [4], to: 0) == nil)
        precondition(SourceOrder.moving(ids, from: [0], to: -1) == nil)
        precondition(SourceOrder.moving([1,1], from: [0], to: 1) == nil)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dante-editor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = StudioModel(projectDirectory: directory)
        guard let engine = dante_engine_create_with_config(CommandLine.arguments[1], 640, 360, 10, directory.path) else { fatalError(copied(dante_engine_last_error(nil))) }
        model.engine = engine; model.refresh()
        for name in ["A", "B", "C"] {
            precondition(model.command("source.add", ["scene":model.sceneName,"type":"color_source_v3","name":name,"settings":["width":640,"height":360,"color":0xFF112233]]))
        }
        if CommandLine.arguments.count > 2 {
            let target = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            try Data(copied(dante_engine_save(engine)).utf8).write(to: target.appendingPathComponent("studio.json"))
        }
        let displayed = model.items.reversed().map(\.sceneItemID)
        let selected = displayed[0]; model.selectedItem = selected
        let history = model.undoCount
        model.moveSources(in: model.sceneName, ids: displayed, from: [0], to: 3)
        precondition(model.items.reversed().map { $0.string("name") } == ["B","A","C"])
        precondition(model.undoCount == history + 1 && model.selectedItem == selected)
        let reordered = model.items.map(\.sceneItemID)
        let saved = copied(dante_engine_save(engine))
        model.undo(); precondition(model.items.reversed().map(\.sceneItemID) == displayed)
        model.redo(); precondition(model.items.map(\.sceneItemID) == reordered)
        model.moveSources(in: "wrong-scene", ids: displayed, from: [0], to: 2)
        model.moveSources(in: model.sceneName, ids: displayed, from: [0], to: 2)
        precondition(model.items.map(\.sceneItemID) == reordered)
        precondition(!model.command("scene.reorderSources", ["scene":model.sceneName,"ids":[reordered[0],reordered[0],reordered[2]]]))
        precondition(!model.command("scene.reorderSources", ["scene":model.sceneName,"ids":[reordered[0]]]))
        precondition(model.items.map(\.sceneItemID) == reordered)
        precondition(dante_engine_load(engine,saved)); model.refresh()
        precondition(model.items.map(\.sceneItemID) == reordered)
        let table = NSTableView(); table.addTableColumn(NSTableColumn(identifier:NSUserInterfaceItemIdentifier("source")))
        let controller = SourceListView.Coordinator(model:model); controller.table = table; controller.update(model)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let writer = controller.tableView(table,pasteboardWriterForRow:0)!
        precondition(board.writeObjects([writer]))
        precondition(!controller.valid(source:NSTableView(),pasteboard:board))
        precondition(controller.valid(source:table,pasteboard:board))
        precondition(!controller.drop(source:table,pasteboard:board,row:99))
        let beforeDrop = model.items.reversed().map(\.sceneItemID)
        precondition(controller.drop(source:table,pasteboard:board,row:3))
        precondition(model.items.reversed().map(\.sceneItemID) == [beforeDrop[1],beforeDrop[2],beforeDrop[0]])
        precondition(!controller.valid(source:table,pasteboard:board))
        controller.update(model)
        let contextMenu = controller.menu(row:1)!
        let contextName = controller.rows[1].string("name")
        contextMenu.performActionForItem(at:0)
        precondition(model.showingProperties && model.selectedName == contextName)
        model.showingProperties = false
        print("PASS: AppKit drag pasteboard, foreign/invalid drop rejection, accepted drop updates engine, consumed token, clicked-row properties action")
        let originalName = "A"
        queue.submit(immediate: false) { precondition(model.command("source.update", ["name":originalName,"settings":["width":321]])) }
        model.selectedItem = model.items.first { $0.string("name") == "B" }!.sceneItemID
        queue.flush()
        precondition(model.properties(name:"A").object("settings").number("width") == 321)
        precondition(model.properties(name:"B").object("settings").number("width") == 640)
        model.shutdown()
        print("PASS: actual engine reorder, one-step undo/redo, stable selection, stale/invalid order rejection, save/load and source-bound edits; no physical devices or public output")
    }
}
