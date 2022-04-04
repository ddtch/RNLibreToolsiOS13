//
//  Libre14Usd.swift
//  LibreWrapper
//
//  Created by Yury Dymov on 4/2/22.
//

import Foundation

final class Libre14US: AbstractLibre {
    
    override var type: SensorType {
        return .libreUS14day
    }
    
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
    
    private func getFramArg(block: Int) -> UInt16 {
        if block < 3 || block >= 40 {
            // For header and footer it is a fixed value.
            return 0xcadc
        }
        return UInt16(patchInfo[5], patchInfo[4])
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
}

