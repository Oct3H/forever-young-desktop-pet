# 素材与接口来源 / Credits

本项目是非官方、AI 辅助制作的フォーエバーヤング（Forever Young／青春永驻）桌宠。角色、官方决胜服立绘与游戏录音归 Cygames 及相应权利人；本仓库不代表官方发布。

This is an unofficial, AI-assisted Forever Young desktop pet. Character artwork and original recordings belong to Cygames and their respective rights holders.

- [官方角色页 / Official character page](https://umamusume.jp/character/foreveryoung)：角色设定、决胜服、CV 海弓シュリ与原官网语音。界面使用该页决胜服立绘；桌宠图集为 AI 辅助生成，包含九组动作与十六方向。
- [角色游戏语音录屏 / Character game-voice capture](https://www.bilibili.com/video/BV1tFfCBEEEn/)：玩家上传，非 Cygames 官方账号；原角色录音与官网样本、角色画面交叉核验。逐段范围和哈希见 [语音说明](语音来源与触发说明.md) 与应用资源 `voices/catalog.json`。
- [桌宠制作参考 / Pet reference](https://github.com/2846182283/zili-codex-pet)：动作／包装参考，未复制该作者角色素材。
- [hatch-pet](https://github.com/openai/skills/tree/main/skills/.curated/hatch-pet)：图集制作流程参考。功能图标由 AppKit 系统符号渲染，UI 无外部 CDN。
- [Codex App Server](https://learn.chatgpt.com/docs/app-server)、[VS Code API](https://code.visualstudio.com/api/references/vscode-api)、[JetBrains Execution API](https://plugins.jetbrains.com/docs/intellij/execution.html)：联动接口参考。
- [JRA 国内 GⅠ](https://jra.jp/datafile/seiseki/replay/g1.html)、[JRA 海外赛事](https://jra.jp/keiba/overseas/)、[JAIRS](https://www.jairs.jp/)、[Breeders’ Cup](https://www.breederscup.com/)、[JBIS 历史战绩](https://www.jbis.or.jp/horse/0001339834/record/)：本机赛事查询来源。官方网页快照、个人缓存和测试资料不随公开成品发布。

原始录音未合成或改变音色；没有用同 CV 的其他角色替代。核心窗口使用 Swift／AppKit，声音使用 AVFoundation，工作台使用 WebKit，赛事 PDF 使用 PDFKit；不打包 IDE SDK 类。
