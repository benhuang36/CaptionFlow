import Foundation
import Combine

/// 集中管理本機 LLM 的選擇:依硬體自動推薦,或讓使用者手動指定。
@MainActor
final class ModelManager: ObservableObject {
    let profile: HardwareProfile
    @Published private(set) var catalog: [LLMModel]

    init(profile: HardwareProfile = .current, catalog: [LLMModel] = LLMCatalog.all) {
        self.profile = profile
        self.catalog = catalog
    }

    var recommended: LLMModel {
        ModelRecommender.recommended(for: profile, from: catalog)
    }

    func canRun(_ model: LLMModel) -> Bool {
        ModelRecommender.canRun(model, on: profile)
    }

    /// 依設定算出實際要用的模型:自動模式 → 推薦值;手動模式 → 使用者選的(找不到則退回推薦值)。
    func effectiveModel(for settings: AppSettings) -> LLMModel {
        if settings.autoSelectModel { return recommended }
        return LLMCatalog.model(id: settings.selectedModelID) ?? recommended
    }
}
