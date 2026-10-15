# Proofread

Menu-bar app for macOS: select text in any app, click the **✨ Edit** button that appears (or press **⌃⌥E**), then pick an edit. The AI result replaces the selection.

The Edit button shows after a drag-select or double/triple-click, and hides on the next click, keypress, scroll, or after 4 seconds.
Turn it off from the menu bar icon → Show Edit Button on Selection. Your clipboard is only touched when you click it.

- Type a custom instruction and press Return, or use the quick actions: Proofread ⌘1, Improve ⌘2, Shorter ⌘3, Longer ⌘4, Professional ⌘5, Casual ⌘6.
- Esc closes the panel. ⌘Z in the target app undoes the replacement.
- Works with Gemini (default, free tier is enough) or OpenAI. API keys are stored in the macOS Keychain.
- Settings (menu bar icon) lists your account's models live, marked ⚡ fastest/cheapest, ⭐ balanced, 🧠 smartest, ❔ unrated new name.

## Build and run

Requires macOS 14+ and the Xcode command-line tools.

```bash
git clone https://github.com/shivam1410/mac-proofread.git
cd mac-proofread
./build.sh
```

This builds, runs the self-test, signs, installs to `/Applications/Proofread.app`, and restarts the app.

On first launch:
1. Enter your API key in the Settings dialog (Gemini: aistudio.google.com/apikey).
2. Grant Accessibility access: System Settings → Privacy & Security → Accessibility → enable Proofread. It is needed to send ⌘C/⌘V.

`build.sh` signs with the first code-signing identity in your keychain (override with `SIGN_IDENTITY=...`).
That keeps the app's identity stable, so the Accessibility and Keychain grants survive rebuilds.
With no identity it falls back to ad-hoc signing, and macOS asks again after every rebuild.

Start at Login is on by default; turn it off from the menu bar icon → Start at Login.
