import AppKit
import Foundation
import Network

struct Interface: Codable, Equatable {
    var name: String
    var mac: String
}

class SettingsManager {
    static let shared = SettingsManager()
    private let key = "macwolf.interfaces"
    private let defaults = UserDefaults(suiteName: "io.github.tyoubin.macwolf") ?? .standard
    
    func getInterfaces() -> [Interface] {
        guard let data = defaults.data(forKey: key),
              let interfaces = try? JSONDecoder().decode([Interface].self, from: data) else {
            return []
        }
        return interfaces
    }
    
    func saveInterfaces(_ interfaces: [Interface]) {
        if let data = try? JSONEncoder().encode(interfaces) {
            defaults.set(data, forKey: key)
        }
    }
}

class InterfaceTableViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let nameColumnId = NSUserInterfaceItemIdentifier("NameCol")
    private let macColumnId = NSUserInterfaceItemIdentifier("MacCol")

    var interfaces: [Interface] = []
    var onSave: (() -> Void)?

    let scrollView = NSScrollView()
    let tableView = NSTableView()
    let addButton = NSButton()
    let removeButton = NSButton()

    override func loadView() {
        view = NSView()
        setupTable()
        setupButtons()
        setupLayout()
        updateControlStates()
    }

    private func setupTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.headerView = NSTableHeaderView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.registerForDraggedTypes([.string])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)

        let nameCol = NSTableColumn(identifier: nameColumnId)
        nameCol.title = "Name"
        nameCol.minWidth = 180
        nameCol.isEditable = true
        tableView.addTableColumn(nameCol)

        let macCol = NSTableColumn(identifier: macColumnId)
        macCol.title = "MAC Address"
        macCol.minWidth = 220
        macCol.isEditable = true
        tableView.addTableColumn(macCol)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = tableView
    }

    private func setupButtons() {
        addButton.title = "+"
        addButton.bezelStyle = .rounded
        addButton.target = self
        addButton.action = #selector(addInterface)

        removeButton.title = "-"
        removeButton.bezelStyle = .rounded
        removeButton.target = self
        removeButton.action = #selector(removeInterface)
    }

    private func setupLayout() {
        let buttonStack = NSStackView(views: [addButton, removeButton])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 8
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        view.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: buttonStack.topAnchor, constant: -12),

            buttonStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            buttonStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
        ])
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        interfaces.count
    }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        guard row >= 0 && row < interfaces.count else { return nil }
        let interface = interfaces[row]
        switch tableColumn?.identifier {
        case nameColumnId:
            return interface.name
        case macColumnId:
            return interface.mac
        default:
            return nil
        }
    }

    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        guard row >= 0 && row < interfaces.count else { return }
        let text = ((object as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        switch tableColumn?.identifier {
        case nameColumnId:
            interfaces[row].name = text.isEmpty ? "Unnamed" : text
            saveAndRefresh(selecting: row)
        case macColumnId:
            let mac = normalizedMac(text)
            guard isValidMac(mac) else {
                showInvalidMacAlert()
                reloadMacCell(row: row)
                return
            }
            interfaces[row].mac = mac
            saveAndRefresh(selecting: row)
        default:
            break
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateControlStates()
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        NSString(string: "\(row)")
    }

    func tableView(_ tableView: NSTableView,
                   validateDrop info: any NSDraggingInfo,
                   proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        if dropOperation != .above {
            tableView.setDropRow(row, dropOperation: .above)
        }
        return .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let items = info.draggingPasteboard.readObjects(forClasses: [NSString.self], options: nil),
              let first = items.first as? NSString,
              let sourceRow = Int(first as String),
              sourceRow >= 0,
              sourceRow < interfaces.count else {
            return false
        }

        var destinationRow = row
        let moved = interfaces.remove(at: sourceRow)
        if sourceRow < destinationRow {
            destinationRow -= 1
        }
        destinationRow = max(0, min(destinationRow, interfaces.count))
        interfaces.insert(moved, at: destinationRow)
        saveAndRefresh(selecting: destinationRow)
        return true
    }

    @objc private func addInterface() {
        interfaces.append(Interface(name: "New Interface", mac: "00:11:22:33:44:55"))
        let newRow = interfaces.count - 1
        saveAndRefresh(selecting: newRow)
        tableView.editColumn(tableView.column(withIdentifier: nameColumnId), row: newRow, with: nil, select: true)
    }

    @objc private func removeInterface() {
        let row = tableView.selectedRow
        guard row >= 0 && row < interfaces.count else { return }
        interfaces.remove(at: row)
        let nextRow = min(row, interfaces.count - 1)
        saveAndRefresh(selecting: nextRow >= 0 ? nextRow : nil)
    }

    private func reloadMacCell(row: Int) {
        let column = tableView.column(withIdentifier: macColumnId)
        guard column >= 0 else { return }
        tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: column))
    }

    private func showInvalidMacAlert() {
        let alert = NSAlert()
        alert.messageText = "Invalid MAC Address"
        alert.informativeText = "Please use a valid MAC address (e.g., 00:11:22:33:44:55)."
        alert.runModal()
    }

    private func isValidMac(_ mac: String) -> Bool {
        let pattern = "^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$"
        return mac.range(of: pattern, options: .regularExpression) != nil
    }

    private func normalizedMac(_ mac: String) -> String {
        mac.replacingOccurrences(of: "-", with: ":").uppercased()
    }

    private func updateControlStates() {
        let row = tableView.selectedRow
        let hasSelection = row >= 0 && row < interfaces.count
        removeButton.isEnabled = hasSelection
    }

    private func saveAndRefresh(selecting rowToSelect: Int? = nil) {
        SettingsManager.shared.saveInterfaces(interfaces)
        tableView.reloadData()
        if let rowToSelect, rowToSelect >= 0 && rowToSelect < interfaces.count {
            tableView.selectRowIndexes(IndexSet(integer: rowToSelect), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }
        updateControlStates()
        onSave?()
    }
}

