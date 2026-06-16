import Foundation

/// UserDefaults 中存放「介面語言覆蓋」的鍵。值為語言碼(如 "ja"),
/// 或 "system"/空字串代表跟隨系統。與 AppSettings 的 @AppStorage("appLanguage") 同步。
let appLanguageKey = "appLanguage"

/// runtime 字串(狀態列、錯誤訊息等非 SwiftUI 字面值)的在地化入口。
///
/// SwiftUI 的 `Text("...")` 會吃 environment 的 \.locale 自動在地化;但在
/// View 之外組出的字串走 verbatim,不會自動翻譯。這裡依使用者選的介面語言,
/// 解析對應的 .lproj bundle,讓這些字串與 UI 一致(免重啟即時切換)。
enum Localized {
    static func string(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: overrideBundle)
    }

    /// 依介面語言覆蓋挑選 bundle;跟隨系統時回主 bundle(用系統語言)。
    private static var overrideBundle: Bundle {
        let code = UserDefaults.standard.string(forKey: appLanguageKey) ?? ""
        guard !code.isEmpty, code != "system",
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return .main }
        return bundle
    }
}
