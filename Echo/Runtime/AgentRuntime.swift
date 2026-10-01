import Foundation
import SwiftUI
import SwiftData

@MainActor
@Observable
final class AgentRuntime {
    private(set) var phase: RunPhase = .idle
    private(set) var items: [RunItem] = []
    private(set) var plan: [StepState] = []
    private(set) var usage = RunUsage()
    private(set) var error: String?
    private(set) var pendingSteps: [StepState] = []
    private(set) var sessionId: UUID?

    var isBusy: Bool { phase == .planning || phase == .executing || phase == .summarising }
    var needsApproval: Bool { phase == .awaiting }

    private var task: Task<Void, Never>?
    private var goal = ""
    private var runStart = Date.now
    private var order = 0
    private var textId: String?
    private var reasonId: String?
    private var callBuf: [String: ToolCallView] = [:]
    private var callOrder: [String] = []

    func reset(for id: UUID) {
        task?.cancel()
        task = nil
        sessionId = id
        items = []
        persistedCount = 0
        plan = []
        pendingSteps = []
        usage = RunUsage()
        error = nil
        phase = .idle
        order = 0
        textId = nil
        reasonId = nil
        callBuf = [:]
        callOrder = []
    }

    func addNote(_ text: String) {
        guard sessionId != nil else { return }
        append(RunItem(.note, order: nextOrder(), text: text, status: .done))
    }

    func cancel() {
        task?.cancel()
        task = nil
        for i in items.indices where items[i].status == .running || items[i].status == .pending {
            items[i].status = .cancelled
        }
        for i in plan.indices where plan[i].status == .pending || plan[i].status == .running {
            plan[i].status = .cancelled
        }
        phase = .cancelled
    }

    func start(goal text: String, images: [Data], history: [OutMsg], settings: AppSettings,
               key: String, session: ChatSession, context: ModelContext) {
        if sessionId == session.id { persistAssistant(session: session, context: context) }
        reset(for: session.id)
        self.goal = text
        order = 0
        textId = nil
        reasonId = nil
        runStart = .now
        error = nil
        append(RunItem(.user, order: nextOrder(), text: text, status: .done, images: images))
        persistUser(text: text, session: session, context: context)

        let service = ChatService(settings: settings, apiKey: key)
        let tools = settings.modelSupportsTools ? ToolKit.schemas(settings) : []
        task = Task { [weak self] in
            await self?.runLoop(text: text, images: images, history: history, settings: settings,
                                service: service, tools: tools, session: session, context: context)
        }
    }

    func approveExecution(settings: AppSettings, key: String, session: ChatSession,
                          context: ModelContext, history: [OutMsg]) {
        guard phase == .awaiting else { return }
        let steps = pendingSteps
        pendingSteps = []
        plan = steps
        updatePlanItem(steps)
        let service = ChatService(settings: settings, apiKey: key)
        let tools = settings.modelSupportsTools ? ToolKit.schemas(settings) : []
        task = Task { [weak self] in
            await self?.execute(goal: self?.goal ?? "", steps: steps, history: history,
                                settings: settings, service: service, tools: tools,
                                session: session, context: context)
        }
    }

    func rejectApproval() {
        pendingSteps = []
        phase = .idle
    }

    private func nextOrder() -> Int { order += 1; return order }

    private func live(_ s: ItemStatus?) -> ItemStatusLive {
        guard let s else { return .pending }
        return ItemStatusLive(rawValue: s.rawValue) ?? .pending
    }

    private func append(_ item: RunItem) {
        items.append(item)
    }

    private func update(_ id: String, _ f: (inout RunItem) -> Void) {
        if let i = items.firstIndex(where: { $0.id == id }) { f(&items[i]) }
    }

    private func persistUser(text: String, session: ChatSession, context: ModelContext) {
        let m = ChatMessage(role: .user, text: text)
        m.runId = session.id
        session.messages.append(m)
        session.updatedAt = .now
        if session.title == "新会话" || session.title.isEmpty {
            session.title = String(text.prefix(24))
        }
        context.insert(session)
        context.insert(m)
    }

    // MARK: - main loop

    private func runLoop(text: String, images: [Data], history: [OutMsg], settings: AppSettings,
                         service: ChatService, tools: [ToolSchema], session: ChatSession,
                         context: ModelContext) async {
        do {
            phase = .planning
            let steps = try await makePlan(goal: text, history: history, settings: settings,
                                           service: service, toolNames: tools.map(\.name))
            plan = steps
            append(RunItem(.plan, order: nextOrder(), title: "执行计划",
                           status: live(steps.first?.status), steps: steps))
            if !settings.autoApprove {
                pendingSteps = steps
                phase = .awaiting
                return
            }
            await execute(goal: text, steps: steps, history: history, settings: settings,
                          service: service, tools: tools, session: session, context: context)
        } catch {
            fail(error, session: session, context: context)
        }
    }

