# 来源与制作记录

角色：フォーエバーヤング（青春永驻 / Forever Young）。角色与官方素材出自 Cygames 的《ウマ娘 プリティーダービー》。本桌宠为非官方、AI 辅助制作的个人自定义素材。

- 角色设定、性格、CV 与服装来源：https://umamusume.jp/character/foreveryoung
- 决胜服参考：官方角色页的「勝負服」立绘；来源是官方角色页。
- 语音：同一官方页面的 `foreveryoung_voice.mp3`，CV 海弓シュリ；原始文件未剪辑、未合成，保存为 `official-voice.mp3`。官方语音地址：https://files.microcms-assets.io/assets/973fc097984b400db8729642ddff5938/3a29844da3824835acdfd9fdd5e59221/foreveryoung_voice.mp3；SHA-256：`8c59585ae51548a129058ddbb6b2bb4873977f34500c2d878b4455633f9a15bb`。完整官方数据和抓取记录保留在本地制作资料中。
- 用户提供的 13 张参考图已浏览，用于识别角色。动画生成的服装依据为官方决胜服立绘，不采用其他服装。
- 动作与包装参考：https://github.com/2846182283/zili-codex-pet
- 视频说明参考：https://www.bilibili.com/video/BV1XhYM6fETF/ 。播放器无法播放；没有将未观看的视频动作作为已验证事实。
- 技能：OpenAI 官方 hatch-pet，https://github.com/openai/skills/tree/main/skills/.curated/hatch-pet
- 图像生成：内置 image_gen，经 imagegen 技能调用；每组动作用统一基准形象及官方立绘作参考，左右跑动分别生成。
- 帧提取、图集装配、校验与 GIF 预览使用 hatch-pet 随附脚本。生成提示词和制作证据保留在本地制作资料中。

访问与制作日期：2026-10-02。

## v2 更新

v2 保留九组已验证动作的 RGBA 像素，使用 hatch-pet 与 imagegen 的内置图像生成流程新增四个基准方向、16 方向的两组连贯视线，以及用于修正左上方向的独立参考姿势。没有把单独修正姿势拼贴成最终方向格。新增图集经固定配准、透明边缘清理和无损 WebP 编码，原九组动作没有重新生成。

本地浏览器交互代码用于“悬停只跳一次”与“点击播放官方原始语音并挥手”。它不扩展 Codex 原生 `pet.json` 的交互能力，也不修改客户端应用文件。所有 v2 生成参考、提示词、原图和检查记录保留在同级「制作过程v2」。

## 独立桌面交互版

使用既有 v2 图集与原始官方语音，图集转换为 PNG 时保持 RGBA 像素一致。原生窗口与交互代码使用本机 Apple SDK 编译；未复制作者的角色素材或 Codex 客户端代码。

## 独立桌面 v2（2026-10-03）

只修改独立桌面程序的交互、动画调度和显示尺寸。PNG 图集和官方 MP3 与桌面 v1 字节一致，未重新生成角色画面，未剪辑或合成语音。桌面 v2 的版本号与 Codex 原生素材 v2 是各自独立的版本。

## 独立桌面 v3（2026-10-03）

v3 继续保留桌面 v2 的 PNG、官方 MP3 和图标原始字节。新增本地 Codex 生命周期适配器与 JRA 赛事信息界面，不复制 Codex 客户端实现。赛事数据直接来自 JRA 官方 GⅠ 日历（https://jra.jp/datafile/seiseki/replay/g1.html）；官网 HTML 测试快照只留在制作目录，不打包进成品。官方 App Server 与 Hooks 资料分别见 https://learn.chatgpt.com/docs/app-server 和 https://learn.chatgpt.com/docs/hooks 。本版不需要云端服务器或上传任务内容。

## 桌面 v3.1

修复本地任务读取错误分类、增加兼容性探测与缓存管理；未改变图集、官方语音与图标字节，未修改正式 UI 美术风格。UI 概念预览不随成品发布。

## 桌面 v3.2

将已确认的二次元／极简界面用于正式工作台，沿用任务和赛事提供者，新增中日英功能语言切换与连接引导。界面立绘来自上述官方角色页的决胜服图，沿用预览内的无损 WebP；角色、立绘和语音权利归 Cygames 及相应权利人。本次没有生成新的角色帧或修改原始语音。

功能图标由本机 AppKit 系统符号渲染，UI 随应用打包，不依赖外部图标库或 CDN。原有成品不变，未提交或上传 GitHub。

## v3.3 赛事信息来源

本机直接查询 JBIS 全竞走成績、JAIRS 海外主要竞走日程、JRA 国内及海外赛事公告、Breeders’ Cup 赛程和参赛候选。数据页与公告归各机构所有；成品不携带官网抓取页面或用户缓存，不包含第三方桌宠程序代码。官方页面快照仅在独立制作目录内用于解析回归检查。

- https://www.jbis.or.jp/horse/0001339834/record/
- https://www.jairs.jp/2026_world_principal_race_schedule.pdf
- https://jra.jp/keiba/overseas/
- https://www.breederscup.com/watch
- https://www.breederscup.com/horses/entries

PDFKit 为 macOS 系统框架。气泡、按钮与文字输入使用现有 AppKit；不增加第三方运行依赖。
