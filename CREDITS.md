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