    private func makePlan(goal: String, history: [OutMsg], settings: AppSettings,
                          service: ChatService, toolNames: [String]) async throws -> [StepState] {
        var req = ChatRequest(base: settings, model: settings.model)
        req.system = Planner.plannerSystem(toolNames: toolNames)
        req.messages = Array(history.suffix(6)) + [.user("目标：" + goal)]
        req.tools = []
        req.stream = false
        req.thinking = false
        req.temperature = 0.2
        let reply = try await service.next(req)
        let parsed = Planner.parseSteps(reply.text)
        if parsed.isEmpty {
            return [StepState(id: 1, title: "直接回答", detail: goal)]
        }
        return parsed
    }

    private func execute(goal: String, steps: [StepState], history: [OutMsg], settings: AppSettings,
                         service: ChatService, tools: [ToolSchema], session: ChatSession,
                         context: ModelContext) async {
        phase = .executing
        var record: [String] = []
        for idx in steps.indices {
            if Task.isCancelled { break }
            var step = steps[idx]
            step.status = .running
            setStep(step, at: idx)
            let noteId = "note-\(step.id)"
            append(RunItem(id: noteId, .text, order: nextOrder(),
                           text: "▸ 第 \(idx + 1)/\(steps.count) 步：\(step.title)", status: .running))
            do {
                let outcome = try await runStep(step: step, index: idx, total: steps.count,
                                                steps: steps, goal: goal, record: record,
                                                history: history, settings: settings,
                                                service: service, tools: tools)
                step.status = .done
                step.note = outcome
                setStep(step, at: idx)
                update(noteId) { $0.status = .done }
                record.append("\(step.title)：\(outcome.clamped(600))")
            } catch {
                step.status = .failed
                step.note = error.localizedDescription
                setStep(step, at: idx)
                update(noteId) { $0.status = .failed }
                record.append("\(step.title)：失败 \(error.localizedDescription)")
                if Task.isCancelled { break }
            }
        }
        if Task.isCancelled { finishCancel(session: session, context: context); return }
        await summarise(goal: goal, record: record, history: history, settings: settings,
                        service: service, session: session, context: context)
    }

    private func runStep(step: StepState, index: Int, total: Int, steps: [StepState], goal: String,
                         record: [String], history: [OutMsg], settings: AppSettings,
                         service: ChatService, tools: [ToolSchema]) async throws -> String {
        var req = ChatRequest(base: settings, model: settings.model)
        req.system = Planner.executorSystem(settings: settings, goal: goal, steps: steps,
                                            index: index, record: record)
        req.messages = Array(history.suffix(settings.historyLimit))
            + [.user("现在执行第 \(index + 1) 步：\(step.title)\n细节：\(step.detail)")]
        req.tools = tools
        req.stream = settings.stream
        req.thinking = settings.deepThink
        var msgs = req.messages
        var produced: [String] = []

        for turn in 0..<settings.maxTurnsPerStep {
            if Task.isCancelled { throw ChatError.cancelled }
            req.messages = msgs
            let collected: Collected
            do {
                collected = try await collect(req: req, service: service)
            } catch {
                guard !req.tools.isEmpty, Self.isToolRejection(error) else { throw error }
                NoToolMemory.remember(settings.model)
                req.tools = []
                append(RunItem(.note, order: nextOrder(),
                               text: "\(settings.model) 这个接口不接受工具调用，已改为直接作答", status: .done))
                collected = try await collect(req: req, service: service)
            }
            let spoken = collected.text
            if collected.calls.isEmpty {
                let tail = produced.isEmpty ? "" : "｜产出 " + produced.joined(separator: "，")
                if spoken.isEmpty { return tail.isEmpty ? "无输出" : String(tail.dropFirst()) }
                return spoken.clamped(400) + tail
            }
            msgs.append(.assistant(spoken, calls: collected.calls.map {
                AssistCall(id: $0.id, name: $0.name, arguments: $0.args)
            }))
            for call in collected.calls {
                if Task.isCancelled { throw ChatError.cancelled }
                guard let tool = ToolID(rawValue: call.name), settings.toolAllowed(tool) else {
                    let msg = "没有这个工具：\(call.name)"
                    update(call.id) {
                        $0.status = .failed
                        $0.text = msg
                        $0.call = ToolCallView(id: call.id, name: call.name, argsJSON: call.args,
                                               result: msg, status: .failed,
                                               startedAt: .now, endedAt: .now)
                    }
                    msgs.append(.tool(call.id, name: call.name, result: msg))
                    continue
                }
                let started = Date.now
                update(call.id) {
                    $0.status = .running
                    $0.argsDisplay = call.args
                    $0.call = ToolCallView(id: call.id, name: call.name, argsJSON: call.args,
                                           result: "", status: .running,
                                           startedAt: started, endedAt: started)
                }
                let outcome = await ToolKit.execute(tool, json: call.args, settings: settings)
                let shown = outcome.displayText
                let ended = Date.now
                update(call.id) {
                    $0.status = .done
                    $0.text = shown
                    $0.call = ToolCallView(id: call.id, name: call.name, argsJSON: call.args,
                                           result: shown, status: .done,
                                           startedAt: started, endedAt: ended)
                }
                if case .file(let name, let url, let bytes, let preview, let added, let removed) = outcome {
                    produced.append(name)
                    append(RunItem(.file, order: nextOrder(), text: preview, title: name,
                                   status: .done, path: url.path,
                                   file: RunFile(name: name, path: url.path, size: bytes,
                                                 preview: preview, added: added, removed: removed)))
                }
                msgs.append(.tool(call.id, name: call.name,
                                  result: outcome.modelText.clamped(8000)))
            }
            if turn == settings.maxTurnsPerStep - 1 {
                return "步数用完｜" + (produced.isEmpty ? spoken.clamped(200)
                                    : produced.joined(separator: "，"))
            }
        }
        return produced.joined(separator: "，")
    }

