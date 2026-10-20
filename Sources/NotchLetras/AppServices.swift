import AppKit
import Carbon
import ServiceManagement

struct SongPreferences {
    let defaults: UserDefaults
    func offset(for key: String) -> Double { (defaults.dictionary(forKey: "songOffsets")?[key] as? Double) ?? 0 }
    func setOffset(_ value: Double, for key: String) {
        guard value.isFinite else { return }
        var offsets = defaults.dictionary(forKey: "songOffsets") ?? [:]
        offsets[key] = min(10, max(-10, value))
        defaults.set(offsets, forKey: "songOffsets")
    }
}

@MainActor final class LoginItem: ObservableObject {
    @Published var enabled = false
    @Published var status = ""
    func refresh() {
        let value = SMAppService.mainApp.status
        enabled = value == .enabled || value == .requiresApproval
        switch value {
        case .enabled: status = "Se abrirá al iniciar sesión."
        case .requiresApproval: status = "Pendiente de aprobación en Ajustes del Sistema → General → Ítems de inicio."
        case .notRegistered: status = "Inicio automático desactivado."
        default: status = "macOS no encuentra el registro de esta app."
        }
    }
    func setEnabled(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refresh()
        } catch {
            refresh(); status = "No se pudo cambiar el inicio automático: \(error.localizedDescription)"
        }
    }
}

@MainActor final class GlobalShortcut {
    var handler: EventHandlerRef?
    var hotkey: EventHotKeyRef?
    var escape: EventHotKeyRef?
    var localMonitor: Any?
    var selection = "off"
    var action: (() -> Void)?
    var close: (() -> Void)?
    static let signature: OSType = 0x4E4C5952
    func install() {
        guard handler == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let expected: NSEvent.ModifierFlags = self.selection == "cmdOptionL" ? [.command, .option] : (self.selection == "ctrlOptionL" ? [.control, .option] : [.command, .shift])
            if self.selection != "off", event.keyCode == UInt16(kVK_ANSI_L), flags == expected {
                self.action?(); return nil
            }
            if self.escape != nil, event.keyCode == UInt16(kVK_Escape), flags.isEmpty { self.close?(); return nil }
            return event
        }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == GlobalShortcut.signature else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                let owner = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
                if id.id == 2 { owner.close?() } else { owner.action?() }
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register(_ selection: String) -> Bool {
        install()
        self.selection = selection
        if let hotkey { UnregisterEventHotKey(hotkey); self.hotkey = nil }
        if selection == "off" { return true }
        let modifiers: UInt32
        switch selection {
        case "cmdOptionL": modifiers = UInt32(cmdKey | optionKey)
        case "ctrlOptionL": modifiers = UInt32(controlKey | optionKey)
        default: modifiers = UInt32(cmdKey | shiftKey)
        }
        return RegisterEventHotKey(UInt32(kVK_ANSI_L), modifiers, EventHotKeyID(signature: Self.signature, id: 1), GetApplicationEventTarget(), 0, &hotkey) == noErr
    }
    func captureEscape(_ enabled: Bool) {
        if let escape { UnregisterEventHotKey(escape); self.escape = nil }
        if enabled {
            _ = RegisterEventHotKey(UInt32(kVK_Escape), 0, EventHotKeyID(signature: Self.signature, id: 2), GetApplicationEventTarget(), 0, &escape)
        }
    }
    func stop() {
        if let hotkey { UnregisterEventHotKey(hotkey) }
        if let escape { UnregisterEventHotKey(escape) }
        if let handler { RemoveEventHandler(handler) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        hotkey = nil; escape = nil; handler = nil
    }
}
