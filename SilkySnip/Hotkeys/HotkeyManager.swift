//
//  HotkeyManager.swift
//  SilkySnip
//
//  Copyright © 2024-2026 Silky Apple Technologies. All rights reserved.
//  This source code is proprietary and confidential.
//  Unauthorized copying, modification, or distribution is strictly prohibited.
//

import Cocoa
import Carbon.HIToolbox

class HotkeyManager {
    
    // MARK: - Properties
    
    private var registeredHotkeys: [UInt32: HotkeyRegistration] = [:]
    private var nextHotkeyID: UInt32 = 1
    
    private var eventHandlerRef: EventHandlerRef?
    
    // MARK: - Initialization
    
    init() {
        installEventHandler()
    }
    
    deinit {
        unregisterAll()
        
        if let handlerRef = eventHandlerRef {
            RemoveEventHandler(handlerRef)
            // M9: Release the retained self reference from installEventHandler
            Unmanaged.passUnretained(self).release()
        }
    }
    
    // MARK: - Registration
    
    func register(_ hotkey: Hotkey, handler: @escaping () -> Void) throws {
        let hotkeyID = nextHotkeyID
        nextHotkeyID += 1
        
        var eventHotKey: EventHotKeyRef?
        var hotkeyIDStruct = EventHotKeyID(signature: OSType(0x5156_574B), id: hotkeyID)  // 'QVWK'
        
        let status = RegisterEventHotKey(
            hotkey.carbonKeyCode,
            hotkey.carbonModifiers,
            hotkeyIDStruct,
            GetApplicationEventTarget(),
            0,
            &eventHotKey
        )
        
        guard status == noErr, let hotKeyRef = eventHotKey else {
            throw HotkeyError.registrationFailed(hotkey: hotkey)
        }
        
        let registration = HotkeyRegistration(
            id: hotkeyID,
            hotkey: hotkey,
            hotKeyRef: hotKeyRef,
            handler: handler
        )
        
        registeredHotkeys[hotkeyID] = registration
        
        print("Registered hotkey: \(hotkey)")
    }
    
    func unregisterAll() {
        for registration in registeredHotkeys.values {
            UnregisterEventHotKey(registration.hotKeyRef)
        }
        registeredHotkeys.removeAll()
    }
    
    // MARK: - Event Handling
    
    private func installEventHandler() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let handlerBlock: EventHandlerUPP = { (_, event, userData) -> OSStatus in
            guard let event = event, let userData = userData else { return OSStatus(eventNotHandledErr) }
            
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            return manager.handleHotKeyEvent(event)
        }
        
        // M9: Use passRetained to prevent dangling pointer if object deallocates before handler removal
        let retained = Unmanaged.passRetained(self)
        
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            handlerBlock,
            1,
            &eventSpec,
            retained.toOpaque(),
            &eventHandlerRef
        )
        
        if status != noErr {
            // Release since handler wasn't installed
            retained.release()
            print("Failed to install hotkey event handler: \(status)")
        }
    }
    
    private func handleHotKeyEvent(_ event: EventRef) -> OSStatus {
        var hotkeyID = EventHotKeyID()
        
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotkeyID
        )
        
        guard status == noErr else { return status }
        
        if let registration = registeredHotkeys[hotkeyID.id] {
            DispatchQueue.main.async {
                registration.handler()
            }
            return noErr
        }
        
        return OSStatus(eventNotHandledErr)
    }
}

// MARK: - Hotkey

struct Hotkey: CustomStringConvertible {
    let key: KeyCode
    let modifiers: KeyModifiers
    
    var carbonKeyCode: UInt32 {
        key.carbonCode
    }
    
    var carbonModifiers: UInt32 {
        modifiers.carbonFlags
    }
    
    var description: String {
        var parts: [String] = []
        
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        
        parts.append(key.displayName)
        
        return parts.joined()
    }
}

// MARK: - Key Code

enum KeyCode: UInt32 {
    case a = 0x00
    case b = 0x0B
    case c = 0x08
    case d = 0x02
    case e = 0x0E
    case f = 0x03
    case g = 0x05
    case h = 0x04
    case i = 0x22
    case j = 0x26
    case k = 0x28
    case l = 0x25
    case m = 0x2E
    case n = 0x2D
    case o = 0x1F
    case p = 0x23
    case q = 0x0C
    case r = 0x0F
    case s = 0x01
    case t = 0x11
    case u = 0x20
    case v = 0x09
    case w = 0x0D
    case x = 0x07
    case y = 0x10
    case z = 0x06
    
    case plus = 0x18      // = key (shift for +)
    case minus = 0x1B
    
    var carbonCode: UInt32 {
        rawValue
    }
    
    var displayName: String {
        switch self {
        case .plus: return "+"
        case .minus: return "-"
        default: return String(describing: self).uppercased()
        }
    }
}

// MARK: - Key Modifiers

struct KeyModifiers: OptionSet {
    let rawValue: UInt32
    
    static let command = KeyModifiers(rawValue: 1 << 0)
    static let shift = KeyModifiers(rawValue: 1 << 1)
    static let option = KeyModifiers(rawValue: 1 << 2)
    static let control = KeyModifiers(rawValue: 1 << 3)
    
    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        
        if contains(.command) { flags |= UInt32(cmdKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.control) { flags |= UInt32(controlKey) }
        
        return flags
    }
}

// MARK: - Registration Record

private struct HotkeyRegistration {
    let id: UInt32
    let hotkey: Hotkey
    let hotKeyRef: EventHotKeyRef
    let handler: () -> Void
}

// MARK: - Error

enum HotkeyError: LocalizedError {
    case registrationFailed(hotkey: Hotkey)
    
    var errorDescription: String? {
        switch self {
        case .registrationFailed(let hotkey):
            return "Failed to register hotkey: \(hotkey). It may conflict with another application."
        }
    }
}
