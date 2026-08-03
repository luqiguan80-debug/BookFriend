import SwiftUI
import SwiftData

#if os(iOS)
@main
#endif
struct ShuYouApp: App {
    @StateObject private var aiSettings = AISettings()
    @State private var showWelcome = true

    let container: ModelContainer = {
        Storage.ensureDirectories()
        let schema = Schema([Book.self, NoteCard.self])
        // 有 iCloud entitlement 才启用 CloudKit 同步，否则纯本地（未签名本地构建）
        let cloudKit: ModelConfiguration.CloudKitDatabase = Entitlements.hasCloudKit ? .automatic : .none
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: cloudKit)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    var body: some Scene {
        WindowGroup {
            ZStack {
                BookshelfView()
                    .environmentObject(aiSettings)
                if showWelcome {
                    WelcomeView {
                        withAnimation(.easeOut(duration: 0.7)) { showWelcome = false }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
        }
        .modelContainer(container)
    }
}