    struct CollectedCall { let id: String; let name: String; var args: String }
    struct Collected { let text: String; let reasoning: String; let calls: [CollectedCall] }

    private func collect(req: ChatRequest, service: ChatService) async throws -> Collected {
        textId = nil
        reasonId = nil
        callBuf = [:]
        callOrder = []
        var text = ""
        var reason = ""
        for try await ev in service.stream(req) {
            if Task.isCancelled { throw ChatError.cancelled }
            switch ev {
            case .textDelta(let d):
                text += d
                streamText(text)
            case .reasonDelta(let d):
                reason += d
                streamReason(reason)
            case .callStart(let id, let name):
                if callBuf[id] == nil {
                    callBuf[id] = ToolCallView(id: id, name: name, argsJSON: "", result: "",
                                               status: .pending, startedAt: .now, endedAt: .now)
                    callOrder.append(id)
                    append(RunItem(id: id, .tool, order: nextOrder(), title: name,
                                   status: .pending, call: callBuf[id]))
                }
            case .callArgs(let id, let d):
                let key = callOrder.last ?? id
                if callBuf[key] == nil {
                    callBuf[key] = ToolCallView(id: key, name: "tool", argsJSON: "", result: "",
                                                status: .pending, startedAt: .now, endedAt: .now)
                    callOrder.append(key)
                }
                callBuf[key]?.argsJSON += d
                if let c = callBuf[key] { update(key) { $0.call = c; $0.path = c.argsJSON } }
            case .usage(let p, let c):
                usage.prompt += p
                usage.completion += c
            case .stop:
                break
            case .serverError(let m):
                throw ChatError.http(-1, m)
            }
        }
        let calls = callOrder.compactMap { callBuf[$0] }.map {
            CollectedCall(id: $0.id, name: $0.name, args: $0.argsJSON.isEmpty ? "{}" : $0.argsJSON)
        }
        textId = nil
        reasonId = nil
        return Collected(text: text, reasoning: reason, calls: calls)
    }

    private func streamText(_ full: String) {
        if let i = textId {
            update(i) { $0.text = full }
        } else {
            let new = "txt-\(nextOrder())"
            textId = new
            append(RunItem(id: new, .text, order: nextOrder(), text: full, status: .running))
        }
    }

    private func streamReason(_ full: String) {
        if let i = reasonId {
            update(i) { $0.text = full }
        } else {
            let new = "rsn-\(nextOrder())"
            reasonId = new
            append(RunItem(id: new, .text, order: nextOrder(), text: full, title: "思考",
                           status: .running))
        }
    }

