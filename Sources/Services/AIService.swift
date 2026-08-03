import Foundation

enum AIError: LocalizedError {
    case missingAPIKey
    case invalidURL(String)
    case badResponse(Int, String, String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "请先在设置中填入 API Key"
        case .invalidURL(let url): return "API 地址无效：\(url)"
        case .badResponse(let code, let body, let url):
            let hint = code == 404 ? "\n请求地址：\(url)\n提示：Base URL 只需填根地址，不要带 /chat/completions 或 /v1/messages" : ""
            return "API 返回 \(code)\n\(body.prefix(200))\(hint)"
        }
    }
}

/// 统一的大模型流式调用：OpenAI 兼容接口 + Anthropic 原生接口（PRD 4.5）
final class AIService {

    /// 单轮兼容封装（等价于 messages 里只有一条 user 消息）
    func stream(system: String, user: String,
                settings: AISettings) -> AsyncThrowingStream<String, Error> {
        stream(system: system, messages: [ChatMessage(role: .user, content: user)], settings: settings)
    }

    /// 多轮流式调用：messages 为完整对话历史（user 开头、交替；不要包含末尾空的 assistant 占位）
    func stream(system: String, messages: [ChatMessage],
                settings: AISettings) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream(String.self) { continuation in
            let task = Task {
                do {
                    guard !settings.apiKey.isEmpty else { throw AIError.missingAPIKey }
                    switch settings.provider {
                    case .openAICompatible:
                        try await streamOpenAI(system: system, messages: messages, settings: settings) {
                            continuation.yield($0)
                        }
                    case .anthropic:
                        try await streamAnthropic(system: system, messages: messages, settings: settings) {
                            continuation.yield($0)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 非流式调用：静默消费流，返回完整文本（用于笔记要点提取等后台调用）
    func complete(system: String, user: String, settings: AISettings) async throws -> String {
        var result = ""
        for try await chunk in stream(system: system, user: user, settings: settings) {
            result += chunk
        }
        return result
    }

    // MARK: - OpenAI 兼容（/chat/completions，SSE）

    private func cleanBaseURL(_ raw: String) -> String {
        var b = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        for suffix in ["/chat/completions", "/v1/messages", "/v1/chat/completions", "/completions"] {
            if b.hasSuffix(suffix) { b = String(b.dropLast(suffix.count)) }
        }
        return b
    }

    private func streamOpenAI(system: String, messages: [ChatMessage],
                              settings: AISettings,
                              yield: (String) -> Void) async throws {
        let base = cleanBaseURL(settings.baseURL)
        guard let url = URL(string: base + "/chat/completions") else {
            throw AIError.invalidURL(base)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        var wire: [[String: String]] = [["role": "system", "content": system]]
        wire += messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        let body: [String: Any] = [
            "model": settings.model,
            "stream": true,
            "messages": wire,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try validate(response, url: request.url?.absoluteString ?? "")
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String else { continue }
            yield(content)
        }
    }

    // MARK: - Anthropic（/v1/messages，SSE）

    private func streamAnthropic(system: String, messages: [ChatMessage],
                                 settings: AISettings,
                                 yield: (String) -> Void) async throws {
        let base = cleanBaseURL(settings.baseURL)
        guard let url = URL(string: base + "/v1/messages") else {
            throw AIError.invalidURL(base)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(settings.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 60
        let body: [String: Any] = [
            "model": settings.model,
            "max_tokens": 2048,
            "stream": true,
            "system": system,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try validate(response, url: request.url?.absoluteString ?? "")
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["type"] as? String == "content_block_delta",
                  let delta = json["delta"] as? [String: Any],
                  let text = delta["text"] as? String else { continue }
            yield(text)
        }
    }

    // MARK: - OCR（视觉识别）

    func ocr(imageBase64: String, mediaType: String = "image/jpeg",
             settings: AISettings) -> AsyncThrowingStream<String, Error> {
        let prompt = "请识别并提取这张图片中的所有文字，保持原文的格式和顺序。只输出文字，不要添加任何解释。"
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !settings.apiKey.isEmpty else { throw AIError.missingAPIKey }
                    switch settings.provider {
                    case .openAICompatible:
                        try await ocrOpenAI(imageBase64: imageBase64, mediaType: mediaType,
                                           prompt: prompt, settings: settings) {
                            continuation.yield($0)
                        }
                    case .anthropic:
                        try await ocrAnthropic(imageBase64: imageBase64, mediaType: mediaType,
                                              prompt: prompt, settings: settings) {
                            continuation.yield($0)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func ocrOpenAI(imageBase64: String, mediaType: String,
                           prompt: String, settings: AISettings,
                           yield: (String) -> Void) async throws {
        let base = cleanBaseURL(settings.baseURL)
        guard let url = URL(string: base + "/chat/completions") else {
            throw AIError.invalidURL(base)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120
        let body: [String: Any] = [
            "model": settings.model,
            "max_tokens": 4096,
            "stream": true,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url",
                     "image_url": ["url": "data:\(mediaType);base64,\(imageBase64)"]],
                ],
            ]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try validate(response, url: request.url?.absoluteString ?? "")
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String else { continue }
            yield(content)
        }
    }

    private func ocrAnthropic(imageBase64: String, mediaType: String,
                              prompt: String, settings: AISettings,
                              yield: (String) -> Void) async throws {
        let base = cleanBaseURL(settings.baseURL)
        guard let url = URL(string: base + "/v1/messages") else {
            throw AIError.invalidURL(base)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(settings.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 120
        let body: [String: Any] = [
            "model": settings.model,
            "max_tokens": 4096,
            "stream": true,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image",
                     "source": ["type": "base64", "media_type": mediaType, "data": imageBase64]],
                ],
            ]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try validate(response, url: request.url?.absoluteString ?? "")
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["type"] as? String == "content_block_delta",
                  let delta = json["delta"] as? [String: Any],
                  let text = delta["text"] as? String else { continue }
            yield(text)
        }
    }

    private func validate(_ response: URLResponse, url: String) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw AIError.badResponse(http.statusCode, "", url)
        }
    }
}
