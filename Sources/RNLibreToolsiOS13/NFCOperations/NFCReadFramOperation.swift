import CoreNFC
import Foundation

final class NFCReadFramOperation: NFCAbstractOperation {
    
    override func performTask(tag: NFCISO15693Tag, sensor: Sensor) async throws {
        let securityManager = SecurityManager(sensor: sensor, tag: tag, logger: logger)
        try await securityManager.passSecurityChallengeIfNeeded()
        let blocks = sensor.readFramBlocksToRead
        
        let (start, data) = try await sensor.securityGeneration < 2 ?
        sensor.read(tag: tag, fromBlock: 0, count: blocks) : sensor.readBlocks(tag: tag, from: 0, count: blocks)
        sensor.lastReadingDate = Date()
        sensor.fram = Data(data)
        try await sensor.scanHistory(tag: tag)
        logger.info(data.hexDump(header: "NFC: did read \(data.count / 8) FRAM blocks:", startBlock: start))
        try await securityManager.passPostSecurityChallengedIfNeeded(data: data)
    }
}

extension Sensor {

    func convertToReadFramResponse() throws -> [[String: String]] {
        do {
            let sensInfo = try self.detailFRAM()
            return [["sensorInfo": sensInfo]]
        } catch {
            throw LibreError.readFailure("Can not get senser info")
        }
        
    }
}

fileprivate extension Sensor {
    
    var readFramBlocksToRead: Int {
        switch type {
        case .libre1: return 244
        case .libreProH: return 22 + 24 // (32 * 6 / 8)
        default: return 43
        }
    }
}
