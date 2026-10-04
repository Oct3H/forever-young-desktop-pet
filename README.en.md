# Forever Young · Standalone Desktop Pet v3.5

[简体中文](README.md)

An unofficial personal fan pet for Forever Young / フォーエバーヤング on Apple Silicon Macs, macOS 14+. v3.5 remembers run targets, adds automatic single-file execution in VS Code and switches controls by app card. Local Codex input, simultaneous status reception, prioritized notices, Anime/Minimal, three languages and the offline manual remain. Character assets are unchanged; see [CREDITS.md](CREDITS.md).

## Changelog

**v3.5 (since the last GitHub release of the standalone desktop pet, v2)**

- Added local Codex task integration and an official App Server input channel, with documented limits on controlling turns from other clients.
- Added VS Code and PyCharm plugins with lifecycle feedback; VS Code remembers run targets and runs supported single files directly.
- Added domestic and international GⅠ schedules, Forever Young's upcoming entries and historical results.
- Added the icon action bar, per-app controls, prioritized notices, Anime/Minimal styles and Chinese/Japanese/English UI.
- Added an offline connection manual, cache clearing and plugin installation instructions.

## Install and launch

1. Extract forever-young-desktop-macos-arm64.zip.
2. Quit the previous desktop pet through its context menu or 🐎 menu, then open 青春永驻桌宠.app. You may copy the complete application to your preferred folder.
3. Open signed-in Codex under the same macOS account. No extra pet account binding or API key is needed.
4. Install the included IDE plugins as described below and open a project.

Desktop versions share their application identifier to preserve position, size and preferences; run one at a time. v3.4.1 is preserved. This application runs independently of the native Codex pet selector. It does not replace the built-in pet renderer, modify macOS permissions/settings/login items, or require a separately hosted bridge server.

## Actions, status and primary source

Click the character to wave and play the original official greeting. Five icon buttons open the workspace, text composer, run shortcut, integration page, or close the bar. Tooltips and accessibility labels explain them. The bar follows the selected appearance, stays within the screen, and hides after fifteen seconds; dragging does not trigger a click.

A click shows the latest primary-source status with a randomly rotated text greeting. First-time status reminders take precedence; greetings never replace an unseen status update. No new or synthesized character voice was added. A currently displayed status reminder remains visible on repeated clicks.

Use workspace Settings to select Auto, Codex, VS Code or PyCharm. Auto prefers a connected foreground app, then the most recently changed active source, then connected Codex or a recently connected IDE. A fixed source does not silently change when disconnected. All three sources continue receiving events regardless of the selection; separate cards show project, task, status and active count.

Pending notifications prioritize failures, then completion/interruption, then ordinary states. Equal priorities favor the primary source, then arrival order. Existing status reminders stay visible for about six seconds. Duplicate events and heartbeats do not repeat notifications; historical completions are not replayed at startup. IDE heartbeats arrive every ten seconds and expire after approximately 35 seconds. Multiple windows/projects have separate instances; active instances take precedence within a source.

The linked-animation switch affects all sources. Dragging, hover jump and greeting interactions temporarily take precedence over status animation. Two styles and three languages persist locally; the workspace supports widths down to 320 px, wrapping and scrolling. The expandable module menu includes Codex, domestic/international GⅠ, Forever Young and Integrations.

## v3.5 workspace and manual

App integrations is now a third primary navigation entry beside Codex and races. Other modules remain in Features. The integration page shows the configured mode and actual primary source without a duplicate selector; change the source only in Settings. Connection instructions, diagnostics and the animation toggle are in Settings → User manual & connections. The offline manual covers pet controls, Codex, VS Code and PyCharm in all three UI languages.

Run project discovers existing/provider-detected tasks and debug configurations. Multiple candidates require one selection per workspace; later runs reuse it. Change run target saves without executing. Run current file supports Python, JavaScript and C/C++ single files using existing tools, without generating tasks.json. C17/C++17 compilation must succeed before running. Multi-file projects, libraries, special flags and tests still need their own configurations. Run/build/test remember separate targets.

Extracting and launching does not install plugins, generate configurations or patch IDE program files. Install the bundled 3.5.0 plugins and open your own projects; older bridge plugins need upgrading. Only user-directory plugins were upgraded on this Mac. IDE workspace/project storage remembers targets under the same user account.

