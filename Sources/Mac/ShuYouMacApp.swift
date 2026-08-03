import SwiftUI
import SwiftData

#if os(macOS)
@main
#endif
struct ShuYouMacApp: App {
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
            .frame(minWidth: 700, idealWidth: 900, maxWidth: .infinity,
                   minHeight: 500, idealHeight: 700, maxHeight: .infinity)
        }
        .modelContainer(container)
        .windowResizability(.contentMinSize)
    }
}

// macOS 上不需要 iOS 的 ShuYouApp
#if os(iOS)
// (iOS entry point in Sources/App/)
#endif
