import Foundation

/// 針對統一記憶體(unified memory)的硬體側寫。LLM 不是吃獨立 VRAM,
/// 而是跟 OS、STT、本 app、以及使用者同時開的軟體(Zoom、瀏覽器)搶同一塊 RAM,
/// 所以可分配給 LLM 的預算要刻意保守。
struct HardwareProfile {
    let totalRAMGB: Double

    /// 願意分配給 LLM 的記憶體上限:
    /// 預留 ~8GB 給其餘所有東西,且永遠不超過總量的 60%。
    var llmBudgetGB: Double {
        max(0, min(totalRAMGB - 8.0, totalRAMGB * 0.6))
    }

    static var current: HardwareProfile {
        let bytes = ProcessInfo.processInfo.physicalMemory
        return HardwareProfile(totalRAMGB: Double(bytes) / 1_073_741_824.0)
    }
}
