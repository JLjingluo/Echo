import Foundation
import JavaScriptCore

enum ScriptRunner {
    static func run(_ source: String, input: String) async -> String {
        await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: execute(source, input))
            }
        }
    }

    private static func execute(_ source: String, _ input: String) -> String {
        guard let ctx = JSContext() else { return "❌ JavaScriptCore 起不来" }
        var errors: [String] = []
        ctx.exceptionHandler = { _, ex in
            if let ex { errors.append("❌ JS 错误: \(ex)") }
        }
        let hook = """
        var __out = [];
        function emit() { __out.push(Array.from(arguments).map(x => typeof x === 'object' ? JSON.stringify(x) : String(x)).join(' ')); }
        function log() { emit.apply(null, arguments); }
        var console = { log: log, warn: log, error: log, info: log, table: log };
        var print = log;
        """
        ctx.evaluateScript(hook)
        let safeInput = input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "null" : input
        ctx.evaluateScript("var input = \(safeInput);")
        ctx.evaluateScript(source)
        let out = ctx.evaluateScript("__out.join('\\n')")?.toString() ?? ""
        let msg = errors.joined(separator: "\n")
        if out.isEmpty { return msg.isEmpty ? "(没有任何输出，用 emit() 或 console.log() 打印结果)" : msg }
        return msg.isEmpty ? out : out + "\n" + msg
    }
}
