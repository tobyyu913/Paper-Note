# Paper Note

A skeuomorphic notebook app. A leather-bound book on a shelf that you open,
write in on ruled paper, and flip through page by page — with a two-page
spread in full screen, Touch ID / passcode locking, and PNG / PDF export.

## ⬇️ Download

**[Download the latest macOS app →](https://github.com/tobyyu913/Paper-Note/releases/latest)**

1. Open the link above and download `PaperNote-macOS.zip` from the **Assets**.
2. Unzip it and drag **Paper Note.app** into your `/Applications` folder.
3. The app isn't notarized, so the first time you open it macOS will warn that
   it's from an unidentified developer. **Right-click the app → Open → Open**
   (you only need to do this once).

Requires macOS 14 or later.

## Features

- 📖 A leather notebook you open and flip through, with a page-curl turn.
- 🖥️ **Full screen** shows an open two-page spread; the window shows one page.
- 🔒 **Touch ID / passcode lock** — every notebook unlocks with your fingerprint
  or a passcode (`paper note` by default; change it from the shelf).
- ✍️ Ruled paper with handwriting-style text that sits on the lines.
- 📸 Save a page as a PNG, or export the whole notebook as a PDF.
- 🎨 Pick from several leather cover colors.

## Build from source

```sh
git clone https://github.com/tobyyu913/Paper-Note.git
cd "Paper-Note"
open "Paper Note.xcodeproj"
```

Then build and run the **Paper Note** scheme in Xcode (macOS target).

An Android version lives in [`android/`](android/) and builds with Gradle.
