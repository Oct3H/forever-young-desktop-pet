import AppKit

enum CodexRPCError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? { if case let .unavailable(message) = self { return message }; return nil }
}

/// Uses the installed official CLI; proxy is preferred when a control socket exists.
/// A private stdio server is only allowed to start a turn on an idle tracked thread.
final class OfficialCodex: NSObject {
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var callbacks: [Int:(Result<[String:Any],Error>) -> Void] = [:]
    private var nextID = 1
    private(set) var ready = false
    private(set) var proxy = false
    private(set) var message = ""
    private(set) var activeTurns: [String:String] = [:]
    private var loaded = Set<String>()
    private var initializing: [(Result<Void,Error>)->Void] = []
    private var sequence = 0
    private let instance = UUID().uuidString
    var titles: [String:(title:String,project:String)] = [:]
    var onEvent: ((String,LinkedEvent)->Void)?
    var onChange: (() -> Void)?
    var requestHook: ((String,[String:Any],@escaping(Result<[String:Any],Error>)->Void)->Void)?
    static var cli: URL? {
        let fm = FileManager.default
        let paths = ["/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
                     "/Applications/Codex.app/Contents/Resources/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        return paths.first { fm.isExecutableFile(atPath:$0) }.map { URL(fileURLWithPath:$0) }
    }
    var object: [String:Any] { ["ready":ready,"transport":proxy ? "proxy" : "stdio","message":message,"activeThreads":Array(activeTurns.keys),"available":Self.cli != nil] }

    func connect(_ completion: @escaping(Result<Void,Error>)->Void) {
        if requestHook != nil { ready = true; completion(.success(())); return }
        if ready { completion(.success(())); return }
        initializing.append(completion)
        if process != nil { return }
        guard let cli = Self.cli else { fail("找不到本机 Codex CLI。请先安装或启动 Codex。"); return }
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
        let socket = URL(fileURLWithPath:home).appendingPathComponent("app-server-control/app-server-control.sock")
        proxy = FileManager.default.fileExists(atPath:socket.path)
        let proc = Process(); proc.executableURL = cli
        proc.arguments = proxy ? ["app-server","proxy","--sock",socket.path] : ["app-server","--stdio"]
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        proc.standardInput = stdin; proc.standardOutput = stdout; proc.standardError = stderr
        input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading; process = proc
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { self?.consume(data) }
        }
        // Never record CLI stderr: it may contain project data or authentication details.
        stderr.fileHandleForReading.readabilityHandler = { handle in if handle.availableData.isEmpty { handle.readabilityHandler = nil } }
        proc.terminationHandler = { [weak self] _ in DispatchQueue.main.async { self?.fail("Codex 官方本地服务已断开。可以重新连接。"); self?.onChange?() } }
        do {
            try proc.run()
            request("initialize",["clientInfo":["name":"foreveryoung_desktop_pet","title":"Forever Young Desktop Pet","version":"3.7"]]) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success:
                    self.write(["method":"initialized","params":[:]])
                    self.ready = true; self.message = self.proxy ? "官方本地控制通道" : "官方 stdio 通道；其他客户端执行中时不接管"
                    let pending = self.initializing; self.initializing.removeAll(); pending.forEach { $0(.success(())) }; self.onChange?()
                case let .failure(error): self.fail(error.localizedDescription)
                }
            }
        } catch { fail("无法启动本机 Codex 官方服务：\(error.localizedDescription)") }
    }
    private func fail(_ reason: String) {
        ready = false; message = reason
        output?.readabilityHandler = nil; output = nil; input = nil; buffer.removeAll()
        let proc = process; process = nil; proc?.terminationHandler = nil
        if proc?.isRunning == true { proc?.terminate() }
        let disconnected = Array(activeTurns.keys)
        loaded.removeAll(); activeTurns.removeAll()
        disconnected.forEach { emit(.disconnected,threadID:$0) }
        let error = CodexRPCError.unavailable(reason)
        let pending = callbacks; callbacks.removeAll(); pending.values.forEach { $0(.failure(error)) }
        let starters = initializing; initializing.removeAll(); starters.forEach { $0(.failure(error)) }
    }
    func request(_ method: String, _ params: [String:Any], completion: @escaping(Result<[String:Any],Error>)->Void) {
        if let hook = requestHook { hook(method,params,completion); return }
        guard process?.isRunning == true else { completion(.failure(CodexRPCError.unavailable("官方服务尚未连接。"))); return }
        let id = nextID; nextID += 1; callbacks[id] = completion
        write(["id":id,"method":method,"params":params])
        DispatchQueue.main.asyncAfter(deadline:.now()+20) { [weak self] in
            guard let callback = self?.callbacks.removeValue(forKey:id) else { return }
            callback(.failure(CodexRPCError.unavailable("官方接口响应超时；发送结果未确认，请先查看 Codex，避免重复发送。")))
        }
    }
    private func write(_ object: [String:Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject:object) else { return }
        data.append(10)
        do { try input?.write(contentsOf:data) } catch { fail("本地 Codex 通道写入失败。") }
    }
    private func consume(_ data: Data) {
        if data.isEmpty { return }
        buffer.append(data)
        guard buffer.count < 8_388_608 else { fail("官方接口消息超过支持大小。未继续处理。"); return }
        while let end = buffer.firstIndex(of:10) {
            let line = buffer.prefix(upTo:end); buffer.removeSubrange(...end)
            guard let object = try? JSONSerialization.jsonObject(with:line) as? [String:Any] else { continue }
            if let id = object["id"] as? Int, object["method"] == nil {
                if let error = object["error"] as? [String:Any] { callbacks.removeValue(forKey:id)?(.failure(CodexRPCError.unavailable(error["message"] as? String ?? "官方接口返回错误。"))) }
                else { callbacks.removeValue(forKey:id)?(.success(object["result"] as? [String:Any] ?? [:])) }
            } else if let method = object["method"] as? String {
                let params = object["params"] as? [String:Any] ?? [:]
                if object["id"] != nil { handleServerRequest(object,method:method,params:params) }
                else { notification(method,params:params) }
            }
        }
    }
    func notification(_ method: String, params: [String:Any]) {
        guard let id = params["threadId"] as? String, titles[id] != nil else { return }
        let turn = params["turn"] as? [String:Any] ?? [:]
        let item = params["item"] as? [String:Any] ?? [:]
        switch method {
        case "turn/started": activeTurns[id] = turn["id"] as? String; emit(.working,threadID:id)
        case "turn/completed":
            activeTurns.removeValue(forKey:id)
            let state: CodexActivity = turn["status"] as? String == "completed" ? .completed : turn["status"] as? String == "interrupted" ? .interrupted : .failed
            emit(state,threadID:id)
        case "item/started":
            let type = item["type"] as? String ?? ""
            emit(type == "enteredReviewMode" ? .review : ["commandExecution","mcpToolCall","webSearch","fileChange"].contains(type) ? .waiting : .working,threadID:id)
        case "item/completed": if activeTurns[id] != nil { emit(.working,threadID:id) }
        case "thread/status/changed":
            let status = params["status"] as? [String:Any] ?? [:]
            if status["type"] as? String == "systemError" { emit(.failed,threadID:id) }
        default: break // No prompt, tool output, delta text, or credentials retained.
        }
    }
    private func emit(_ state: CodexActivity, threadID: String) {
        guard let task = titles[threadID] else { return }
        sequence += 1
        onEvent?(threadID,LinkedEvent(version:1,source:.codex,instance:instance,sequence:sequence,sentAt:Date().timeIntervalSince1970*1000,state:state,runID:activeTurns[threadID] ?? threadID,title:task.title,project:task.project,activeCount:activeTurns[threadID] == nil ? 0 : 1))
        onChange?()
    }
    func send(_ text: String, to thread: CodexThreadSummary, activeElsewhere: Bool, completion: @escaping(Result<Void,Error>)->Void) {
        guard !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, text.utf8.count <= 32_768, codexThreadURL(thread.id) != nil else {
            completion(.failure(CodexRPCError.unavailable("请输入有效文字并选择要跟随的 Codex 任务。"))); return
        }
        connect { [weak self] connected in
            guard let self = self else { return }
            if case let .failure(error) = connected { completion(.failure(error)); return }
            if activeElsewhere && !self.proxy && self.activeTurns[thread.id] == nil {
                completion(.failure(CodexRPCError.unavailable("这项任务正在另一个 Codex 客户端执行，而本机未开放官方控制通道。请等本轮完成后直接发送；桌宠不会启动第二个执行者。"))); return
            }
            self.titles[thread.id] = (thread.title,thread.cwd)
            let submit: ()->Void = {
                let active = self.activeTurns[thread.id] ?? (activeElsewhere && self.proxy ? thread.turnID : nil)
                var params: [String:Any] = ["threadId":thread.id,"input":[["type":"text","text":text]]]
                if let active = active { params["expectedTurnId"] = active }
                self.request(active == nil ? "turn/start" : "turn/steer",params) { result in
                    switch result {
                    case let .failure(error): completion(.failure(error))
                    case let .success(value):
                        if let turn = value["turn"] as? [String:Any], let id = turn["id"] as? String { self.activeTurns[thread.id] = id; self.emit(.working,threadID:thread.id) }
                        completion(.success(()))
                    }
                }
            }
            if self.loaded.contains(thread.id) { submit() }
            else { self.request("thread/resume",["threadId":thread.id,"excludeTurns":true]) { result in
                switch result {
                case let .failure(error): completion(.failure(error))
                case .success: self.loaded.insert(thread.id); submit()
                }
            } }
        }
    }
    func interrupt(_ thread: CodexThreadSummary, completion: @escaping(Result<Void,Error>)->Void) {
        guard let turn = activeTurns[thread.id] ?? (proxy ? thread.turnID : nil), ready else { completion(.failure(CodexRPCError.unavailable("当前任务不是这个官方通道启动的，无法从桌宠停止。请在原客户端操作。"))); return }
        request("turn/interrupt",["threadId":thread.id,"turnId":turn]) { completion($0.map { _ in () }) }
    }
    private func handleServerRequest(_ object: [String:Any], method: String, params: [String:Any]) {
        guard let id = object["id"] else { return }
        if let thread = params["threadId"] as? String { emit(.waiting,threadID:thread) }
        guard ["item/commandExecution/requestApproval","item/fileChange/requestApproval"].contains(method) else {
            write(["id":id,"error":["code":-32601,"message":"This pet does not support this interactive request. No permission was granted."]]); return
        }
        let alert = NSAlert(); alert.messageText = "Codex · 请求批准"
        let detail = [params["command"] as? String, params["reason"] as? String].compactMap { $0 }.joined(separator:"\n")
        let scope = params["grantRoot"] as? String ?? params["cwd"] as? String ?? "—"
        alert.informativeText = String((detail.isEmpty ? "文件修改请求；请确认后再允许。" : detail).prefix(6000)) + "\n\n工作目录／申请范围：" + scope
        alert.addButton(withTitle:"允许本次"); alert.addButton(withTitle:"拒绝")
        NSApp.activate(ignoringOtherApps:true)
        let response = alert.runModal()
        write(["id":id,"result":["decision":response == .alertFirstButtonReturn ? "accept" : "decline"]])
    }
    func stop() { fail("官方通道已关闭。") }
}
