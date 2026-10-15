# Proofread

Menu-bar app for macOS that edits, summarizes, or answers questions about text you select in any app.
Bring your own Gemini or OpenAI API key.

## How it works

Select text, then click the **✨** button that appears next to it, or press **⌃⌥E**. A panel opens with:

- **A prompt box.** Type any instruction and press Return.
- **Quick actions:** Proofread, Shorten, Formal, Summarise.

What happens to the result depends on where the text is:

| Selection | Edits (Proofread, Shorten, Formal, typed instructions) | Summarise |
|---|---|---|
| Editable text (Notion page, text field) | Replace the selection. ⌘Z in the app undoes it. | Shown in the panel |
| Read-only text (chat, web page) | Shown in the panel. Typed prompts are answered as questions, e.g. "who said what?" | Shown in the panel |

Results shown in the panel are formatted Markdown: nested bullets (● ○ ▪), numbered lists, headings, **bold**, *italic*.
Use **Copy** (keeps the Markdown, so it pastes formatted into Notion) or **Replace Selection**. Esc closes the panel.

The ✨ button appears after a drag-select, a double/triple-click, or a keyboard selection (⇧ + arrows, ⌘A).
It hides on the next click, keypress, scroll, or after 4 seconds. Your clipboard is only touched when you use it, and is restored afterwards.

## Settings

Menu bar icon → **Settings…** (the menu has just Settings and Quit):

- **Provider and API key**: Gemini (free tier is enough; key from aistudio.google.com/apikey) or OpenAI (platform.openai.com/api-keys).
- **Model**: your account's live model list, marked ⚡ fastest/cheapest, ⭐ balanced, 🧠 smartest, ❔ new name, unrated.
  Markers are guessed from model names. ⚡ models such as `gpt-6-luna` or `gemini-flash-lite-latest` are plenty for proofreading.
- **Show ✨ button when text is selected**: on by default.
- **Start at login**: on by default.

## Build and install

Requires macOS 14+ and the Xcode command-line tools.

```bash
git clone https://github.com/shivam1410/mac-proofread.git
cd mac-proofread
./build.sh
```

`build.sh` compiles, runs the self-test, generates the icon, signs, installs to `/Applications/Proofread.app`, and restarts the app.

On first launch:
1. Paste your API key in Settings and click Save.
2. Grant Accessibility access when asked (System Settings → Privacy & Security → Accessibility → Proofread).
   It is needed to read the selection and send ⌘C/⌘V.

### Signing and permissions

`build.sh` signs with the first code-signing identity in your keychain (override with `SIGN_IDENTITY=...`).
A stable identity keeps the Accessibility grant across rebuilds. With no identity it falls back to ad-hoc signing,
and Accessibility must be re-granted after every rebuild.

API keys for all providers are stored together in one Keychain item, "Proofread – API keys".
With a self-signed identity, macOS asks once after each rebuild to let the new build read it; choose **Always Allow**.

## Code

| File | Contents |
|---|---|
| `main.swift` | App, panel, settings, AI requests, Keychain, self-test (`--selftest`) |
| `SelectionWatcher.swift` | ✨ button, selection and editability detection via Accessibility |
| `MarkdownView.swift` | Markdown rendering for results |
| `make_icon.swift` | Draws the app icon at build time |