    private func summarise(goal: String, record: [String], history: [OutMsg], settings: AppSettings,
                           service: ChatService, session: ChatSession, context: ModelContext) async {
        phase = .summarising
        do {
            var req = ChatRequest(base: settings, model: settings.model)
            req.system = Planner.summariseSystem
            req.messages = Array(history.suffix(settings.historyLimit))
                + [.user("目标：\(goal)\n\n执行记录：\n" + record.joined(separator: "\n")
                    + "\n\n现在给用户写最终回复。")]
            req.tools = []
            req.stream = settings.stream
            req.thinking = false
            let collected = try await collect(req: req, service: service)
            let body = collected.text.isEmpty ? "（这一步没生成文字，看上面的执行结果）" : collected.text
            append(RunItem(id: "final", .text, order: nextOrder(), text: body, status: .done))
            saveCodeFiles(from: body, hint: goal)
            usage.seconds = Date.now.timeIntervalSince(runStart)
            phase = .done
            Notifier.shared.runDone(title: "任务完成", body: goal.clamped(40))
            persistAssistant(session: session, context: context)
        } catch {
            fail(error, session: session, context: context)
        }
    }

    static func isToolRejection(_ e: Error) -> Bool {
        guard case let ChatError.http(code, body) = e as? ChatError, (400...499).contains(code) else {
            return false
        }
        let b = body.lowercased()
        return b.contains("tool") || b.contains("function") || b.contains("工具") || b.contains("不支持")
    }

    private func saveCodeFiles(from text: String, hint: String) {
        let skip = Set(items.compactMap { $0.file?.name })
        for c in CodeFiles.candidates(from: text, hint: hint, skip: skip) {
            guard let url = try? FileStore.shared.write(c.name, c.content) else { continue }
            let bytes = (try? Data(contentsOf: url))?.count ?? c.content.utf8.count
            let head = c.content.components(separatedBy: "\n").prefix(3).joined(separator: " ")
            append(RunItem(.file, order: nextOrder(), text: head.clamped(120), title: c.name,
                           status: .done, path: url.path,
                           file: RunFile(name: c.name, path: url.path, size: bytes,
                                         preview: head.clamped(120),
                                         added: c.lineCount, removed: 0)))
        }
    }

    private func fail(_ e: Error, session: ChatSession, context: ModelContext) {
        if e is CancellationError { finishCancel(session: session, context: context); return }
        error = e.localizedDescription
        append(RunItem(.error, order: nextOrder(), text: e.localizedDescription, status: .failed))
        phase = .failed
        persistAssistant(session: session, context: context)
    }

    private func finishCancel(session: ChatSession, context: ModelContext) {
        phase = .cancelled
        persistAssistant(session: session, context: context)
    }

    private func setStep(_ step: StepState, at idx: Int) {
        guard idx < plan.count else { return }
        plan[idx] = step
        updatePlanItem(plan)
    }

    private func updatePlanItem(_ steps: [StepState]) {
        if let i = items.firstIndex(where: { $0.kind == .plan }) {
            items[i].steps = steps
            items[i].status = steps.contains { $0.status == .running } ? .running : .done
        }
    }

    private var persistedCount = 0

    var thinkingCount: Int { items.filter { $0.isReasoning }.count }
    var toolCount: Int { items.filter { $0.kind == .tool }.count }
    var runFiles: [RunFile] { items.compactMap(\.file) }
    var totalAdded: Int { runFiles.reduce(0) { $0 + $1.added } }
    var totalRemoved: Int { runFiles.reduce(0) { $0 + $1.removed } }
    var hasUnpersisted: Bool { persistedCount < items.count }

    func persistIfNeeded(session: ChatSession, context: ModelContext) {
        if hasUnpersisted { persistAssistant(session: session, context: context) }
    }

    func persistAssistant(session: ChatSession, context: ModelContext) {
        let m = ChatMessage(role: .assistant)
        m.runId = session.id
        var order = persistedCount
        for item in items.dropFirst(persistedCount) {
            if item.kind == .user { continue }
            order += 1
            let b = MsgBlock(kind: item.kind, order: order, text: item.text,
                             language: item.language, title: item.title,
                             status: ItemStatus(rawValue: item.status.rawValue) ?? .done,
                             path: item.path, startedAt: item.startedAt, endedAt: item.endedAt,
                             stepsJSON: item.kind == .plan
                                ? (String(data: (try? JSONEncoder().encode(item.steps)) ?? Data(),
                                          encoding: .utf8) ?? "") : "",
                             metaJSON: item.kind == .file
                                ? MsgBlock.meta(added: item.file?.added ?? 0,
                                                removed: item.file?.removed ?? 0,
                                                size: item.file?.size ?? 0) : "")
            if let c = item.call {
                b.text = c.result.isEmpty ? item.text : c.result
                b.path = c.argsJSON
            }
            context.insert(b)
            m.blocks.append(b)
        }
        persistedCount = items.count
        m.text = items.filter { $0.kind == .text && !$0.isReasoning }.map(\.text).joined(separator: "\n\n")
        context.insert(m)
        session.messages.append(m)
        session.updatedAt = .now
        context.insert(session)
        try? context.save()
    }

}