class SettingsWindow: NSWindow {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable],
                   backing: .buffered,
                   defer: false)
        self.title = "macwolf Settings"
        self.center()
        self.minSize = NSSize(width: 480, height: 340)
        
        let vc = InterfaceTableViewController()
        vc.interfaces = SettingsManager.shared.getInterfaces()
        vc.onSave = {
            NotificationCenter.default.post(name: NSNotification.Name("SettingsChanged"), object: nil)
        }
        self.contentViewController = vc
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let chars = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        switch chars {
        case "x":
            return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
        case "c":
            return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
        case "v":
            return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
        case "a":
            return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

class MacWolfApp: NSObject, NSApplicationDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var settingsWindow: SettingsWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "network", accessibilityDescription: "Wake on LAN")
        }
        constructMenu()
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("SettingsChanged"), object: nil, queue: .main) { [weak self] _ in
            self?.constructMenu()
        }
    }
    
    func constructMenu() {
        let menu = NSMenu()
        let interfaces = SettingsManager.shared.getInterfaces()
        
        if interfaces.isEmpty {
            let emptyItem = NSMenuItem(title: "Interfaces: not yet set.", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for (index, interface) in interfaces.enumerated() {
                let item = NSMenuItem(title: interface.name, action: #selector(wakeInterface(_:)), keyEquivalent: "\(index + 1)")
                item.representedObject = interface.mac
                menu.addItem(item)
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    @objc func openSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow()
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func wakeInterface(_ sender: NSMenuItem) {
        guard let mac = sender.representedObject as? String else { return }
        sendWakeOnLan(macAddress: mac)
    }
    
    func sendWakeOnLan(macAddress: String) {
        let cleanMac = macAddress.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
        guard cleanMac.count == 12 else {
            print("Invalid MAC address")
            return
        }
        
        var macBytes = [UInt8]()
        for i in stride(from: 0, to: cleanMac.count, by: 2) {
            let start = cleanMac.index(cleanMac.startIndex, offsetBy: i)
            let end = cleanMac.index(start, offsetBy: 2)
            let hex = String(cleanMac[start..<end])
            if let byte = UInt8(hex, radix: 16) {
                macBytes.append(byte)
            }
        }
        
        guard macBytes.count == 6 else { return }
        
        var packet = Data()
        packet.append(contentsOf: [UInt8](repeating: 0xFF, count: 6))
        for _ in 0..<16 {
            packet.append(contentsOf: macBytes)
        }
        
        let connection = NWConnection(host: "255.255.255.255", port: NWEndpoint.Port(integerLiteral: 9), using: .udp)
        connection.start(queue: .global())
        connection.send(content: packet, completion: .contentProcessed { error in
            if let error = error {
                print("Send error: \(error)")
            } else {
                print("Magic packet sent to \(macAddress)")
            }
            connection.cancel()
        })
    }
}

let app = NSApplication.shared
let delegate = MacWolfApp()
app.delegate = delegate
app.run()
