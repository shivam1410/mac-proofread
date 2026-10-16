// Shows a small ✨ button next to the cursor after the user selects text in another app.
import AppKit
import Carbon.HIToolbox
import SwiftUI

enum AXSelection { case text, empty, unknown }

/// Electron/Chromium apps (Notion, Slack, Claude) only build their accessibility tree for
/// assistive tools; this flag asks them to, so selection and editability become readable.
func enableAppAccessibility() {
    guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.2)
    _ = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue) // non-Electron apps reject it; fine
}

func focusedElement() -> AXUIElement? {
    enableAppAccessibility()
    let system = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(system, 0.2) // don't stall on a hung app
    var focused: CFTypeRef?
    guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
          let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
    return (focused as! AXUIElement) // swiftlint:disable:this force_cast
}

/// The focused app's selected text, read without touching the clipboard; nil when the app doesn't say.
func axSelectedText() -> String? {
    guard let element = focusedElement() else { return nil }
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success else { return nil }
    return value as? String
}

func axSelection() -> AXSelection {
    guard let text = axSelectedText() else { return .unknown }
    return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .empty : .text
}

/// Text fields count when their value is writable; web/Electron content when it sits inside a contenteditable.
func isEditable(role: String?, valueSettable: Bool, hasEditableAncestor: Bool) -> Bool {
    let fieldRoles = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
    return hasEditableAncestor || (fieldRoles.contains(role ?? "") && valueSettable)
}

/// Whether pasting would land in an editable field. Unknown counts as not editable,
/// so results are shown instead of pasted into nowhere.
func focusedTextIsEditable() -> Bool {
    guard let element = focusedElement() else { return false }
    var role: CFTypeRef?
    _ = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
    var settable = DarwinBoolean(false)
    _ = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
    var ancestor: CFTypeRef?
    let hasAncestor = AXUIElementCopyAttributeValue(element, "AXEditableAncestor" as CFString, &ancestor) == .success
        && ancestor != nil
    return isEditable(role: role as? String, valueSettable: settable.boolValue, hasEditableAncestor: hasAncestor)
}

/// Screen point (Cocoa coordinates) at the top-right of the selection, when the app exposes it.
func axSelectionAnchor() -> NSPoint? {
    guard let element = focusedElement() else { return nil }
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

/// Icon clicks open the menu on right/⌃-click, without Accessibility, or when the app reports an empty
/// selection. Otherwise they try to edit; apps like Google Sheets report nothing, so ⌘C decides.
func iconClickOpensMenu(rightClick: Bool, control: Bool, trusted: Bool, selection: AXSelection) -> Bool {
    rightClick || control || !trusted || selection == .empty
}

/// Keys that extend a text selection: ⇧ + arrows/Home/End/Page Up/Down, or ⌘A.
func isSelectionKey(keyCode: Int, flags: NSEvent.ModifierFlags) -> Bool {
    let extendKeys = [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
                      kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown]
    if flags.contains(.shift) && extendKeys.contains(keyCode) { return true }
    return keyCode == kVK_ANSI_A && flags.contains(.command) && !flags.contains(.shift)
}

/// A drag or double/triple click counts only when it left a new, non-empty selection. Dragging a
/// window, tab or scrollbar leaves the selection unreadable or unchanged, so it gets no button.
func shouldOfferButton(dragDistance: CGFloat, clickCount: Int, before: String?, after: String?) -> Bool {
    guard dragDistance > 6 || clickCount >= 2,
          let after, !after.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
    return after != before
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    // One click should press the button, not just focus the panel.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct SelectionButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color(white: 0.2), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1)) // keeps the edge visible on dark apps
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                .padding(4) // room for the shadow inside the panel
        }
        .buttonStyle(.plain)
        .help("Edit or summarize with AI")
        .accessibilityLabel("Edit or summarize with AI")
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
    private var selectionAtPress: String?
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
        // Selections inside Proofread's own windows (e.g. the API key field) never get the button.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            hide()
            return
        }
        switch event.type {
        case .leftMouseDown:
            mouseDownAt = NSEvent.mouseLocation
            // Only the first click of a double-click: by the second, the app may already have selected the word.
            if event.clickCount <= 1 { selectionAtPress = axSelectedText() }
            hide()
        case .leftMouseUp:
            let up = NSEvent.mouseLocation
            let distance = hypot(up.x - mouseDownAt.x, up.y - mouseDownAt.y)
            let clicks = event.clickCount
            let before = selectionAtPress
            guard Self.isEnabled, !isSuppressed(), distance > 6 || clicks >= 2 else { return }
            Task {
                await sleepMs(60) // let the app finish updating its selection
                if shouldOfferButton(dragDistance: distance, clickCount: clicks, before: before, after: axSelectedText()) { show(at: up) }
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
        panel.hasShadow = false // the button draws its own shadow
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
