//
//  AbstractLibre2.swift
//  LibreWrapper
//
//  Created by Yury Dymov on 4/2/22.
//

import CoreNFC
import Foundation

let libre2DumpMap = [
    0x000:  (40,  "Extended header"),
    0x028:  (32,  "Extended footer"),
    0x048:  (296, "Body right-rotated by 4"),
    0x170:  (24,  "FRAM header"),
    0x188:  (296, "FRAM body"),
    0x2b0:  (24,  "FRAM footer"),
    0x2c8:  (34,  "Keys"),
    0x2ea:  (10,  "MAC address"),
    0x26d8: (24,  "Table of enabled NFC commands")
]

class AbstractLibre2: AbstractLibre {
    
    override func update(fram: Data) {
        self.fram = fram
        encryptedFram = Data()
        if UInt16(fram[0...1]) != crc16(fram[2...23]) {
            encryptedFram = fram
            if fram.count >= 344 {
                if let decryptedFRAM = try? decryptFRAM(data: fram) {
                    self.fram = decryptedFRAM
                }
            }
        }
        parseFRAM()
    }


    private let libre2Secret: UInt16 = 0x1b6a
    
    private func getFramArg(block: Int) -> UInt16 {
        return UInt16(patchInfo[5], patchInfo[4]) ^ 0x44
    }

    private func decryptFRAM(data: Data) throws -> Data {
        var result = [UInt8]()

        for i in 0 ..< 43 {
            let input = prepareVariables(id: uid, x: UInt16(i), y: getFramArg(block: i))
            let blockKey = processCrypto(input: input)

            result.append(data[i * 8 + 0] ^ UInt8(truncatingIfNeeded: blockKey[0]))
            result.append(data[i * 8 + 1] ^ UInt8(truncatingIfNeeded: blockKey[0] >> 8))
            result.append(data[i * 8 + 2] ^ UInt8(truncatingIfNeeded: blockKey[1]))
            result.append(data[i * 8 + 3] ^ UInt8(truncatingIfNeeded: blockKey[1] >> 8))
            result.append(data[i * 8 + 4] ^ UInt8(truncatingIfNeeded: blockKey[2]))
            result.append(data[i * 8 + 5] ^ UInt8(truncatingIfNeeded: blockKey[2] >> 8))
            result.append(data[i * 8 + 6] ^ UInt8(truncatingIfNeeded: blockKey[3]))
            result.append(data[i * 8 + 7] ^ UInt8(truncatingIfNeeded: blockKey[3] >> 8))
        }
        return Data(result)
    }
    
    override var activationCommand: NFCCommand {
        return nfcCommand(.activate)
    }
    
    override func activate(tag: NFCISO15693Tag) async throws {
        try await super.activate(tag: tag)
        logger.info("NFC: \(type) should be activated and warming up")
    }
 
    override func nfcCommand(_ code: Subcommand, parameters: Data = Data(), secret: UInt16 = 0) -> NFCCommand {
        let secret = secret != 0 ? secret : libre2Secret

        var parameters = parameters
        if code.rawValue < 0x20 {
            parameters += usefulFunction(id: uid, x: UInt16(code.rawValue), y: secret)
        }
        
        return super.nfcCommand(code, parameters: parameters, secret: secret)
    }
    
    override func readBlocks(tag: NFCISO15693Tag, from start: Int, count blocks: Int, requesting: Int = 3) async throws -> (Int, Data) {
        guard securityGeneration >= 1 else {
            logger.error("readBlocks() B3 command not supported by \(type)")
            throw LibreError.commandNotSupported("B3")
        }

        return try await super.readBlocks(tag: tag, from: start, count: blocks, requesting: requesting)
    }
    
    private func usefulFunction(id: SensorUid, x: UInt16, y: UInt16) -> Data {
        let blockKey = processCrypto(input: prepareVariables(id: id, x: x, y: y))
        let low = blockKey[0]
        let high = blockKey[1]

        // https://github.com/ivalkou/LibreTools/issues/2: "XOR with inverted low/high words in usefulFunction()"
        let r1 = low ^ 0x4163
        let r2 = high ^ 0x4344

        return Data([
            UInt8(truncatingIfNeeded: r1),
            UInt8(truncatingIfNeeded: r1 >> 8),
            UInt8(truncatingIfNeeded: r2),
            UInt8(truncatingIfNeeded: r2 >> 8)
        ])
    }
}
