import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AISettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(macOS)
        Form {
            modelsSection
            Section { Toggle("AI 回答自动存为笔记卡片", isOn: $settings.autoSaveCards) }
                header: { Text("笔记") }
            Section { LabeledContent("版本", value: "0.1.0") }
                header: { Text("关于") }
        }
        .formStyle(.grouped)
        #else
        NavigationStack {
            Form {
                modelsSection
                Section("笔记") { Toggle("AI 回答自动存为笔记卡片", isOn: $settings.autoSaveCards) }
                Section("关于") { LabeledContent("版本", value: "0.1.0") }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        }
        #endif
    }

    @ViewBuilder
    private var modelsSection: some View {
        ForEach(Array(settings.models.enumerated()), id: \.element.id) { i, cfg in
            Section {
                Picker("供应商", selection: Binding(get: { cfg.provider }, set: { new in
                    var c = cfg; c.provider = new; c.baseURL = new.defaultBaseURL; c.model = new.defaultModel
                    updateModel(cfg, with: c)
                })) {
                    ForEach(AIProviderKind.allCases) { Text($0.displayName).tag($0) }
                }
                TextField("模型名", text: Binding(get: { cfg.model }, set: { new in
                    var c = cfg; c.model = new; updateModel(cfg, with: c)
                }))
                TextField("Base URL", text: Binding(get: { cfg.baseURL }, set: { new in
                    var c = cfg; c.baseURL = new; updateModel(cfg, with: c)
                }))
                SecureField("API Key", text: Binding(get: { settings.apiKey(for: cfg.id) }, set: { settings.setAPIKey($0, for: cfg.id) }))
                HStack {
                    if settings.defaultModelID == cfg.id {
                        Label("默认模型", systemImage: "checkmark")
                    } else {
                        // List 行内多按钮必须 borderless，否则点击互相串（曾把「设为默认」串成「删除」）
                        Button("设为默认") { settings.defaultModelID = cfg.id }
                            .buttonStyle(.borderless)
                    }
                    Spacer()
                    Button("删除", role: .destructive) { settings.deleteModel(cfg) }
                        .buttonStyle(.borderless)
                }
            } header: {
                Text("模型 \(i + 1)").textCase(nil)
            }
        }
        Section {
            Button { _ = settings.addModel() } label: {
                Label("添加模型", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
        }
    }

    private func updateModel(_ old: AIModelConfig, with new: AIModelConfig) {
        if let idx = settings.models.firstIndex(where: { $0.id == old.id }) {
            settings.models[idx] = new
            settings.objectWillChange.send()
        }
    }
}