The app is ad-hoc signed and not notarized; another Mac may require first-launch source confirmation. Compatibility with every app version is not guaranteed. Automatic setup was evaluated only: detecting existing tasks and proposing reviewable drafts are feasible, but universally inferring entry points, interpreters and arguments is unreliable. No automatic generation or overwrite is implemented.

## Direct Codex input and official events

Opening the composer captures the followed task and displays its title/project path. Sending revalidates that exact threadId instead of targeting a task that auto-follow may have switched to. Run/test/review shortcuts fill editable prompts; only the Send button starts execution. Copy and open Codex remains a fallback.

The installed official CLI App Server performs initialize, thread/resume and turn/start. Turns already started by this channel use turn/steer with expectedTurnId; stopping uses turn/interrupt. The adapter does not override model, sandbox or approval policy. Official lifecycle events drive working, waiting, review, completion, failure and interruption states. Prompt bodies, tool output and CLI stderr are not retained by the pet.

**Current-machine limitation: Codex Desktop does not expose a shared official control socket.** A private stdio channel starts the next turn on an idle existing thread and can steer/interrupt its own active turns. It cannot take over a turn running in another client; sending returns an explicit explanation. Existing Desktop work continues to use the read-only compatibility adapter. This is not a complete replacement client for all active Desktop turns. Desktop may need to reopen the thread to load a turn written by the other channel.

If an official app-server-control socket already exists, CLI proxy is preferred. The pet does not bootstrap a shared daemon or use private IPC/keyboard injection. The official interface remains experimental and may require compatibility updates.

Command/file approval requests for pet-started turns use a local confirmation dialog and are never automatically accepted. Other interactive request types are unsupported and explicitly rejected; use the full Codex client for those workflows. Existing-client tasks are approved in that client. Settings → User manual & connections → Codex separates reader and official-channel status and provides both checks; a connected official channel does not imply control of every Desktop turn.

The compatibility adapter reads SQLite metadata and selected JSONL lifecycle records once per second. It does not directly modify Codex databases, configuration, approvals or credentials. The default home is ~/.codex; launch from the same environment for a custom CODEX_HOME. CLI 0.160.0 was checked locally. Unsupported internal formats stop state inference with a diagnostic. The bridge stays local; normal Codex inference still uses the existing account/service.

## VS Code plugin

Install 联动插件/forever-young-vscode-3.5.0.vsix through Extensions → Install from VSIX… and reload the window. Source is in 联动插件/VSCode. Open your project and use saved tasks.json / launch.json configurations. The extension respects Workspace Trust and does not activate in Restricted Mode; trust only projects you consider safe.

Run/build/test reuse a remembered target, a sole candidate or a unique default. Ambiguous first choices and deleted/changed targets prompt again. Run current file uses the selected Python interpreter or existing .venv, existing Node.js, or an existing C/C++ compiler. Stop chooses an active task. Real Task lifecycle events determine success/failure; Debug termination has no universal exit code and reports interruption. Ordinary terminal commands are outside task events.

Minimum VS Code 1.90; actual start/success/failure events and the mailbox configuration picker were checked on 1.138.0.

## PyCharm plugin

Install 联动插件/forever-young-pycharm-3.5.0.zip through the IDE Plugins gear → Install Plugin from Disk… and restart PyCharm. Source is in 联动插件/PyCharm. No macOS System Settings changes are required. Open a project with an existing interpreter and saved Run/Debug configurations.

PyCharm run/test reuses a remembered target, otherwise the IDE-selected or sole configuration before asking once. Change run target saves without execution. Test filters test configuration types. Stop confirms the selected project’s processes. The official ExecutionListener maps exit zero to completion and nonzero to failure (130/143 to interruption). Console content and external Python processes are not monitored.

Requires PyCharm 2025.1+. Plugin loading, configuration selection and real Python success/failure events were checked on Community 2025.1.3.1.

## Local interface

PetCommand, IntegrationHub, official/compatibility Codex adapters, IDEBridge, animation and racing providers remain separate. IDEs exchange atomic JSON through ~/Library/Application Support/ForeverYoungPet/Bridge/ (events, commands, acks); no TCP/public listener exists.

