'use strict';
(() => {
  const translations = {
    zh: {
      settings: '设置', closeSettings: '关闭设置', appearance: '外观风格', language: '功能语言', animeStyle: '二次元 · Anime', minimalStyle: '极简 · Minimal', navigation: '功能', features: '全部功能',
      tasks: 'Codex 任务', races: 'GⅠ 赛程', racesShort: '赛事', taskCompanion: '任务陪伴', currentTask: '当前任务', working: '工作中', following: '自动跟随 · 当前任务', workFollowing: '工作中 · 自动跟随',
      retry: '记录暂忙，自动重试中。显示上次成功读取的任务。', openCurrent: '打开当前任务', openTask: '打开任务', reconnect: '重新连接', reconnectShort: '重连', completed: '已完成', recentTasks: '最近任务',
      raceCalendar: 'GⅠ 赛事日历', jraSource: 'JRA 官方来源', nextSevenDays: '未来七天', dateRange: '10月3日—10月9日 · 日本时间', noRaces: '这七天没有 JRA 平地 GⅠ 赛事。', nextRace: '下一场 · 所选七天之外', raceDate: '10月18日', raceTrack: '京都 · 芝 2,000 米', refresh: '刷新官网', clearCache: '清理缓存',
      connected: '本地连接正常', busy: '暂忙 · 自动重试', taskFooter: '本机联动 · 原客户端任务在原客户端审批', raceFooter: '赛事按日本时间 · 缓存五分钟', sourceFooter: '官方来源 · 缓存五分钟',
      sourceCached: '本地缓存 · 示例更新时间 15:24', sourceCleared: '演示：缓存已清理 · 下次查询联网获取', sourceOnline: '演示：官网在线获取 · 数据已更新',
      feedbackClear: '概念操作，不清理真实缓存', feedbackRefresh: '概念操作，不发起联网', feedbackReconnect: '概念操作，不连接真实任务', feedbackOpen: '概念操作，不打开真实 Codex'
    },
    ja: {
      settings: '設定', closeSettings: '設定を閉じる', appearance: '表示スタイル', language: '表示言語', animeStyle: 'アニメ', minimalStyle: 'ミニマル', navigation: '機能', features: 'すべての機能',
      tasks: 'Codex タスク', races: 'GⅠ 日程', racesShort: 'レース', taskCompanion: 'タスクサポート', currentTask: '現在のタスク', working: '実行中', following: '自動追従 · 現在のタスク', workFollowing: '実行中 · 自動追従',
      retry: '記録が一時的に読み取れません。自動再試行中です。最後に取得したタスクを表示しています。', openCurrent: 'タスクを開く', openTask: 'タスクを開く', reconnect: '再接続', reconnectShort: '再接続', completed: '完了', recentTasks: '最近のタスク',
      raceCalendar: 'GⅠ レース日程', jraSource: 'JRA 公式情報', nextSevenDays: '今後7日間', dateRange: '10月3日〜10月9日 · 日本時間', noRaces: 'この7日間に JRA の平地 GⅠ レースはありません。', nextRace: '次のレース · 選択期間外', raceDate: '10月18日', raceTrack: '京都 · 芝 2,000m', refresh: '公式情報を更新', clearCache: 'キャッシュ削除',
      connected: 'ローカル接続中', busy: '読み取り待ち · 再試行中', taskFooter: 'ローカル連携 · 元クライアントのタスクは元の画面で承認', raceFooter: '日本時間 · キャッシュは5分間', sourceFooter: '公式情報 · キャッシュは5分間',
      sourceCached: 'ローカルキャッシュ · サンプル更新時刻 15:24', sourceCleared: 'デモ：キャッシュ削除済み · 次回はオンライン取得', sourceOnline: 'デモ：公式サイトから取得 · 更新済み',
      feedbackClear: 'デザインプレビュー：実際のキャッシュは削除しません', feedbackRefresh: 'デザインプレビュー：通信は行いません', feedbackReconnect: 'デザインプレビュー：実際のタスクには接続しません', feedbackOpen: 'デザインプレビュー：実際の Codex は開きません'
    },
    en: {
      settings: 'Settings', closeSettings: 'Close settings', appearance: 'Appearance', language: 'Interface language', animeStyle: 'Anime', minimalStyle: 'Minimal', navigation: 'Navigation', features: 'Features',
      tasks: 'Codex tasks', races: 'GⅠ races', racesShort: 'Races', taskCompanion: 'Task companion', currentTask: 'Current task', working: 'Working', following: 'Auto-follow · Current task', workFollowing: 'Working · Auto-follow',
      retry: 'Records are temporarily busy. Retrying automatically; showing the last successfully read task.', openCurrent: 'Open task', openTask: 'Open task', reconnect: 'Reconnect', reconnectShort: 'Reconnect', completed: 'Completed', recentTasks: 'Recent tasks',
      raceCalendar: 'GⅠ calendar', jraSource: 'JRA official', nextSevenDays: 'Next 7 days', dateRange: 'Oct 3–9 · Japan time', noRaces: 'No JRA flat GⅠ races during these 7 days.', nextRace: 'Next race · Outside this period', raceDate: 'Oct 18', raceTrack: 'Kyoto · Turf 2,000 m', refresh: 'Refresh', clearCache: 'Clear cache',
      connected: 'Local connection ready', busy: 'Busy · Retrying', taskFooter: 'Local integration · Approve existing client tasks there', raceFooter: 'Japan time · 5-minute cache', sourceFooter: 'Official source · 5-minute cache',
      sourceCached: 'Local cache · Sample update time 15:24', sourceCleared: 'Demo: cache cleared · Next query will fetch online', sourceOnline: 'Demo: fetched from the official site · Updated',
      feedbackClear: 'Design preview: no real cache is deleted', feedbackRefresh: 'Design preview: no network request is made', feedbackReconnect: 'Design preview: no real task is connected', feedbackOpen: 'Design preview: the real Codex app is not opened'
    }
  };
  Object.assign(translations.zh, {
    connectionGuide: 'Codex 连接说明', closeGuide: '关闭连接说明', guideTitle: 'Codex · 本地连接',
    guideIntro: '同一台电脑、同一 macOS 用户，无需额外账号绑定或 API Key。',
    guideStep1: '启动并登录本机 Codex。', guideStep2: '创建或打开一项任务；桌宠自动跟随最近开始的活跃任务。',
    guideStep3: '点击“检查连接”；也可在任务列表固定跟随某一项。',
    guideMethod: '已有 Codex 桌面任务通过只读记录兼容联动；直接发送使用官方本地 App Server，在原任务启动新一轮，官方事件驱动状态。其他客户端执行中且没有共享控制通道时不可接管。桌宠启动的轮次如需命令或文件审批，会显示确认窗口；其余交互请求暂不支持。内部记录格式和实验性官方协议变化可能需要更新。',
    dataFolder: '任务数据目录', lastCheck: '最近检查', openCodex: '打开 Codex', checkConnection: '检查连接', connecting: '正在读取本地任务…',
    disconnected: 'Codex 未连接', noTasks: '暂无本地任务', paused: '动画联动已暂停', toggleLink: '联动状态动作', autoFollow: '自动跟随活跃任务', pinned: '固定跟随', followTask: '跟随任务',
    idle: '空闲', waiting: '等待工具结果', review: '正在检查', interrupted: '本轮已中断', failed: '本轮失败',
    pastSevenDays: '过去七天', loadingRaces: '正在从 JRA 官网查询…', raceScope: '日本时间 · JRA 平地 GⅠ（不含 J・GⅠ 与海外赛事）',
    officialRace: '官方赛事页', officialResult: '官方赛果', officialCalendar: '官方 GⅠ 日历', winner: '冠军', jockey: '骑师',
    source: '来源', fetched: '数据获取（本机时间）', online: '官网在线获取', localCache: '本地缓存（五分钟内，本次未联网）', fallbackCache: '旧缓存（本次官网查询失败）', mixed: '部分在线获取，部分使用缓存',
    clearing: '正在清理本地缓存…', cleared: '本地缓存已清理（{count} 个文件）。当前未联网；下一次查询重新获取。', queryError: '查询失败', retryHint: '状态尚未确认；自动重试中，也可手动检查连接。'
  });
  Object.assign(translations.ja, {
    connectionGuide: 'Codex 接続ガイド', closeGuide: '接続ガイドを閉じる', guideTitle: 'Codex · ローカル接続',
    guideIntro: '同じ Mac と macOS ユーザーで使用する場合、追加のアカウント連携や API Key は不要です。',
    guideStep1: 'この Mac で Codex を起動し、ログインします。', guideStep2: 'タスクを作成または開きます。最近開始した実行中のタスクに自動追従します。',
    guideStep3: '「接続を確認」を押します。タスク一覧から追従先を固定することもできます。',
    guideMethod: '既存のデスクトップタスクは読み取り専用記録で連携します。直接送信には公式のローカル App Server を使い、同じタスクで次のターンを開始し、公式イベントを受信します。共有制御チャネルがない場合、別クライアントで実行中のターンは操作できません。ペットが開始したターンのコマンド・ファイル承認は確認画面で行います。他の対話要求は未対応です。内部形式と実験的な公式プロトコルの変更には更新が必要な場合があります。',
    dataFolder: 'タスク記録の場所', lastCheck: '最終確認', openCodex: 'Codex を開く', checkConnection: '接続を確認', connecting: 'ローカルタスクを取得中…',
    disconnected: 'Codex 未接続', noTasks: 'ローカルタスクがありません', paused: 'アニメ連携は一時停止中', toggleLink: '連携状態アニメ', autoFollow: '実行中タスクに自動追従', pinned: '追従先を固定', followTask: 'このタスクに追従',
    idle: '待機中', waiting: 'ツールの結果待ち', review: '確認中', interrupted: 'このターンは中断', failed: 'このターンは失敗',
    pastSevenDays: '過去7日間', loadingRaces: 'JRA 公式サイトから取得中…', raceScope: '日本時間 · JRA 平地 GⅠ（J・GⅠ と海外レースを除く）',
    officialRace: '公式レースページ', officialResult: '公式結果', officialCalendar: '公式 GⅠ カレンダー', winner: '優勝馬', jockey: '騎手',
    source: '情報源', fetched: '取得時刻（この Mac の時間）', online: '公式サイトから取得', localCache: 'ローカルキャッシュ（5分以内・今回の通信なし）', fallbackCache: '古いキャッシュ（今回の取得失敗）', mixed: '公式情報とキャッシュを併用',
    clearing: 'キャッシュを削除中…', cleared: 'キャッシュ {count} 件を削除しました。通信は行っていません。次の検索で再取得します。', queryError: '取得に失敗', retryHint: '現在の状態は未確認です。自動再試行中です。手動で接続を確認することもできます。'
  });
  Object.assign(translations.en, {
    connectionGuide: 'Codex connection guide', closeGuide: 'Close connection guide', guideTitle: 'Codex · Local connection',
    guideIntro: 'On the same Mac and macOS user account, no additional account binding or API Key is needed.',
    guideStep1: 'Launch Codex on this Mac and sign in.', guideStep2: 'Create or open a task. The pet follows the most recently started active task.',
    guideStep3: 'Select “Check connection”. You can also pin a task from the list.',
    guideMethod: 'Existing desktop tasks use a read-only compatibility adapter. Direct sending uses the official local App Server to start the next turn in the same task and receive official events. Without a shared control channel, active turns in another client cannot be controlled. Command/file approvals for pet-started turns use a confirmation dialog; other interactive requests are unsupported. Internal formats and the experimental official protocol may require updates.',
    dataFolder: 'Task data folder', lastCheck: 'Last checked', openCodex: 'Open Codex', checkConnection: 'Check connection', connecting: 'Reading local tasks…',
    disconnected: 'Codex disconnected', noTasks: 'No local tasks', paused: 'Animation link paused', toggleLink: 'Linked state animations', autoFollow: 'Auto-follow active task', pinned: 'Pinned task', followTask: 'Follow task',
    idle: 'Idle', waiting: 'Waiting for tools', review: 'Reviewing', interrupted: 'Turn interrupted', failed: 'Turn failed',
    pastSevenDays: 'Past 7 days', loadingRaces: 'Querying the official JRA site…', raceScope: 'Japan time · JRA flat GⅠ only (excludes J・GⅠ and overseas races)',
    officialRace: 'Official race', officialResult: 'Official result', officialCalendar: 'Official GⅠ calendar', winner: 'Winner', jockey: 'Jockey',
    source: 'Source', fetched: 'Fetched (Mac local time)', online: 'Fetched from the official site', localCache: 'Local cache (under 5 minutes; no request this time)', fallbackCache: 'Older cache (current fetch failed)', mixed: 'Official data and cache combined',
    clearing: 'Clearing local cache…', cleared: 'Cleared {count} cached files. No network request was made. The next query will fetch again.', queryError: 'Query failed', retryHint: 'Current state is unconfirmed. Retrying automatically; you can also check the connection manually.'
  });
  Object.assign(translations.zh, {
    domesticNoRaces:'这七天没有 JRA 平地 GⅠ赛事。', horse:'Forever Young', horseTitle:'フォーエバーヤング · Race Record', upcomingMonth:'未来三十天 · 参赛计划', history:'历史战绩', historyScope:'实马 Forever Young · JBIS 全竞走成績；日期采用主办方当地日期。',
    planScope:'仅列已公布的计划。候选、报名与正式出马表分别标注；出走仍可能取消。', noPlan:'当前来源未列出未来三十天的参赛计划。', historyUnavailable:'战绩来源暂不可用，不能确认完整战绩。',
    international:'国际 GⅠ', japaneseDeclared:'日本调教马 · 出马表', japaneseCandidate:'日本调教马 · 候选', runnersUnknown:'日本马名单尚未核实', declared:'官方出马表', candidate:'候选参赛 · 未最终确认', unknown:'计划待确认',
    timeTBA:'发走时间待公布 · 当地日期', provisionalTime:'暂定时间 · 主办方可能调整', sourceDetails:'来源与更新时间', runners:'参赛名单', position:'名次', races:'国内 / 国际 GⅠ',
    raceScope:'JRA 国内平地 GⅠ + JAIRS 海外主要 GⅠ + 育马者杯；国际覆盖非全球全集。七天按公布的当地日期筛选。',
    raceFooter:'国内 / 国际主要 GⅠ · 可刷新、清理缓存', noRaces:'所覆盖的赛程在这七天没有 GⅠ赛事。', loadingRaces:'正在查询官方赛程与参赛资料…',
    internationalUnavailable:'国际赛程未完整获取，请检查来源提示。', clockRule:'中文：北京时间 · 日文：东京时间 · 英文：比赛当地时间。未公布时刻时保留当地日期。',
    autoRefresh:'页面打开时每五分钟更新；也可手动刷新。', sourceIncomplete:'部分来源不可用或结构发生变化：'
  });
  Object.assign(translations.ja, {
    domesticNoRaces:'この7日間に JRA 平地 GⅠはありません。',horse:'Forever Young',horseTitle:'フォーエバーヤング · Race Record',upcomingMonth:'今後30日 · 出走予定',history:'競走成績',historyScope:'実馬 Forever Young · JBIS 全競走成績。日付は開催地の公表日です。',
    planScope:'公表された予定のみ。候補・登録・出馬表を区別しています。出走取消の場合があります。',noPlan:'現在の情報源には今後30日の出走予定がありません。',historyUnavailable:'成績の情報源を取得できず、全成績を確認できません。',
    international:'海外 GⅠ',japaneseDeclared:'日本調教馬 · 出馬表',japaneseCandidate:'日本調教馬 · 候補',runnersUnknown:'日本馬の出走は未確認',declared:'公式出馬表',candidate:'出走候補 · 未確定',unknown:'予定未確認',
    timeTBA:'発走時刻未発表 · 現地日付',provisionalTime:'暫定時刻 · 変更の場合あり',sourceDetails:'情報源と取得時刻',runners:'出走馬情報',position:'着順',races:'国内 / 海外 GⅠ',
    raceScope:'JRA 平地 GⅠ + JAIRS 海外主要 GⅠ + Breeders’ Cup。世界の全 GⅠを網羅していません。期間は公表された現地日付で絞り込みます。',
    raceFooter:'国内 / 海外主要 GⅠ · 更新・キャッシュ削除',noRaces:'対象の7日間に掲載対象の GⅠはありません。',loadingRaces:'公式日程と出走情報を取得中…',
    internationalUnavailable:'海外日程の取得が不完全です。情報源をご確認ください。',clockRule:'中文：北京時間 · 日本語：東京時間 · English：開催地の時間。時刻未公表の場合は現地日付のみ。',
    autoRefresh:'表示中は5分ごとに更新。手動更新もできます。',sourceIncomplete:'一部の情報源が取得できないか、形式が変更されました：'
  });
  Object.assign(translations.en, {
    domesticNoRaces:'No JRA flat GⅠ races in these seven days.',horse:'Forever Young',horseTitle:'フォーエバーヤング · Race Record',upcomingMonth:'Next 30 days · Race plans',history:'Race record',historyScope:'The racehorse Forever Young · Full record from JBIS. Dates retain the published local race date.',
    planScope:'Published plans only. Contenders, nominations and declared fields are distinct; withdrawal remains possible.',noPlan:'Current sources list no race plan in the next 30 days.',historyUnavailable:'The record source is unavailable; the full record cannot be confirmed.',
    international:'International GⅠ',japaneseDeclared:'Japan-trained · Declared',japaneseCandidate:'Japan-trained · Contenders',runnersUnknown:'Japanese runners unverified',declared:'Official declared field',candidate:'Contender · Not final',unknown:'Plan unconfirmed',
    timeTBA:'Post time TBA · Local date',provisionalTime:'Provisional time · Subject to change',sourceDetails:'Sources and fetch times',runners:'Runner list',position:'Finish',races:'Domestic / World GⅠ',
    raceScope:'JRA flat GⅠ + JAIRS principal overseas GⅠ + Breeders’ Cup. Coverage is not a complete global calendar. Periods use published local dates.',
    raceFooter:'Domestic / principal world GⅠ · Refresh and clear cache',noRaces:'No covered GⅠ races in this 7-day period.',loadingRaces:'Fetching official schedules and runners…',
    internationalUnavailable:'International coverage is incomplete. Check the source notices.',clockRule:'Chinese: Beijing · Japanese: Tokyo · English: Race venue. Without a published time, retain the local date.',
    autoRefresh:'Refreshes every 5 minutes while this page is visible; manual refresh is also available.',sourceIncomplete:'Some sources are unavailable or their format has changed:'
  });
  const root = document.getElementById('forever-young-pet-ui');
  Object.assign(translations.zh, {completed:'本轮已完成'});
  Object.assign(translations.ja, {completed:'このターンは完了'});
  Object.assign(translations.en, {completed:'Turn complete'});
  Object.assign(translations.zh,{integrations:'软件联动',primaryIntegration:'主要联动来源',autoIntegration:'自动 · 前台软件优先',integrationRule:'三个来源同时接收；失败优先，其次完成／中断，再到普通状态。同级优先主来源，其余按到达顺序。问候不覆盖新状态。',runLinked:'运行配置',buildLinked:'构建',testLinked:'运行测试',stopLinked:'停止',officialAdapter:'Codex 官方本地接口',officialConnect:'检查官方通道',sendCodex:'写给当前任务',runCodex:'Codex 运行项目',testCodex:'Codex 测试',reviewCodex:'Codex 检查改动',adapterHint:'使用已安装的官方 CLI。未开放共享控制通道时，只向空闲任务直接发送；其他客户端正在执行的任务不接管。审批与沙盒保留。',pluginHint:'VS Code / PyCharm 需要安装成品内的本地联动插件，并打开项目。普通终端输入不视为 IDE 任务事件。',domestic:'国内 · JRA',international:'国际 GⅠ',liveRuns:'个运行任务',notConnected:'未连接',codexShortcutHint:'Codex 快捷操作先填入输入框，由你点击发送。IDE 运行需在 IDE 选择已有配置。'});
  Object.assign(translations.ja,{integrations:'アプリ連携',primaryIntegration:'優先する連携先',autoIntegration:'自動 · 前面のアプリを優先',integrationRule:'3つの入力を同時に受信。失敗、完了／中断、通常状態の順。同じ優先度では主な連携先を優先し、残りは到着順。挨拶は新しい状態を上書きしません。',runLinked:'実行設定',buildLinked:'ビルド',testLinked:'テスト',stopLinked:'停止',officialAdapter:'Codex 公式ローカル API',officialConnect:'公式接続を確認',sendCodex:'タスクに入力',runCodex:'Codex で実行',testCodex:'Codex テスト',reviewCodex:'Codex レビュー',adapterHint:'インストール済み CLI を使用。共有制御ソケットがない場合、待機中のタスクにのみ送信。他のクライアントの実行は引き継ぎません。承認とサンドボックスは維持。',pluginHint:'同梱の VS Code / PyCharm プラグインを導入してプロジェクトを開いてください。通常のターミナル入力はタスクイベントに含まれません。',domestic:'国内 · JRA',international:'海外 GⅠ',liveRuns:'件実行中',notConnected:'未接続',codexShortcutHint:'Codex 操作は入力欄に下書きを入れます。送信は手動。IDE では保存済み設定を選択してください。'});
  Object.assign(translations.en,{integrations:'App integrations',primaryIntegration:'Primary integration',autoIntegration:'Auto · Frontmost app first',integrationRule:'All three sources remain subscribed. Failure precedes completion/interruption, then ordinary status. At equal priority, primary first, then arrival order. Greetings never overwrite new status.',runLinked:'Run configuration',buildLinked:'Build',testLinked:'Run tests',stopLinked:'Stop',officialAdapter:'Official local Codex API',officialConnect:'Check official connection',sendCodex:'Write to tracked task',runCodex:'Codex run project',testCodex:'Codex tests',reviewCodex:'Codex review',adapterHint:'Uses the installed CLI. Without a shared control socket, direct sending is limited to idle threads; active work in another client is never taken over. Existing approvals and sandbox are preserved.',pluginHint:'Install the bundled VS Code / PyCharm bridge and open a project. Arbitrary terminal input is not an IDE task event.',domestic:'Domestic · JRA',international:'International GⅠ',liveRuns:'running tasks',notConnected:'Disconnected',codexShortcutHint:'Codex shortcuts fill a draft; click Send to execute. IDE actions let you choose a saved configuration inside the IDE.'});
  Object.assign(translations.zh,{connectionGuide:'使用手册与连接',closeGuide:'关闭使用手册',guideTitle:'使用手册',manualBasics:'桌宠使用',changeInSettings:'在设置中更改优先来源',currentIntegration:'当前主来源',primaryBadge:'主要来源',noneSelected:'暂无来源',tasksShort:'Codex',integrationsShort:'联动'});
  Object.assign(translations.ja,{connectionGuide:'使い方と接続',closeGuide:'ガイドを閉じる',guideTitle:'使い方ガイド',manualBasics:'使い方',changeInSettings:'優先先は設定で変更',currentIntegration:'現在の優先先',primaryBadge:'優先先',noneSelected:'入力なし',tasksShort:'Codex',integrationsShort:'連携'});
  Object.assign(translations.en,{connectionGuide:'User manual & connections',closeGuide:'Close user manual',guideTitle:'User manual',manualBasics:'Pet basics',changeInSettings:'Change the primary source in Settings',currentIntegration:'Current primary source',primaryBadge:'Primary',noneSelected:'No source',tasksShort:'Codex',integrationsShort:'Apps'});
  Object.assign(translations.zh,{runLinked:'运行项目',chooseRun:'重新选择目标',runFile:'运行当前文件',operationTarget:'操作对象',operationHint:'点击软件条目切换操作栏；主要状态来源仍在设置中选择。',pluginUpgrade:'新增操作需要 3.7.0 联动插件，请按设置中的说明更新。'});
  Object.assign(translations.ja,{runLinked:'プロジェクト実行',chooseRun:'対象を選び直す',runFile:'現在のファイルを実行',operationTarget:'操作対象',operationHint:'アプリ項目で操作欄を切り替えます。状態の優先先は設定で選択。',pluginUpgrade:'新しい操作には連携プラグイン 3.7.0 が必要です。設定のガイドから更新してください。'});
  Object.assign(translations.en,{runLinked:'Run project',chooseRun:'Choose target',runFile:'Run current file',operationTarget:'Control target',operationHint:'Select an app card for its controls. The primary status source remains in Settings.',pluginUpgrade:'New controls require bridge plugin 3.7.0. Update using the Settings guide.'});
  translations.zh.toolFooter='本机计时与摘要 · 设置可关闭提醒';translations.ja.toolFooter='ローカル計測と要約 · 通知は設定で変更';translations.en.toolFooter='Local timers and summaries · Control alerts in Settings';translations.zh.tools='陪伴工具'; translations.ja.tools='サポート'; translations.en.tools='Companion tools';
  const state = {style: 'anime', language: 'zh', page: 'tasks', settings: false, modules: false, manualPage:'basics',operationSource:null};
  let data = {modules: [], codex: {threads: []}, races: {status: 'loading', period: 'nextWeek'}};
  let received = false;
  const text = key => translations[state.language][key] || key;
  const escape = value => String(value ?? '').replace(/[&<>"']/g, character => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[character]));
  const icon = name => `<img class="fy-icon" src="icons/${escape(name)}.png" alt="" aria-hidden="true">`;
  const button = (key, command, attributes = '', primary = false) => `<button type="button" class="fy-action ${primary ? 'fy-primary' : ''}" data-command="${command}" ${attributes}>${escape(text(key))}</button>`;
  const send = (command, values = {}) => window.webkit?.messageHandlers?.pet?.postMessage({command, ...values});
  const date = (value, time = false, japan = false) => value ? new Intl.DateTimeFormat(
    {zh:'zh-CN',ja:'ja-JP',en:'en-US'}[state.language],
    time ? {dateStyle:'medium',timeStyle:'medium'} : {month:'short',day:'numeric',year:'numeric',timeZone:japan ? 'Asia/Tokyo' : undefined}
  ).format(new Date(value)) : '—';
  const activity = value => text({working:'working',completed:'completed',disconnected:'disconnected'}[value] || value || 'idle');

  // Replace host-provided preview icons with bundled system symbols; no CDN or server dependency.
  root.querySelectorAll('[data-lucide]').forEach(element => element.outerHTML = icon(element.dataset.lucide));
  root.querySelectorAll('.fy-settings').forEach(settings => {
    const guide = document.createElement('button');
    guide.type = 'button'; guide.className = 'fy-guide-link'; guide.dataset.command = 'guide'; guide.dataset.i18n = 'connectionGuide';
    settings.append(guide);
    const primary=document.createElement('label');primary.className='fy-primary-setting';
    primary.innerHTML='<span data-i18n="primaryIntegration"></span><select data-primary-integration><option value="auto" data-i18n="autoIntegration"></option><option value="codex">Codex</option><option value="vscode">VS Code</option><option value="pycharm">PyCharm</option></select>';
    settings.append(primary);
  });

  const dialog = document.getElementById('fy-connection-guide');
  root.append(dialog);
  let manualLanguage;
  function renderGuide() {
    if (manualLanguage !== state.language) {
      for (const [id,page] of Object.entries(window.petManual[state.language])) {
        dialog.querySelector(`[data-manual-body="${id}"]`).innerHTML=`<h3>${escape(page.title)}</h3>`+page.groups.map(group=>`<h4>${escape(group.title)}</h4><ul>${group.items.map(item=>`<li>${escape(item)}</li>`).join('')}</ul>`).join('');
      }
      manualLanguage=state.language;
    }
    dialog.querySelectorAll('[data-manual-page]').forEach(tab=>tab.setAttribute('aria-pressed',String(tab.dataset.manualPage===state.manualPage)));
    dialog.querySelectorAll('[data-manual-panel]').forEach(panel=>panel.hidden=panel.dataset.manualPanel!==state.manualPage);
    const codex = data.codex;
    dialog.querySelector('[data-guide-status]').textContent = received ? text(codex.connected ? 'connected' : 'disconnected') : text('connecting');
    dialog.querySelector('[data-guide-home]').textContent = codex.home || '~/.codex';
    dialog.querySelector('[data-guide-check]').textContent = date(codex.checkedAt, true);
    dialog.querySelector('[data-guide-detail]').textContent = codex.connected ? text('guideMethod') : [text('retryHint'), codex.message || ''].filter(Boolean).join('\n');
    dialog.querySelector('[data-toggle-codex]').checked = codex.enabled !== false;
    const official=data.official || {};
    dialog.querySelector('[data-guide-official]').textContent=text('officialAdapter')+' · '+(official.ready?text('connected')+' · '+(official.transport || ''):official.message || text('notConnected'));
  }

  function renderNavigation() {
    for (const surface of root.querySelectorAll('[data-ui-surface]')) {
      const anime = surface.dataset.uiSurface === 'anime';
      const nav = surface.querySelector(anime ? '.uma-navigation' : '.pet-nav');
      nav.querySelectorAll(':scope > [data-module]').forEach(element => element.remove());
      nav.querySelectorAll(':scope > [data-uma-view],:scope > [data-view]').forEach(element => element.remove());
      const control = nav.querySelector('.fy-module-control');
      for (const module of data.modules.filter(module=>['tasks','races','integrations'].includes(module.id))) {
        const tab = document.createElement('button');
        tab.type = 'button'; tab.className = anime ? 'uma-tab' : 'pet-nav-item'; tab.dataset.module = module.id;
        tab.setAttribute('aria-pressed', String(module.id === state.page));
        tab.setAttribute('aria-label',text(module.titleKey));tab.title=text(module.titleKey);
        tab.innerHTML = icon(module.icon) + `<span><span class="fy-nav-full">${escape(text(module.titleKey))}</span><span class="fy-nav-short">${escape(text(module.id+'Short'))}</span></span>`;
        nav.insertBefore(tab, control);
      }
      surface.querySelector('.fy-module-menu').innerHTML = `<strong>${escape(text('features'))}</strong>` + data.modules.map(module =>
        `<button type="button" data-module="${escape(module.id)}" aria-pressed="${module.id === state.page}">${icon(module.icon)}<span>${escape(text(module.titleKey))}</span></button>`).join('');
    }
  }

  function renderTasks() {
    const codex = data.codex;
    const selected = codex.threads.find(thread => thread.id === codex.selectedID);
    const status = received ? text(codex.connected ? 'connected' : 'disconnected') : text('connecting');
    const others = codex.threads.filter(thread => thread.id !== codex.selectedID);
    const title = selected?.title || text('noTasks');
    const currentActions = (selected ? button('openTask','openThread',`data-id="${escape(selected.id)}"`,true) + button('sendCodex','codexCompose') : button('openCodex','openCodex','',true)) + button('reconnect','reconnect');
    const list = others.map(thread => `<article class="fy-thread-row"><div class="fy-thread-heading"><strong>${escape(thread.title)}</strong><span>${escape(activity(thread.activity))}</span></div>
      <div class="fy-location">${escape(thread.cwd)}</div><div class="fy-thread-actions">${button('followTask','follow',`data-id="${escape(thread.id)}"`)}${button('openTask','openThread',`data-id="${escape(thread.id)}"`)}</div></article>`).join('');
    const notices = !codex.connected && received ? `<div class="fy-notice" role="status">${escape(text('retryHint'))}</div>` : '';
    const followControls = `<div class="fy-follow-bar"><span>${escape(text(codex.followingID ? 'pinned' : 'following'))}</span>${button('autoFollow','follow')}</div>`;
    const content = `<div class="fy-current"><div class="fy-task-meta"><span>${escape(codex.enabled === false ? text('paused') : activity(codex.activity))}</span></div>
      <h2>${escape(title)}</h2><div class="fy-location">${icon('folder')}${escape(selected?.cwd || '')}</div>${followControls}${notices}<div class="fy-actions">${currentActions}</div></div>
      ${others.length ? `<div class="fy-recent-label">${escape(text('recentTasks'))}</div>${list}` : ''}`;
    root.querySelector('[data-uma-panel="tasks"]').innerHTML = `<div class="uma-ribbon"><h3>${icon('flag')}<span>${escape(text('taskCompanion'))}</span></h3><span class="uma-connection">${escape(status)}</span></div><div class="uma-panel-body">${content}</div>`;
    root.querySelector('[data-panel="tasks"]').innerHTML = `<div class="pet-line"><h3>${escape(text('currentTask'))}</h3><span class="pet-status">${escape(status)}</span></div>${content}<footer class="pet-footer">${escape(text('taskFooter'))}</footer>`;
  }

  // The third module uses the existing module menu; no fixed two-tab layout.
  for (const surface of root.querySelectorAll('[data-ui-surface]')) {
    const anime=surface.dataset.uiSurface==='anime';
    const panel=document.createElement('div');
    panel.className=anime?'uma-panel':'fy-horse-panel';
    panel.setAttribute(anime?'data-uma-panel':'data-panel','horse');panel.hidden=true;
    const anchor=surface.querySelector(anime?'[data-uma-panel="races"]':'[data-panel="races"]');
    anchor.after(panel);
    const linked=document.createElement('div');linked.className=anime?'uma-panel':'fy-integration-panel';linked.setAttribute(anime?'data-uma-panel':'data-panel','integrations');linked.hidden=true;panel.after(linked);
  }
  Object.assign(translations.zh,{runCpp:'编译并运行当前文件',advancedRun:'高级工程操作（可选）',practiceHint:'默认运行当前文件，无需选择工程目标。运行前自动保存，输入数据请使用 VS Code 终端。',pluginUpgrade:'请更新 VS Code 3.7.1／PyCharm 3.7.0 联动插件。'});
  Object.assign(translations.ja,{runCpp:'現在のファイルをビルドして実行',advancedRun:'高度なプロジェクト操作（任意）',practiceHint:'既定は現在のファイルを実行。対象選択は不要です。保存後、入力は VS Code のターミナルで行います。',pluginUpgrade:'VS Code 3.7.1／PyCharm 3.7.0 の連携プラグインを更新してください。'});
  Object.assign(translations.en,{runCpp:'Compile and run current file',advancedRun:'Advanced project actions (optional)',practiceHint:'Run the current file by default, without choosing a project target. The file is saved first; enter input in the VS Code terminal.',pluginUpgrade:'Update the VS Code 3.7.1 / PyCharm 3.7.0 bridge plugins.'});
  function renderIntegrations() {
    const integration=data.integrations || {primary:'auto',selected:'codex',sources:[]};
    const sourceName=value=>({codex:'Codex',vscode:'VS Code',pycharm:'PyCharm'}[value] || text('noneSelected'));
    if(!state.operationSource && received) state.operationSource=integration.selected || 'codex';
    const operation=state.operationSource || integration.selected || 'codex';
    let content=`<div class="fy-primary-display" data-primary-display><span>${escape(text('primaryIntegration'))}<strong>${escape(integration.primary==='auto'?text('autoIntegration'):sourceName(integration.primary))}</strong></span><span>${escape(text('currentIntegration'))}<strong>${escape(sourceName(integration.selected))}</strong></span><small>${escape(text('changeInSettings'))}</small></div>`;
    content+=(integration.sources || []).map(source=>`<article class="fy-source-card fy-${escape(source.source)} ${operation===source.source?'fy-operation-selected':''}"><button type="button" class="fy-source-select" data-linked-source="${escape(source.source)}" aria-pressed="${operation===source.source}"><span class="fy-thread-heading"><strong>${escape(source.label)}</strong><span>${escape(source.connected?activity(source.state):text('notConnected'))}</span></span><strong class="fy-source-title">${escape(source.title || '—')}</strong><span class="fy-location">${escape(source.project || '')}</span><small>${Number(source.activeCount)||0} ${escape(text('liveRuns'))}${integration.selected===source.source?' · '+escape(text('primaryBadge')):''}</small></button></article>`).join('');
    const source=(integration.sources || []).find(source=>source.source===operation);
    const actions=source?.actions || ['run','build','test','stop'];
    const linkedButton=(key,action,primary=false)=>button(key,'linkedAction',`data-action="${action}" data-source="${operation}" ${source?.metadata?.[action==='runFile'?'fileToken':action+'Token']?`data-expected-token="${escape(source.metadata[action==='runFile'?'fileToken':action+'Token'])}"`:''} ${source?.instance?`data-instance="${escape(source.instance)}"`:''} ${source?.connected && actions.includes(action) && (!['run','runFile','build','test'].includes(action) || ['3.7.0','3.7.1'].includes(source?.metadata?.pluginVersion))?'':'disabled'}`,primary);
    let controls,advanced="";
    if(operation==='codex') controls=button('sendCodex','codexCompose','',true)+button('runCodex','codexCompose','data-preset="run"')+button('testCodex','codexCompose','data-preset="test"')+button('reviewCodex','codexCompose','data-preset="review"')+button('stopLinked','linkedAction','data-action="stop" data-source="codex"');
    else if(operation==='vscode') {
      controls=linkedButton(/\.(c|cc|cpp|cxx)$/i.test(source?.metadata?.file || '')?'runCpp':'runFile','runFile',true)+linkedButton('stopLinked','stop');
      advanced=linkedButton('runLinked','run')+linkedButton('chooseRun','chooseRun')+linkedButton('buildLinked','build')+linkedButton('testLinked','test');
    } else controls=linkedButton('runLinked','run',true)+linkedButton('chooseRun','chooseRun')+linkedButton('testLinked','test')+linkedButton('stopLinked','stop');
    if(operation!=='codex') {
      const m=source?.metadata || {};
      const labels={zh:['将运行的目标','当前文件','当前文件解释器 / 编译器','首次需在 IDE 选择目标','打开问题面板','打开控制台'],ja:['実行予定の対象','現在のファイル','現在のファイルの実行環境','初回は IDE で対象を選択','問題パネル','コンソール'],en:['Target to run','Current file','Current-file interpreter / compiler','Choose in IDE on first use','Open Problems','Open console']}[state.language];
      const projectPreview=`<strong>${escape(labels[0])}</strong><p>${escape(m.runTarget || labels[3])}</p><dl>${operation==='vscode'?`<dt>Build</dt><dd>${escape(m.buildTarget || labels[3])}</dd>`:''}<dt>Test</dt><dd>${escape(m.testTarget || labels[3])}</dd></dl>`;
      content+=`<div class="fy-run-preview">${operation==='vscode'?`<strong>${escape(text('runFile'))}</strong><p>${escape(m.file || '—')}</p>`:projectPreview}<small>${escape(source?.project || '')}</small><dl><dt>${escape(labels[1])}</dt><dd>${escape(m.file || '—')}</dd><dt>${escape(labels[2])}</dt><dd>${escape(m.runtime || '—')}</dd></dl>${operation==='vscode'?`<p class="fy-race-label">${escape(text('practiceHint'))}</p>`:''}</div>`;
      if(operation==='vscode') {
        controls+=linkedButton(labels[5],'openConsole');
        advanced=`<details class="fy-vscode-advanced" data-advanced-vscode ${state.vscodeAdvancedOpen?'open':''}><summary data-vscode-advanced-toggle>${escape(text('advancedRun'))}</summary><div class="fy-run-preview">${projectPreview}</div><div class="fy-actions">${advanced+linkedButton(labels[4],'openProblems')}</div></details>`;
      } else controls+=linkedButton(labels[4],'openProblems')+linkedButton(labels[5],'openConsole');
    }
    content+=`<div class="fy-operation-controls" data-linked-controls="${operation}"><h4>${escape(text('operationTarget'))} · ${escape(sourceName(operation))}</h4><p class="fy-race-label">${escape(text('operationHint'))}</p><div class="fy-actions">${controls}</div>${advanced}${operation!=='codex' && source?.connected && !['3.7.0','3.7.1'].includes(source?.metadata?.pluginVersion)?`<p class="fy-notice">${escape(text('pluginUpgrade'))}</p>`:''}</div>`;
    root.querySelector('[data-uma-panel=integrations]').innerHTML=`<div class="uma-ribbon"><h3>${icon('terminal')}<span>${escape(text('integrations'))}</span></h3></div><div class="uma-panel-body">${content}</div>`;
    root.querySelector('[data-panel=integrations]').innerHTML=`<h3>${escape(text('integrations'))}</h3>${content}`;
    root.querySelectorAll('.fy-settings [data-primary-integration]').forEach(select=>select.value=integration.primary);
  }
  const civilDate=value => value ? new Intl.DateTimeFormat({zh:'zh-CN',ja:'ja-JP',en:'en-US'}[state.language],{dateStyle:'medium',timeZone:'UTC'}).format(new Date(value+'T12:00:00Z')) : '—';
  function raceClock(race) {
    if (!race.start) return `${escape(civilDate(race.localDate))} · ${escape(text('timeTBA'))}`;
    const zone=state.language==='zh'?'Asia/Shanghai':state.language==='ja'?'Asia/Tokyo':race.zone;
    return escape(new Intl.DateTimeFormat({zh:'zh-CN',ja:'ja-JP',en:'en-US'}[state.language],{year:'numeric',month:'short',day:'numeric',hour:'2-digit',minute:'2-digit',timeZone:zone,timeZoneName:'short'}).format(new Date(race.start)));
  }
  function worldCard(race) {
    const japanese=(race.japaneseRunners || []);
    const name=state.language==='en' && race.englishName ? race.englishName : race.name;
    const mark=japanese.length?`<span class="fy-japan-badge">JP · ${escape(text(race.entryStatus==='declared'?'japaneseDeclared':'japaneseCandidate'))}</span>`:'';
    return `<article class="fy-race fy-world-race"><div class="fy-race-top"><span class="uma-grade">GⅠ</span><div><small>${escape(text('international'))}</small><h2>${escape(name)}</h2><strong class="fy-clock">${raceClock(race)}</strong><div class="fy-location">${escape(race.venue)}${race.course?' · '+escape(race.course):''}</div></div></div>
      ${race.provisionalTime?`<p class="fy-race-label">${escape(text('provisionalTime'))}</p>`:''}
      ${mark}<p class="fy-race-label">${escape(text(race.entryStatus==='declared'?'declared':race.entryStatus==='candidate'?'candidate':'runnersUnknown'))}${japanese.length?' · '+escape(japanese.join(' / ')):''}</p>
      <div class="fy-thread-actions">${button('officialRace','openRace',`data-url="${escape(race.pageURL)}"`)}${race.runnersURL?button('runners','openRace',`data-url="${escape(race.runnersURL)}"`):''}</div></article>`;
  }
  function sourceList(checks,warnings=[]) {
    return `<details class="fy-source-details"><summary>${escape(text('sourceDetails'))}</summary>${checks.map(check=>`<p><button class="fy-source-link" data-command="openRace" data-url="${escape(check.url)}">${escape(new URL(check.url).host)}</button> · ${escape(text(check.mode))}<br>${escape(date(check.fetchedAt,true))}</p>`).join('')}</details>${warnings.length?`<div class="fy-notice"><strong>${escape(text('sourceIncomplete'))}</strong><br>${warnings.map(escape).join('<br>')}</div>`:''}`;
  }
  function renderRaces() {
    const result=data.races;
    const periodKey=result.period==='pastWeek'?'pastSevenDays':'nextSevenDays';
    let content=`<div class="fy-race-periods">${button('pastSevenDays','query','data-period="pastWeek"')}${button('nextSevenDays','query','data-period="nextWeek"')}</div><p class="fy-race-scope">${escape(text('raceScope'))}</p><p class="fy-race-label">${escape(text('clockRule'))}</p>`;
    if (result.status==='ready') {
      content+=`<div class="uma-date"><strong>${escape(text(periodKey))}</strong><span>${escape(date(result.rangeStart,false,true))} — ${escape(date(result.rangeEnd,false,true))}</span></div>`;
      const world=result.international || [];
      if (!result.items.length && !world.length) {
        if (result.domesticAvailable!==false) content+=`<p>${escape(text(result.internationalAvailable?'noRaces':'domesticNoRaces'))}</p>`;
        if (!result.internationalAvailable) content+=`<p class="fy-notice">${escape(text('internationalUnavailable'))}</p>`;
      }
      const shown=result.items.length?result.items.map(race=>({race,outside:false})):result.period==='nextWeek' && !world.length && result.nextRace?[{race:result.nextRace,outside:true}]:[];
      content+=`<div class="fy-race-legend"><span>${escape(text('domestic'))}</span><span>${escape(text('international'))}</span></div>`;
      content+=shown.map(({race,outside})=>`<article class="fy-race fy-domestic-race"><div class="fy-race-top"><span class="uma-grade">GⅠ</span><div><small>${escape(text('domestic'))}</small>${outside?`<span class="fy-race-label">${escape(text('nextRace'))}</span>`:''}<h2>${escape(date(race.date,false,true))} · ${escape(race.name)}</h2><span class="fy-location">${escape(race.venue)} · ${escape(race.course)}</span></div></div>${race.winner?`<p>${escape(text('winner'))}：${escape(race.winner)}<br>${escape(text('jockey'))}：${escape(race.jockey)}</p>`:''}<div class="fy-thread-actions">${button('officialRace','openRace',`data-url="${escape(race.pageURL)}"`)}${race.resultURL?button('officialResult','openRace',`data-url="${escape(race.resultURL)}"`):''}</div></article>`).join('');
      content+=world.map(worldCard).join('');
      if (result.domesticAvailable!==false) content+=`<div class="fy-source">JRA · ${escape(text(result.source))}<br>${escape(date(result.fetchedAt,true))}</div>`;
      if (result.warning) content+=`<p class="fy-notice">${escape(result.warning)}</p>`;
      content+=sourceList(result.internationalChecks || [],result.internationalWarnings || []);
      if (result.calendarURL) content+=`<div class="fy-thread-actions">${button('officialCalendar','openRace',`data-url="${escape(result.calendarURL)}"`)}</div>`;
    } else if (result.status==='error') content+=`<p class="fy-notice" role="alert">${escape(text('queryError'))}<br>${escape(result.error)}</p>`;
    else content+=`<p role="status">${escape(result.status==='cleared'?text('cleared').replace('{count}',result.clearedCount):text(result.status==='clearing'?'clearing':'loadingRaces'))}</p>`;
    content+=`<p class="fy-race-label">${escape(text('autoRefresh'))}</p><div class="fy-actions">${button('refresh','query',`data-period="${result.period}" data-refresh="true"`,true)}${button('clearCache','clearCache')}</div>`;
    root.querySelector('[data-uma-panel="races"]').innerHTML=`<div class="uma-ribbon"><h3>${icon('calendar-days')}<span>${escape(text('raceCalendar'))}</span></h3></div><div class="uma-panel-body">${content}</div>`;
    root.querySelector('[data-panel="races"]').innerHTML=`<h3>${escape(text('raceCalendar'))}</h3>${content}<footer class="pet-footer">${escape(text('sourceFooter'))}</footer>`;
  }
  function renderHorse() {
    const result=data.horse || {status:'loading'};
    let content=`<p class="fy-race-scope">${escape(text('planScope'))}</p><p class="fy-race-label">${escape(text('clockRule'))}</p>`;
    if (result.status==='ready') {
      content+=`<h2>${escape(text('upcomingMonth'))}</h2>`+(result.upcoming.length?result.upcoming.map(worldCard).join(''):`<p>${escape(text('noPlan'))}</p>`);
      content+=`<h2>${escape(text('history'))}</h2><p class="fy-race-scope">${escape(text('historyScope'))}</p>`;
      if (!result.historyAvailable) content+=`<p class="fy-notice">${escape(text('historyUnavailable'))}</p>`;
      else {
        const wins=result.history.filter(race=>race.place==='1').length;
        content+=`<p class="fy-record-count">${state.language==='zh'?result.history.length+' 战 · '+wins+' 胜':state.language==='ja'?result.history.length+' 戦 · '+wins+' 勝':result.history.length+' starts · '+wins+' wins'}</p>`;
        content+=`<div class="fy-history">${result.history.map(race=>`<article class="fy-history-row"><span class="fy-finish ${race.place==='1'?'fy-winner':''}">${escape(race.place)}</span><div><strong>${escape(state.language==='en' && race.englishName?race.englishName:race.name)}</strong><small>${escape(civilDate(race.localDate))} · ${escape(race.venue)} · ${escape(race.grade)}<br>${escape(race.distance)} · ${escape(race.jockey)}</small></div></article>`).join('')}</div>`;
      }
      content+=sourceList(result.checks,result.warnings);
    } else if (result.status==='error') content+=`<p class="fy-notice">${result.error==='cacheCleared'?escape(text('cleared').replace('{count}','—')):escape(text('queryError'))+' · '+escape(result.error)}</p>`;
    else content+=`<p role="status">${escape(text('loadingRaces'))}</p>`;
    content+=`<p class="fy-race-label">${escape(text('autoRefresh'))}</p><div class="fy-actions">${button('refresh','queryHorse','data-refresh="true"',true)}${button('clearCache','clearCache')}</div>`;
    root.querySelector('[data-uma-panel="horse"]').innerHTML=`<div class="uma-ribbon"><h3>${icon('sparkles')}<span>${escape(text('horseTitle'))}</span></h3></div><div class="uma-panel-body">${content}</div>`;
    root.querySelector('[data-panel="horse"]').innerHTML=`<h3>${escape(text('horseTitle'))}</h3>${content}`;
  }

  function render() {
    const scroll = window.scrollY;
    root.lang = state.language === 'zh' ? 'zh-CN' : state.language;
    root.querySelectorAll('[data-i18n]').forEach(element => element.textContent = text(element.dataset.i18n));
    root.querySelectorAll('[data-i18n-label]').forEach(element => element.setAttribute('aria-label',text(element.dataset.i18nLabel)));
    root.querySelectorAll('[data-ui-surface]').forEach(surface => surface.hidden = surface.dataset.uiSurface !== state.style);
    root.querySelectorAll('[data-ui-style]').forEach(select => select.value = state.style);
    root.querySelectorAll('[data-ui-language]').forEach(select => select.value = state.language);
    root.querySelectorAll('.fy-settings').forEach(settings => settings.hidden = !state.settings);
    root.querySelectorAll('.fy-module-menu').forEach(menu => menu.hidden = !state.modules);
    root.querySelectorAll('[data-open-settings]').forEach(button => button.setAttribute('aria-expanded',String(state.settings)));
    root.querySelectorAll('[data-open-modules]').forEach(button => button.setAttribute('aria-expanded',String(state.modules)));
    renderNavigation(); renderTasks(); renderRaces(); renderHorse(); renderIntegrations(); renderGuide(); window.petTools?.render();
    root.querySelectorAll('[data-panel],[data-uma-panel]').forEach(panel => panel.hidden = (panel.dataset.panel || panel.dataset.umaPanel) !== state.page);
    root.querySelector('[data-uma-footer]').textContent = text(state.page==='tools'?'toolFooter':['tasks','integrations'].includes(state.page) ? 'taskFooter' : 'raceFooter');
    root.querySelectorAll('.uma-feedback,.pet-feedback').forEach(element => element.textContent = '');
    document.body.dataset.ready = 'true';
    window.scrollTo(0, scroll);
  }
  window.petUI = {update(payload) {
    if (payload.version !== 1) return;
    data = payload; received = true;
    if (['anime','minimal'].includes(payload.preferences.style)) state.style = payload.preferences.style;
    if (Object.hasOwn(translations,payload.preferences.language)) state.language = payload.preferences.language;
    state.page = payload.page; window.petTools?.update(payload.tools); render();
  }};
  root.addEventListener('click',event => {
    const advancedToggle=event.target.closest('[data-vscode-advanced-toggle]');
    if(advancedToggle){state.vscodeAdvancedOpen=!advancedToggle.parentElement.open;return;}
    const target = event.target.closest('button');
    if (!target) { if (!event.target.closest('.fy-settings,.fy-module-menu,.fy-guide')) { state.settings=false;state.modules=false;render(); } return; }
    if (target.hasAttribute('data-open-settings')) {state.settings=!state.settings;state.modules=false;render();}
    else if (target.hasAttribute('data-close-settings')) {state.settings=false;render();}
    else if (target.hasAttribute('data-open-modules')) {state.modules=!state.modules;state.settings=false;render();}
    else if (target.dataset.module) {state.page=target.dataset.module;state.settings=false;state.modules=false;render();window.scrollTo(0,0);send('page',{page:state.page});}
    else if (target.dataset.linkedSource) {state.operationSource=target.dataset.linkedSource;renderIntegrations();}
    else if (target.dataset.manualPage) {state.manualPage=target.dataset.manualPage;renderGuide();dialog.scrollTop=0;}
    else if (target.dataset.command === 'guide') {state.settings=false;state.modules=false;state.manualPage='basics';render();dialog.showModal();}
    else if (target.dataset.command === 'closeGuide') dialog.close();
    else if (target.dataset.command) {
      const values = {};
      if (target.dataset.id) values.id=target.dataset.id;
      if (target.dataset.url) values.url=target.dataset.url;
      if (target.dataset.action) values.action=target.dataset.action;
      if (target.dataset.source) values.source=target.dataset.source;
      if (target.dataset.instance) values.instance=target.dataset.instance;
      if (target.dataset.expectedToken) values.expectedToken=target.dataset.expectedToken;
      if (target.dataset.preset) values.preset=target.dataset.preset;
      if (target.dataset.period) {values.period=target.dataset.period;values.refresh=target.dataset.refresh==='true';}
      if (target.dataset.command === 'queryHorse') values.refresh=target.dataset.refresh==='true';
      if (target.dataset.command === 'reconnect') {data.codex.message='';data.codex.connected=false;renderGuide();}
      send(target.dataset.command,values);
    }
    if (target.hasAttribute('data-open-settings') && state.settings) root.querySelector('[data-ui-surface]:not([hidden]) [data-ui-style]').focus();
  });
  root.addEventListener('change',event => {
    if (event.target.hasAttribute('data-primary-integration')) {send('primary',{value:event.target.value});return;}
    if (event.target.hasAttribute('data-toggle-codex')) {send('toggleCodex');return;}
    if (event.target.hasAttribute('data-ui-style')) state.style=event.target.value;
    else if (event.target.hasAttribute('data-ui-language')) state.language=event.target.value;
    else return;
    render(); send('preferences',{style:state.style,language:state.language});
    root.querySelector(`[data-ui-surface]:not([hidden]) [${event.target.hasAttribute('data-ui-style') ? 'data-ui-style' : 'data-ui-language'}]`).focus();
  });
  root.addEventListener('keydown',event => {
    if (event.key === 'Escape' && !dialog.open && (state.settings || state.modules)) {
      const settingsWasOpen=state.settings;state.settings=false;state.modules=false;render();
      root.querySelector(`[data-ui-surface]:not([hidden]) [${settingsWasOpen ? 'data-open-settings' : 'data-open-modules'}]`).focus();
    }
  });
  render(); send('ready');
})();
