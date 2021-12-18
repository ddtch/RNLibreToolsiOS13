import Foundation
import AVFoundation    // AudioServicesPlaySystemSound()


import CoreNFC


// https://github.com/ivalkou/LibreTools/blob/master/Sources/LibreTools/NFC/NFCManager.swift

// https://fortinetweb.s3.amazonaws.com/fortiguard/research/techreport.pdf
// https://github.com/travisgoodspeed/goodtag/wiki/RF430TAL152H
// https://github.com/travisgoodspeed/GoodV/blob/master/app/src/main/java/com/kk4vcz/goodv/NfcRF430TAL.java
// https://github.com/cryptax/misc-code/blob/master/glucose-tools/readdump.py
// https://github.com/travisgoodspeed/goodtag/blob/master/firmware/gcmpatch.c
// https://github.com/captainbeeheart/openfreestyle/blob/master/docs/reverse.md

//@available(iOS 13.0, *)
//extension NFC {
//
//
//    func execute(_ taskRequest: TaskRequest) async throws {
//
//        switch taskRequest {
//
//
//        case .dump:
//
//
//        case .reset:
//
//
//        case .prolong:
//
//            if sensor.type != .libre1 {
//                print("FRAM overwriting not supported by \(sensor.type)")
//                throw NFCError.commandNotSupported
//            }
//
//            let (footerAddress, footerFram) = try await readRaw(0xF860 + 40 * 8, 3 * 8)
//
//            let maxLifeOffset = 6
//            let maxLife = Int(footerFram[maxLifeOffset]) + Int(footerFram[maxLifeOffset + 1]) << 8
//            print("\(sensor.type) current maximum life: \(maxLife) minutes (\(maxLife.formattedInterval))")
//
//            var patchedFram = Data(footerFram)
//            patchedFram[maxLifeOffset ... maxLifeOffset + 1] = Data([0xFF, 0xFF])
//            let patchedCRC = crc16(patchedFram[2 ..< 3 * 8])
//            patchedFram[0 ... 1] = patchedCRC.data
//
//            do {
//                try await writeRaw(footerAddress + maxLifeOffset, patchedFram[maxLifeOffset ... maxLifeOffset + 1])
//                try await writeRaw(footerAddress, patchedCRC.data)
//
//                let (_, data) = try await read(fromBlock: 0, count: 43)
//                print(Data(data.suffix(3 * 8)).hexDump(header: "NFC: did overwite FRAM footer:", startBlock: 40))
//                sensor.fram = Data(data)
//            } catch {
//
//                // TODO: manage errors and verify integrity
//
//            }
//
//
//        case .unlock:
//
//            if sensor.securityGeneration < 1 {
//                print("'A1 1A unlock' command not supported by \(sensor.type)")
//                throw NFCError.commandNotSupported
//            }
//
//            do {
//                let output = try await send(sensor.unlockCommand)
//
//                // Libre 2
//                if output.count == 0 {
//                    print("NFC: FRAM should have been decrypted in-place")
//                }
//
//            } catch {
//
//                // TODO: manage errors and verify integrity
//
//            }
//
//            let (_, data) = try await read(fromBlock: 0, count: 43)
//            sensor.fram = Data(data)
//
//
//        case .activate:
//
//            if sensor.securityGeneration > 1 {
//                print("Activating a \(sensor.type) is not supported")
//                throw NFCError.commandNotSupported
//            }
//
//            do {
////                if await sensor.main.settings.debugLevel > 0 {
////                    await sensor.testOOPActivation()
////                }
//
//
//                if sensor.type == .libreProH {
//                    var readCommand = sensor.readBlockCommand
//                    readCommand.parameters = "DF 04".bytes
//                    var output = try await send(readCommand)
//                    print("NFC: 'B0 read 0x04DF' command output: \(output.hex)")
//                    try await send(sensor.unlockCommand)
//                    var writeCommand = sensor.writeBlockCommand
//                    writeCommand.parameters = "DF 04 20 00 DF 88 00 00 00 00".bytes
//                    output = try await send(writeCommand)
//                    print("NFC: 'B1 write' command output: \(output.hex)")
//                    try await send(sensor.lockCommand)
//                    output = try await send(readCommand)
//                    print("NFC: 'B0 read 0x04DF' command output: \(output.hex)")
//                }
//
//                let output = try await send(sensor.activationCommand)
//                print("NFC: after trying to activate received \(output.hex) for the patch info \(sensor.patchInfo.hex)")
//
//                // Libre 2
//                if output.count == 4 {
//                    // receiving 9d081000 for a patchInfo 9d0830010000
//                    print("NFC: \(sensor.type) should be activated and warming up")
//                    main?.activateCompletion?(.success(true))
//                }
//
//            } catch {
//
//                // TODO: manage errors and verify integrity
//                main?.activateCompletion?(.failure(LibreError(errorCode: 100, errorMessage: "Can't activate device")))
//
//            }
//
//            let (_, data) = try await read(fromBlock: 0, count: 43)
//            sensor.fram = Data(data)
//
//
//        default:
//            break
//
//        }
//
//    }
//
//}
//
