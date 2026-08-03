import Foundation
import Security

/// 读取应用自身签名里的 entitlement。
/// 未签名/临时签名的本地构建没有 iCloud 权限，此时开 CloudKit 会直接崩（NSException，catch 不住），
/// 所以启动时先探测，有权限才启用同步，否则退回纯本地。
enum Entitlements {
    static let hasCloudKit: Bool = {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let services = SecTaskCopyValueForEntitlement(
                task, "com.apple.developer.icloud-services" as CFString, nil) as? [String]
        else { return false }
        return services.contains("CloudKit")
        #else
        // iOS 没有公开的 SecTask API；未签名/模拟器构建一律按无 iCloud 权限处理
        return false
        #endif
    }()
}
