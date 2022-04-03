import Foundation
import CoreNFC

// 0x2580: (4, "Libre 1 backdoor")
// 0x25c5: (7, "BLE trend offsets")
// 0x25d0 + 1: (4 + 8, "usefulFunction() and streaming unlock keys")

// 0c8a  CMP.W  #0xadc2, &RF13MRXF
// 0c90  JEQ  0c96
// 0c92  MOV.B  #0, R12
// 0c94  RET
// 0c96  CMP.W  #0x2175, &RF13MRXF
// 0c9c  JNE  0c92
// 0c9e  MOV.B  #1, R12
// 0ca0  RET

// function at 24e2:
//    if (param_1 == '\x1e') {
//      param_3 = param_3 ^ param_4;
//    }
//    else {
//      param_3 = 0x1b6a;
//    }

// 0800: RF13MCTL
// 0802: RF13MINT
// 0804: RF13MIV
// 0806: RF13MRXF
// 0808: RF13MTXF
// 080a: RF13MCRC
// 080c: RF13MFIFOFL
// 080e: RF13MWMCFG


// https://github.com/ivalkou/LibreTools/blob/master/Sources/LibreTools/Sensor/Libre2.swift

class Libre2CA: AbstractLibre2 {
    
    override var type: SensorType {
        return .libre2CA
    }

    /*
    static func prepareVariables2(id: SensorUid, i1: UInt16, i2: UInt16, i3: UInt16, i4: UInt16) -> [UInt16] {
        let s1 = UInt16(truncatingIfNeeded: UInt(UInt16(id[5], id[4])) + UInt(i1))
        let s2 = UInt16(truncatingIfNeeded: UInt(UInt16(id[3], id[2])) + UInt(i2))
        let s3 = UInt16(truncatingIfNeeded: UInt(UInt16(id[1], id[0])) + UInt(i3) + UInt(key[2]))
        let s4 = UInt16(truncatingIfNeeded: UInt(i4) + UInt(key[3]))

        return [s1, s2, s3, s4]
    }


    static func streamingUnlockPayload(id: SensorUid, info: PatchInfo, enableTime: UInt32, unlockCount: UInt16) -> Data {

        // First 4 bytes are just int32 of timestamp + unlockCount
        let time = enableTime + UInt32(unlockCount)
        let b: [UInt8] = [
            UInt8(time & 0xFF),
            UInt8((time >> 8) & 0xFF),
            UInt8((time >> 16) & 0xFF),
            UInt8((time >> 24) & 0xFF)
        ]

        // Then we need data of activation command and enable command that were sent to sensor
        let ad = usefulFunction(id: id, x: UInt16(Sensor.Subcommand.activate.rawValue), y: secret)
        let ed = usefulFunction(id: id, x: UInt16(Sensor.Subcommand.enableStreaming.rawValue), y: UInt16(enableTime & 0xFFFF) ^ UInt16(info[5], info[4]))

        let t11 = UInt16(ed[1], ed[0]) ^ UInt16(b[3], b[2])
        let t12 = UInt16(ad[1], ad[0])
        let t13 = UInt16(ed[3], ed[2]) ^ UInt16(b[1], b[0])
        let t14 = UInt16(ad[3], ad[2])

        let t2 = processCrypto(input: prepareVariables2(id: id, i1: t11, i2: t12, i3: t13, i4: t14))

        // TODO extract if secret
        let t31 = crc16(Data([0xc1, 0xc4, 0xc3, 0xc0, 0xd4, 0xe1, 0xe7, 0xba, UInt8(t2[0] & 0xFF), UInt8((t2[0] >> 8) & 0xFF)]))
        let t32 = crc16(Data([UInt8(t2[1] & 0xFF), UInt8((t2[1] >> 8) & 0xFF),
                              UInt8(t2[2] & 0xFF), UInt8((t2[2] >> 8) & 0xFF),
                              UInt8(t2[3] & 0xFF), UInt8((t2[3] >> 8) & 0xFF)]))
        let t33 = crc16(Data([ad[0], ad[1], ad[2], ad[3], ed[0], ed[1]]))
        let t34 = crc16(Data([ed[2], ed[3], b[0], b[1], b[2], b[3]]))

        let t4 = processCrypto(input: prepareVariables2(id: id, i1: t31, i2: t32, i3: t33, i4: t34))

        let res = [
            UInt8(t4[0] & 0xFF),
            UInt8((t4[0] >> 8) & 0xFF),
            UInt8(t4[1] & 0xFF),
            UInt8((t4[1] >> 8) & 0xFF),
            UInt8(t4[2] & 0xFF),
            UInt8((t4[2] >> 8) & 0xFF),
            UInt8(t4[3] & 0xFF),
            UInt8((t4[3] >> 8) & 0xFF)
        ]

        return Data([b[0], b[1], b[2], b[3], res[0], res[1], res[2], res[3], res[4], res[5], res[6], res[7]])
    }


    /// Decrypts Libre 2 BLE payload
    /// - Parameters:
    ///   - id: ID/Serial of the sensor. Could be retrieved from NFC as uid.
    ///   - data: Encrypted BLE data
    /// - Returns: Decrypted BLE data
    static func decryptBLE(id: SensorUid, data: Data) throws -> Data {
        let d = usefulFunction(id: id, x: UInt16(Sensor.Subcommand.activate.rawValue), y: secret)
        let x = UInt16(d[1], d[0]) ^ UInt16(d[3], d[2]) | 0x63
        let y = UInt16(data[1], data[0]) ^ 0x63

        var key = [UInt8]()
        var initialKey = processCrypto(input: prepareVariables(id: id, x: x, y: y))

        for _ in 0 ..< 8 {
            key.append(UInt8(truncatingIfNeeded: initialKey[0]))
            key.append(UInt8(truncatingIfNeeded: initialKey[0] >> 8))
            key.append(UInt8(truncatingIfNeeded: initialKey[1]))
            key.append(UInt8(truncatingIfNeeded: initialKey[1] >> 8))
            key.append(UInt8(truncatingIfNeeded: initialKey[2]))
            key.append(UInt8(truncatingIfNeeded: initialKey[2] >> 8))
            key.append(UInt8(truncatingIfNeeded: initialKey[3]))
            key.append(UInt8(truncatingIfNeeded: initialKey[3] >> 8))
            initialKey = processCrypto(input: initialKey)
        }

        let result = data[2...].enumerated().map { i, value in
            value ^ key[i]
        }

        guard crc16(Data(result.prefix(42))) == UInt16(Data(result[42...43])) else {
            struct DecryptBLEError: LocalizedError {
                var errorDescription: String? { "BLE data decryption failed" }
            }
            throw DecryptBLEError()
        }

        return Data(result)
    }
     */

    override func isCrcReportFailed(_ crcReport: String) -> Bool {
        return false
    }
}