Version-one event fields: source, instance UUID, sequence, sentAt (Unix milliseconds), state, runID, title, project and activeCount. IDE sources are vscode/pycharm; states are idle, working, waiting, review, completed, failed, interrupted or disconnected. Size, field, timestamp and sequence validation apply. Events exclude prompts and console text.

Only fixed supported actions are accepted: run, chooseRun, test, stop; VS Code also exposes build and runFile. Commands target the displayed source/instance and expire after fifteen seconds. ProcessExecution passes executable and arguments separately, without arbitrary shell text. A delivery ack is not task success; lifecycle events determine the result. The legacy fixed-state distributed notification remains available and executes no command.

## Racing and existing interactions

Domestic JRA flat GⅠ cards use yellow sidebars; international cards use pink plus text labels. Past/future seven-day views, results, official links, next-race fallback and Japanese-trained entry markers remain. International coverage combines major JAIRS, JRA overseas and Breeders’ Cup sources; it is not every worldwide GⅠ. Domestic jump GⅠ is excluded. Tentative/nominated/declared entries and uncertain identities are distinguished.

The Forever Young module shows the real horse’s published next-thirty-day plans and [JBIS historical results](https://www.jbis.or.jp/horse/0001339834/record/), not the game character’s career. Published post times display in Beijing time for Chinese, Tokyo time for Japanese and the venue’s IANA timezone for English, including DST. An unpublished time remains a local date with time pending; historical records keep official local dates.

Visible racing pages refresh every five minutes, and manual refresh bypasses cache. Offline fallback preserves the old timestamp; missing data is explicitly unconfirmed. Clear cache removes only this pet’s JRA/Racing cache files under ~/Library/Caches/org.foreveryoungpet.desktop/, without modifying Codex/IDE data or immediately rebuilding cache. Requests go directly from the Mac to official HTTPS sites; UI and images load locally without a CDN.

Sixteen-direction mouse gaze, one jump per hover entry, left/right running while dragging, official greeting/wave, breathing idle, saved position/size and action previews remain. The atlas is 1536×2288, 73 cells of 192×208; the original MP3 is approximately 2.912 seconds. v3.5 adds no new sprite frames or source resolution.

## Build and verification

重新编译.command uses existing Apple Command Line Tools to compile Swift, copy UI resources and ad-hoc sign the app. No third-party runtime dependencies are installed. The VS Code extension has no npm runtime dependencies. PyCharm uses the installed SDK/JBR and does not package IDE classes. Build records, isolated fixtures, offline pages and verification reports are kept separately in 桌面交互版制作过程v3.5.

Native interaction, three-source arbitration, official routing, both styles × three languages at narrow widths, racing parsing and caching were checked again. Separate SDK checks cover target memory, stale-target reselection, literal arguments and compilation success/failure. Isolated real projects on VS Code 1.138.0 and PyCharm CE 2025.1.3.1 verify pet-button execution, reselection without execution, reuse without another picker and start/success/failure events. VS Code single-file compilation and no-run-after-failure are also live checks. Evidence is stored separately in the process folder. Official initialize and read-only thread/read are live checks; model send/steer use isolated fixtures, with no real model instruction submitted this iteration.

The repository-root SHA256SUMS.txt verifies the downloadable archive; the archive contains its own app, source, plugin and archive checksum manifests. v3.4.1 is checked against its original full-file snapshot.

References: [Codex App Server](https://learn.chatgpt.com/docs/app-server), [VS Code API](https://code.visualstudio.com/api/references/vscode-api), [JetBrains Execution API](https://plugins.jetbrains.com/docs/intellij/execution.html).

Setup references: [VS Code extension installation](https://code.visualstudio.com/docs/configure/extensions/extension-marketplace), [VS Code Tasks](https://code.visualstudio.com/docs/debugtest/tasks), [PyCharm plugins](https://www.jetbrains.com/help/pycharm/managing-plugins.html), [PyCharm run configurations](https://www.jetbrains.com/help/pycharm/run-debug-configuration.html).

App cards select an operation target independently of notification priority. Codex exposes reviewed input/run/test/review drafts and official stop. VS Code exposes run/change target/current file/build/test/stop. PyCharm exposes run/change target/test/stop. Commands lock the displayed IDE instance; offline/unsupported controls are disabled.
