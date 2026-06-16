import Foundation

enum ModelRecommender {
    /// 在記憶體預算內挑「品質最高」的模型;同品質時挑參數較大的。
    /// 若連最小模型都放不下,仍回傳最小模型(讓 UI 能提示改用 Apple Translation)。
    static func recommended(for profile: HardwareProfile,
                            from catalog: [LLMModel] = LLMCatalog.all) -> LLMModel {
        let budget = profile.llmBudgetGB
        let fitting = catalog.filter { $0.approxRAMGB <= budget }
        let ranked = fitting.sorted { a, b in
            if a.quality != b.quality { return a.quality < b.quality }
            return a.parameterCountB < b.parameterCountB
        }
        return ranked.last ?? catalog.min { $0.approxRAMGB < $1.approxRAMGB }!
    }

    /// 這台機器是否跑得動指定模型。
    static func canRun(_ model: LLMModel, on profile: HardwareProfile) -> Bool {
        model.approxRAMGB <= profile.llmBudgetGB
    }
}
