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
        let securityManager = SecurityManager(sensor: sensor, tag: tag, logger: logger)
        await securityManager.performSecuritySetupIfNeeded()
        
        guard sensor.securityGeneration <= 1 else {
            logger.error("Activating a \(sensor.type) is not supported")
            throw LibreError.commandNotSupported("activate")
        }

        do {
            if sensor.debugLevel > 0 {
                try await securityManager.testOOPActivation()
            }


            if sensor.type == .libreProH {
                var readCommand = sensor.readBlockCommand
                readCommand.parameters = "DF 04".bytes
                var output = try await sensor.send(readCommand, tag: tag)
                logger.info("NFC: 'B0 read 0x04DF' command output: \(output.hex)")
                try await sensor.send(sensor.unlockCommand, tag: tag)
                var writeCommand = sensor.writeBlockCommand
                writeCommand.parameters = "DF 04 20 00 DF 88 00 00 00 00".bytes
                output = try await sensor.send(writeCommand, tag: tag)
                logger.info("NFC: 'B1 write' command output: \(output.hex)")
                try await sensor.send(sensor.lockCommand, tag: tag)
                output = try await sensor.send(readCommand, tag: tag)
                logger.info("NFC: 'B0 read 0x04DF' command output: \(output.hex)")
            }

            let output = try await sensor.send(sensor.activationCommand, tag: tag)
            logger.info("NFC: after trying to activate received \(output.hex) for the patch info \(sensor.patchInfo.hex)")

            // Libre 2
            if output.count == 4 {
                // receiving 9d081000 for a patchInfo 9d0830010000
                logger.info("NFC: \(sensor.type) should be activated and warming up")
            }
        } catch {
            logger.error("Activation failed: \(error.localizedDescription)")
            if let err = error as? LibreError {
                errorHandler(err)
            } else {
                errorHandler(LibreError.activationError(error.localizedDescription))
            }
            // TODO: manage errors and verify integrity
        }

        let (_, data) = try await sensor.read(tag: tag, fromBlock: 0, count: 43)
        sensor.fram = Data(data)
    }
}

extension Sensor {
    func convertToActivateResponse() -> [[String : Bool]] {
        // TODO @ddtch: implement actual logic if needed
        print("meow")
        return []
    }
}
