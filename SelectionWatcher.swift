// Shows a small "Edit" button next to the cursor after the user selects text in another app.
import AppKit
import Carbon.HIToolbox
import SwiftUI

enum AXSelection { case text, empty, unknown }

/// Asks the focused app for its selected text without touching the clipboard.
/// Many Electron apps (Notion, Slack) don't answer, which gives `.unknown`.
func axSelection() -> AXSelection {
    let system = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(system, 0.2) // don't stall on a hung app
    var focused: CFTypeRef?
    guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
          let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return .unknown }
    var value: CFTypeRef?
    // swiftlint:disable:next force_cast
    guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &value) == .success,
          let text = value as? String else { return .unknown }
    return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .empty : .text
}

/// Screen point (Cocoa coordinates) at the top-right of the selection, when the app exposes it.
func axSelectionAnchor() -> NSPoint? {
    let system = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(system, 0.2)
    var focused: CFTypeRef?
    guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
          let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
    let element = focused as! AXUIElement // swiftlint:disable:this force_cast
    var range: CFTypeRef?
    var bounds: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &range) == .success,
          let range,
          AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                     range, &bounds) == .success,
          let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }
    var rect = CGRect.zero
    guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect), rect.width > 0 else { return nil } // swiftlint:disable:this force_cast
    // AX uses top-left origin on the primary screen; Cocoa uses bottom-left.
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    return NSPoint(x: rect.maxX, y: primaryHeight - rect.minY)
}

/// Keys that extend a text selection: ⇧ + arrows/Home/End/Page Up/Down, or ⌘A.
func isSelectionKey(keyCode: Int, flags: NSEvent.ModifierFlags) -> Bool {
    let extendKeys = [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
                      kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown]
    if flags.contains(.shift) && extendKeys.contains(keyCode) { return true }
    return keyCode == kVK_ANSI_A && flags.contains(.command) && !flags.contains(.shift)
}

/// A drag or double/triple click may have selected text; skip only when the app says nothing is selected.
func shouldOfferButton(dragDistance: CGFloat, clickCount: Int, selection: AXSelection) -> Bool {
    (dragDistance > 6 || clickCount >= 2) && selection != .empty
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    // One click should press the button, not just focus the panel.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct SelectionButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Edit", systemImage: "sparkles")
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator))
    }
}

@MainActor final class SelectionWatcher {
    private static let enabledKey = "showButtonOnSelect"
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Return true while the edit panel is open, so selections inside it don't spawn a button.
    var isSuppressed: () -> Bool = { false }
    private let onPick: () -> Void
    private var mouseDownAt = NSPoint.zero
    private var button: NSPanel?
    private var hideTask: Task<Void, Never>?
    private var keySelectTask: Task<Void, Never>?

    init(onPick: @escaping () -> Void) { self.onPick = onPick }

    /// Lives for the whole app run, so the monitor is never removed.
    func start() {
        _ = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .keyDown, .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            mouseDownAt = NSEvent.mouseLocation
            hide()
        case .leftMouseUp:
            let up = NSEvent.mouseLocation
            let distance = hypot(up.x - mouseDownAt.x, up.y - mouseDownAt.y)
            let clicks = event.clickCount
            guard Self.isEnabled, !isSuppressed(), distance > 6 || clicks >= 2 else { return }
            Task {
                await sleepMs(60) // let the app finish updating its selection
                if shouldOfferButton(dragDistance: distance, clickCount: clicks, selection: axSelection()) { show(at: up) }
            }
        case .keyDown where isSelectionKey(keyCode: Int(event.keyCode), flags: event.modifierFlags):
            hide()
            guard Self.isEnabled, !isSuppressed() else { return }
            // Wait until the user stops extending the selection, then offer the button once.
            keySelectTask?.cancel()
            keySelectTask = Task { [weak self] in
                await sleepMs(400)
                guard !Task.isCancelled, let self, !self.isSuppressed() else { return }
                if axSelection() != .empty { self.show(at: axSelectionAnchor() ?? NSEvent.mouseLocation) }
            }
        default:
            keySelectTask?.cancel()
            hide()
        }
    }

    private func show(at point: NSPoint) {
        hide()
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.becomesKeyOnlyIfNeeded = true
        let host = FirstMouseHostingView(rootView: SelectionButton { [weak self] in
            self?.hide()
            self?.onPick()
        })
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        panel.setFrameOrigin(NSPoint(x: point.x + 8, y: point.y + 12)) // just above-right of the cursor
        panel.orderFrontRegardless()
        button = panel
        hideTask = Task { [weak self] in
            await sleepMs(4000)
            if !Task.isCancelled { self?.hide() }
        }
    }

    private func hide() {
        hideTask?.cancel()
        hideTask = nil
        button?.orderOut(nil)
        button = nil
    }
}
