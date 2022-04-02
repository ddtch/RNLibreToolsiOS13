import CoreNFC
import Foundation

final class NFCStartSessionOperation: NFCAbstractOperation {
    
    override func performTask(tag: NFCISO15693Tag, sensor: Sensor) async throws {
        let securityManager = SecurityManager(sensor: sensor, tag: tag, toolbox: LibreToolbox(logger: logger, debugLevel: debugLevel))
        try await securityManager.passSecurityChallengeIfNeeded()
        let data = try await sensor.readFram(tag: tag)
        try await sensor.scanHistory(tag: tag)
        try await securityManager.passPostSecurityChallengedIfNeeded(data: data)
        // TODO: @ddtch applyOOP if needed
    }
}

extension Sensor {
    
    func convertToStartSessionResponse(history: History) -> [[String:[Double]]] {
        guard history.factoryTrend.count > 0 else { return [] }
            
        var trend : [Double] = history.factoryTrend.map({Double($0.value)})
        //.map({((Double($0.value) / 18.0182) * 10).rounded() / 10})
        let current = trend.remove(at: 0)
        let rawHistory: [Double] = history.factoryValues.map({Double($0.value)})//.map({((Double($0.value) / 18.0182) * 10).rounded() / 10})
        return [[
            "currentGluecose" : [current],
            "trendHistory" : trend,
            "history" : rawHistory
        ]]
    }
}

fileprivate extension Sensor {
    
    var startSessionBlocksToRead: Int {
        switch type {
        case .libreProH: return 22 + 24 // (32 * 6 / 8)
        default: return 43
        }
    }
}
