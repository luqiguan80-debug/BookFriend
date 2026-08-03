import Foundation

enum AIProviderKind: String, CaseIterable, Codable, Identifiable {
    case openAICompatible, anthropic
    var id: String { rawValue }
    var displayName: String { self == .openAICompatible ? "OpenAI" : "Anthropic" }
    var defaultBaseURL: String {
        self == .openAICompatible ? "https://api.openai.com/v1" : "https://api.anthropic.com"
    }
    var defaultModel: String {
        self == .openAICompatible ? "gpt-4o-mini" : "claude-haiku-4-5-20251001"
    }
}

struct AIModelConfig: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var provider: AIProviderKind
    var baseURL: String
    var model: String
}

final class AISettings: ObservableObject {
    @Published var models: [AIModelConfig] { didSet { saveModels() } }
    @Published var defaultModelID: UUID? { didSet { defaults.set(defaultModelID?.uuidString, forKey: "ai.default") } }
    @Published var autoSaveCards: Bool { didSet { defaults.set(autoSaveCards, forKey: "ai.autoSaveCards") } }

    private let defaults = UserDefaults.standard

    var activeModel: AIModelConfig? { models.first(where: { $0.id == defaultModelID }) ?? models.first }

    // 兼容旧 AIService 调用——从 active model 取值
    var provider: AIProviderKind { activeModel?.provider ?? .openAICompatible }
    var baseURL: String { activeModel?.baseURL ?? AIProviderKind.openAICompatible.defaultBaseURL }
    var model: String { activeModel?.model ?? "gpt-4o-mini" }
    var apiKey: String { activeModel.map { apiKey(for: $0.id) } ?? "" }

    func apiKey(for modelID: UUID) -> String {
        Keychain.get("shuyou.model.\(modelID.uuidString)") ?? ""
    }
    func setAPIKey(_ key: String, for modelID: UUID) { Keychain.set(key, for: "shuyou.model.\(modelID.uuidString)") }

    init() {
        let d = UserDefaults.standard
        self.autoSaveCards = d.object(forKey: "ai.autoSaveCards") as? Bool ?? true

        // 加载已保存的模型列表
        if let data = d.data(forKey: "ai.models"),
           let saved = try? JSONDecoder().decode([AIModelConfig].self, from: data), !saved.isEmpty {
            self.models = saved
        } else {
            // 首次启动：尝试迁移旧的单模型配置
            let p = AIProviderKind(rawValue: d.string(forKey: "ai.provider") ?? "") ?? .openAICompatible
            let oldKey = Keychain.get("shuyou.apikey.\(p.rawValue)")
            if let oldKey, !oldKey.isEmpty {
                let oldModel = AIModelConfig(name: p.displayName, provider: p,
                    baseURL: d.string(forKey: "ai.baseURL.\(p.rawValue)") ?? p.defaultBaseURL,
                    model: d.string(forKey: "ai.model.\(p.rawValue)") ?? p.defaultModel)
                self.models = [oldModel]
                self.setAPIKey(oldKey, for: oldModel.id)
                // 清理旧格式
                Keychain.delete("shuyou.apikey.\(p.rawValue)")
                d.removeObject(forKey: "ai.provider")
                d.removeObject(forKey: "ai.baseURL.\(p.rawValue)")
                d.removeObject(forKey: "ai.model.\(p.rawValue)")
            } else {
                self.models = []
            }
        }

        if let idStr = d.string(forKey: "ai.default"), let id = UUID(uuidString: idStr),
           models.contains(where: { $0.id == id }) {
            self.defaultModelID = id
        } else {
            self.defaultModelID = models.first?.id
        }
    }

    func addModel(name: String = "", provider: AIProviderKind = .openAICompatible) -> AIModelConfig {
        let cfg = AIModelConfig(name: name.isEmpty ? provider.displayName : name,
                                provider: provider,
                                baseURL: provider.defaultBaseURL,
                                model: provider.defaultModel)
        models.append(cfg)
        if models.count == 1 { defaultModelID = cfg.id }
        return cfg
    }

    func deleteModel(_ cfg: AIModelConfig) {
        Keychain.delete("shuyou.model.\(cfg.id.uuidString)")
        models.removeAll { $0.id == cfg.id }
        if defaultModelID == cfg.id { defaultModelID = models.first?.id }
    }

    private func saveModels() {
        if let data = try? JSONEncoder().encode(models) {
            defaults.set(data, forKey: "ai.models")
        }
    }
}
