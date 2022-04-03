//
//  File.swift
//  
//
//  Created by Yury Dymov on 3/15/22.
//

import Foundation
import CoreNFC

final class NFCActivateOperation: NFCAbstractOperation {
    
    override func performTask(tag: NFCISO15693Tag, sensor: Sensor) async throws {
        let securityManager = SecurityManager(sensor: sensor, tag: tag, toolbox: LibreToolbox(logger: logger, debugLevel: debugLevel))
        await securityManager.performSecuritySetupIfNeeded()
        
        guard sensor.securityGeneration <= 1 else {
            logger.error("Activating a \(sensor.type) is not supported")
            throw LibreError.commandNotSupported("activate")
        }

        do {
            if debugLevel > 0 {
                try await securityManager.testOOPActivation()
            }
            
            try await sensor.activate(tag: tag)
        } catch {
            logger.error("Activation failed: \(error.localizedDescription)")
            if let err = error as? LibreError {
                errorHandler(err)
            } else {
                errorHandler(LibreError.activationError(error.localizedDescription))
            }
            // TODO: manage errors and verify integrity
            return
        }
        
        try await sensor.readFram(tag: tag)
    }
}

extension Sensor {
    func convertToActivateResponse() -> [[String : Bool]] {
        // TODO @ddtch: implement actual logic if needed
        return []
    }
}
