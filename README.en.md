# Forever Young — Standalone macOS Desktop Pet

An unofficial fan-made desktop pet featuring Forever Young from Cygames' *Umamusume: Pretty Derby*, using her official race-outfit design, the v2 sprite sheet, and original official voice audio.

## Requirements and installation

- Apple Silicon Mac (`arm64`)
- macOS 14 or later

Download and extract `forever-young-desktop-macos-arm64.zip` from this repository, then double-click the included `青春永驻桌宠.app`. It runs independently of Codex; it is not installed through the Codex Pets list. To rebuild from source, install Apple's Command Line Tools, then run the included `重新编译.command`.

## Interactions

- Her head and eyes follow the mouse across the desktop.
- Entering her fixed hover area triggers one jump. Staying over her does not repeat it; leaving and entering again can trigger another jump.
- Clicking her plays the original official voice and starts a wave. A new click restarts the same audio without overlapping it.
- After jumping or waving, she returns to the gaze direction for the current mouse position.
- Drag her to move the window. A drag does not trigger the click greeting.
- Use the right-click menu or the 🐎 menu-bar item to toggle mouse interaction, preview the nine animation states, show or hide her, reset her position, or quit.

The app uses a transparent, borderless floating window. It does not take keyboard focus from the active app, access the network, modify Codex, or launch at login. Quitting stops audio and mouse tracking.

## Image and audio

The 1536×2288 sheet contains 57 animation frames and 16 gaze cells. Each source cell is 192×208 pixels. The app converts the lossless WebP sheet to PNG with identical RGBA pixels; displaying it larger does not add source detail. Its 60 Hz update schedule is not 60 distinct animation frames.

The voice is unedited audio from the official character page, voiced by Shuri Umiumi. See `CREDITS.md` for the source and checksum. Character and official material rights belong to Cygames and their respective rights holders. This is an unofficial, non-commercial fan project.

## Included files

- `青春永驻桌宠.app`: ready-to-run macOS app.
- `源码/`: Swift source code.
- `重新编译.command`: rebuild script using Apple's Command Line Tools; no third-party packages are required.
- `forever-young-desktop-macos-arm64.zip`: packaged app and source.
- `SHA256SUMS.txt`: SHA-256 checksum for the ZIP.
