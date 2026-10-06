# フォーエバーヤング · macOS Desktop Pet v3.7

[中文](README.md)

An unofficial standalone Forever Young desktop companion for **Apple Silicon Macs running macOS 14+**. It uses the racing outfit, character recordings, local Codex/VS Code/PyCharm integration and a racing workspace. Launch the `.app`; this is separate from a native Codex pet asset pack.

## Download and launch

1. [Download the desktop ZIP](https://github.com/Oct3H/forever-young-desktop-pet/raw/refs/heads/main/forever-young-desktop-macos-arm64.zip) and extract the complete folder.
2. Quit the previous pet through its context or 🐎 menu, then open `青春永驻桌宠.app`. Copy the whole application to a preferred folder if desired. No compilation is needed for normal use.
3. Click or right-click the pet to open controls. The 🐎 menu shows/hides the pet, resets its position and quits.
4. Settings choose Anime/Minimal appearance, Chinese/Japanese/English, primary integration source and notification preferences.

Versions share preferences; run one at a time. This build is ad-hoc signed and not Apple-notarized; another Mac may require first-launch source confirmation. Launching does not automatically install plugins, change macOS permissions/login items or patch IDE core files. No separately hosted cloud bridge is required.

## Features

- Sixteen-direction mouse gaze, one jump per hover entry, left/right running while dragging, wave and randomized original greetings; nine animations and a 73-cell atlas.
- Larger five-icon bar: workspace, input, Run preview, integrations and dismiss; tooltips explain each action.
- Seventeen identity-checked character recordings, five scene switches, volume, audition and daily quiet hours. UI language does not synthesize or translate the recordings.
- All three app sources remain subscribed. The primary source controls character status; app cards select the operation target. Failures take priority over completion/interruption and ordinary notices; heartbeats are deduplicated.
- Preview project, target, file and existing tool before IDE execution. A changed target rejects the stale preview. Selecting a target does not run it; Run/Build/Test remember separate choices.
- Up to 200 local summary records, source filters, task/console jumps, approximate duration and Problems access; no chat bodies or console transcripts are retained.
- Manual Focus/Meeting mode, right-edge parking, pausable Pomodoro and a five-minute break.
- Domestic JRA flat GⅠ and major international GⅠ, Japanese-entry markers, the real Forever Young horse’s published plans and JBIS historical results; visible sources, confirmation/cache timestamps and manual cache clearing.
- Published post times use Beijing time in Chinese, Tokyo in Japanese and the venue’s timezone in English. Unknown times stay unknown. Optional start/entry-change reminders and `.ics` export require the app to be running.

## Connect Codex

Open signed-in Codex under the same macOS user. The pet reads `~/.codex` by default; no extra pet account or API key is required. For custom `CODEX_HOME`, launch in the same environment. Select a followed task in the workspace; Settings → User manual & connections checks the compatibility reader and official channel separately.

The composer captures and revalidates its task. The installed official CLI App Server starts the next turn on an idle existing thread and can continue/stop turns it started. Run/test/review shortcuts fill editable drafts; sending is explicit. Existing approval policy is preserved, with local approval dialogs where supported.

**It cannot take over a turn running in another Codex client.** Existing Desktop turns still have read-only status following. Desktop may need to reopen a thread to show another channel’s new turn. Use the original client for unsupported special authorization/interactive requests. The official interface is experimental; local storage formats can change. The bridge is local, while normal Codex inference still uses its existing account/service.

## Connect VS Code

1. Extensions menu → **Install from VSIX…** → select the [3.7.0 installer](联动插件/forever-young-vscode-3.7.0.vsix), then reload the window.
2. Open your project. Workspace Trust is enforced; Restricted Mode does not execute and the plugin does not change trust settings.
3. Integrations → VS Code: verify the preview before running. Multiple candidates require one initial choice; later runs reuse it. A unique/default target can be used directly.
4. Run current file supports Python, JavaScript and C/C++ using existing interpreters, Node or compilers. Failed compilation never launches a stale executable. Complex projects, arguments and tests require valid project configuration.

Controls include Run, change target, current file, Build, Test, Stop, Problems and terminal. Task exit codes determine success/failure. Debug termination has no universal exit code and reports interruption. Arbitrary terminal commands are outside Task events. Minimum VS Code 1.90; local verification used 1.140.0.

## Connect PyCharm

1. IDE Plugins gear → **Install Plugin from Disk…** → select the [3.7.0 installer](联动插件/forever-young-pycharm-3.7.0.zip), then restart PyCharm.
2. Open a project with an existing interpreter and saved Run/Debug Configuration.
3. Integrations → PyCharm: verify the target before running. The selected/sole configuration is used first; ambiguous choices prompt once and are remembered per project.

Controls include Run, change target, Test, Stop, Problems and Run console. Official ExecutionListener events report start/exit; zero means completion, nonzero failure, and common stop codes interruption. Requires PyCharm 2025.1+; local verification used CE 2025.1.3.1. Every IDE version and other Macs have not been tested.

Both bridge plugins must be updated to **3.7.0**. Older versions can report basic status but lack preview metadata, so execution controls are disabled. Atomic JSON mailboxes under the same user connect the IDEs and pet; there is no public network listener or IDE core modification.

## Manuals and files

- [v3.7 usage supplement](v3.7使用补充.md), in Chinese: preview, quiet policies, history, timers, reminders, calendar and diagnostics.
- [Word operation manual](手册/青春永驻桌宠操作手册.docx), in Chinese: keeps the **v3.6 baseline**. Use the **3.7.0** installers named here instead of its old installer names; new controls are covered by the supplement.
- [Voice provenance/trigger guide](语音来源与触发说明.md) and [credits](CREDITS.md).
- `源码/`: Swift; `界面/`: local HTML/CSS/JavaScript; `联动插件/`: installers and source; `.app`: ready-to-run product.
- `重新编译.command` uses existing Apple Command Line Tools, copies UI resources and ad-hoc signs. No third-party runtime dependency is required.
- `SHA256SUMS.txt` verifies the app and related files; `ARCHIVE-SHA256.txt` verifies the public ZIP.

Local state lives in `~/Library/Application Support/ForeverYoungPet/`; racing caches in `~/Library/Caches/org.foreveryoungpet.desktop/`. History and racing-cache clearing are independent and do not delete Codex tasks or IDE projects.

## Changelog

**v3.7 (2026-10-06, since the repository’s v3.5)**

- Expanded character recordings to seventeen, with randomized/contextual playback, volume and quiet controls.
- Added the Word operation manual and offline supplement; delivery checks require both plugins, working documentation links, resource hashes, signatures and extracted-archive readback.
- Enlarged bottom icons 15→25pt, buttons 38×34→52×46 and workspace icons 16→22px.
- Upgraded both IDE plugins to 3.7.0; added Run previews, target fingerprints and connection diagnostics.
- Added summary history, task duration, recent executions, Problems/console controls.
- Added Focus/Meeting, edge parking, Pomodoro and five-minute breaks.
- Added confirmed-time start reminders, candidate-to-declared alerts and calendar export. Extra race alerts default to off.
- 160 checks passed. Isolated real projects verified VS Code success and intentional PyCharm failure feedback. Codex reading and official initialization/read succeeded; model submission used isolated protocol tests without a real task instruction. Not every app version or other Mac was tested.

**v3.5**: three-app local integration, remembered targets/supported single-file execution, official Codex input channel, racing workspace, icon bubbles, two styles/three languages and cache clearing.

Character artwork and recordings belong to Cygames and the respective rights holders. This unofficial project uses an AI-assisted sprite atlas; attribution and recording sources are documented in Credits.
