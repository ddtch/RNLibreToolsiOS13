import CoreNFC
import Foundation

final class NFCReadFramOperation: NFCAbstractOperation {
    
    override func performTask(tag: NFCISO15693Tag, sensor: Sensor) async throws {
        let securityManager = SecurityManager(sensor: sensor, tag: tag, toolbox: LibreToolbox(logger: logger, debugLevel: debugLevel))
        try await securityManager.passSecurityChallengeIfNeeded()
        let data = try await sensor.readFram(tag: tag)
        try await sensor.scanHistory(tag: tag)
        try await securityManager.passPostSecurityChallengedIfNeeded(data: data)
    }
}

extension Sensor {

    func convertToReadFramResponse(sensorInfo: SensorInfo) throws -> [[String: String]] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(sensorInfo)

        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw LibreError.unexpected("bad data") // should never happen
        }
        
        return [["sensorInfo": jsonString]]
    }
}
