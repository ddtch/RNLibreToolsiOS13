import Foundation
import Combine
import CoreNFC


// https://github.com/travisgoodspeed/goodtag/wiki/RF430TAL152H
// https://github.com/travisgoodspeed/GoodV/blob/master/app/src/main/java/com/kk4vcz/goodv/NfcRF430TAL.java
// https://github.com/travisgoodspeed/goodtag/blob/master/firmware/gcmpatch.c
//
// "The Inner Guts of a Connected Glucose Sensor for Diabetes"
// https://www.youtube.com/watch?v=Y9vtGmxh1IQ
// https://github.com/cryptax/talks/blob/master/BlackAlps-2019/glucose-blackalps2019.pdf
// https://github.com/cryptax/misc-code/blob/master/glucose-tools/readdump.py
//
// "NFC Exploitation with the RF430RFL152 and 'TAL152" in PoC||GTFO 0x20
// https://archive.org/stream/pocorgtfo20#page/n6/mode/1up


extension SensorType {
    var backdoor: String {
        switch self {
        case .libre1:    return "c2ad7521"
        // TODO: test eDroplet NFC A4 unlock command
        // case .libre2:    return "1b60b24b2a"
        // case .libreUS:   return "1b75ae93f0"
        // case .libreProH: return "c2ad0090"
        default:         return "deadbeef"
        }
    }
}


extension Sensor {
    static var freshFRAM: Data {
        var fram =  "50 37 B0 32 01 00 02 08 \n"
        for _ in 1...2 {
            fram += "00 00 00 00 00 00 00 00 \n"
        }
        fram +=     "62 c2 00 00 00 00 00 00 \n"
        for _ in 4 ... 0x27 {
            fram += "00 00 00 00 00 00 00 00 \n"
        }
        return Data(fram.bytes)
    }
}

enum TaskRequest {
    case enableStreaming
    case readFRAM
    case unlock
    case dump
    case reset
    case prolong
    case activate
}


class NFC: NSObject, NFCTagReaderSessionDelegate {

    var tagSession: NFCTagReaderSession?
    var connectedTag: NFCISO15693Tag?
    var sensor: Sensor!

    var main: RNLibreToolsiOS13!

    var isNFCAvailable: Bool {
        return NFCTagReaderSession.readingAvailable
    }

    var taskRequest: TaskRequest? {
        didSet {
            guard taskRequest != nil else { return }
            startSession()
        }
    }

    func startSession() {
        // execute in the .main queue because of publishing changes to main's observables
        tagSession = NFCTagReaderSession(pollingOption: [.iso15693], delegate: self, queue: .main)
        tagSession?.alertMessage = "Hold the top of your iPhone near the Libre sensor"
        tagSession?.begin()
    }

    public func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
//        main.log("NFC: session did become active")
    }

    public func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        if let readerError = error as? NFCReaderError {
            if readerError.code != .readerSessionInvalidationErrorUserCanceled {
                print("NFC: \(readerError.localizedDescription)")
                session.invalidate(errorMessage: "Connection failure: \(readerError.localizedDescription)")
            }
        }
    }

    public func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        print("NFC: did detect tags")

        sensor = Sensor()

        guard let firstTag = tags.first else { return }
        guard case .iso15693(let tag) = firstTag else { return }

        session.alertMessage = "Scan complete"

        let blocks = sensor.type != .libreProH ? 43 : 22 + 24    // (32 * 6 / 8)
        let requestBlocks = 3

        let requests = Int(ceil(Double(blocks) / Double(requestBlocks)))
        let remainder = blocks % requestBlocks
        var dataArray = [Data](repeating: Data(), count: blocks)

        session.connect(to: firstTag) { error in
            if error != nil {
                self.main.sessionCompletionWithTrend?(.failure(LibreError(errorCode: 0, errorMessage: "NFC Error: \(error!.localizedDescription)")))
                session.invalidate(errorMessage: "Connection failure: \(error!.localizedDescription)")
                return
            }
            self.connectedTag = tag
            print("we are connected")

            // https://www.st.com/en/embedded-software/stsw-st25ios001.html#get-software

            self.connectedTag?.getSystemInfo(requestFlags: [.address, .highDataRate]) { (dfsid: Int, afi: Int, blockSize: Int, memorySize: Int, icRef: Int, error: Error?) in
                if error != nil {
                    session.invalidate(errorMessage: "Error while getting system info: " + error!.localizedDescription)
                    self.main.sessionCompletionWithTrend?(.failure(LibreError(errorCode: 0, errorMessage: "NFC Error: \(error!.localizedDescription)")))
                    return
                }

                self.connectedTag?.customCommand(requestFlags: [.highDataRate], customCommandCode: 0xA1, customRequestParameters: Data()) { (customResponse: Data, error: Error?) in
                    if error != nil {
                         session.invalidate(errorMessage: "Error while getting patch info: " + error!.localizedDescription)
                        self.main.sessionCompletionWithTrend?(.failure(LibreError(errorCode: 0, errorMessage: "NFC Error: \(error!.localizedDescription)")))
                    }

                    guard self.taskRequest != .activate else {
                        self.connectedTag?.activate(completion: { result in
                            switch result {
                            case .success(_):
                                self.main.activateCompletion?(.success([["activated": true]]))
                                session.invalidate()
                            case .failure(let error):
                                self.main.activateCompletion?(.failure(error))
                                session.invalidate()
                            }
                        })
                        return
                    }

                    guard self.taskRequest != .readFRAM else {
                        self.connectedTag?.readFram(completion: { result in
                            switch result {
                            case .success(_):
                                self.main.sensorInfoCompletion?(.success([result]))
                                session.invalidate()
                            case .failure(let error):
                                self.main.sensorInfoCompletion?(.failure(error))
                                session.invalidate()
                            }
                        })
                        return
                    }


                    for i in 0 ..< requests {

                        self.connectedTag?.readMultipleBlocks(requestFlags: [.highDataRate, .address], blockRange: NSRange(UInt8(i * requestBlocks)...UInt8(i * requestBlocks + (i == requests - 1 ? (remainder == 0 ? requestBlocks : remainder) : requestBlocks) - (requestBlocks > 1 ? 1 : 0)))) { (blockArray, error) in

                            if error != nil {
                                self.main.sessionCompletionWithTrend?(.failure(LibreError(errorCode: 0, errorMessage: "NFC Error: \(error!.localizedDescription)")))
                                session.invalidate(errorMessage: "Error while reading multiple blocks: \(error!.localizedDescription)")
                                if i != requests - 1 { return }

                            } else {
                                for j in 0 ..< blockArray.count {
                                    dataArray[i * requestBlocks + j] = blockArray[j]
                                }
                            }


                            if i == requests - 1 {
                                    var fram = Data()

                                self.sensor.lastReadingDate = Date()

                                var msg = ""
                                for (n, data) in dataArray.enumerated() {
                                    if data.count > 0 {
                                        fram.append(data)
                                        msg += "NFC: block #\(String(format:"%02d", n))  \(data.reduce("", { $0 + String(format: "%02X", $1) + " "}).dropLast())\n"
                                    }
                                }
                                var manufacturer = String(tag.icManufacturerCode)
                                if manufacturer == "7" {
                                    manufacturer.append(" (Texas Instruments)")
                                }

                                var rom = "RF430"
                                switch self.connectedTag?.identifier[2] {
                                case 0xA0: rom += "TAL152H Libre 1 A0"
                                case 0xA4: rom += "TAL160H Libre 2 A4"
                                default:   rom += " unknown"
                                }

                                self.sensor.uid = Data(tag.identifier.reversed())

                                let patchInfo = customResponse
                                self.sensor.patchInfo = Data(patchInfo)
                                if fram.count > 0 {
                                    self.sensor.fram = Data(fram)
                                }

                                self.main.parseSensorData(self.sensor)
                                session.invalidate()
                            }
                        }
                    }
                }
            }
        }
    }


    // TODO: test
    /// fram:   0xF860, 2048
    /// rom:    0x4400, 0x2000
    /// sram:   0x1C00, 0x1000
    /// config: 0x1A00, 64    (serial number and calibration)

    func readRaw(_ address: UInt16, _ bytes: Int, buffer: Data = Data(), handler: @escaping (UInt16, Data, Error?) -> Void) {

        var buffer = buffer
        let addressToRead = address + UInt16(buffer.count)

        var remainingBytes = bytes
        let bytesToRead = remainingBytes > 24 ? 24 : bytes

        var remainingWords = bytes / 2
        if bytes % 2 == 1 || ( bytes % 2 == 0 && addressToRead % 2 == 1 ) { remainingWords += 1 }
        let wordsToRead = UInt8(remainingWords > 12 ? 12 : remainingWords)    // real limit is 15

//        if buffer.count == 0 { self.main.debugLog("NFC: sending 0xa3\(sensor.type.backdoor) command (\(sensor.type) read raw)") }

        self.connectedTag?.customCommand(requestFlags: [.highDataRate], customCommandCode: 0xA3, customRequestParameters: Data(self.sensor.type.backdoor.bytes + [UInt8(addressToRead & 0x00FF), UInt8(addressToRead >> 8), wordsToRead])) { (customResponse: Data, error: Error?) in

            var data = customResponse

            if error != nil {
//                self.main.debugLog("NFC: error while reading \(wordsToRead) words at raw memory 0x\(String(format: "%04X", addressToRead))")
                remainingBytes = 0
            } else {
                if addressToRead % 2 == 1 { data = data.subdata(in: 1 ..< data.count) }
                if data.count - Int(bytesToRead) == 1 { data = data.subdata(in: 0 ..< data.count - 1) }
            }

            buffer += data
            remainingBytes -= data.count

            if remainingBytes == 0 {
                handler(address, buffer, error)
            } else {
                self.readRaw(address, remainingBytes, buffer: buffer) { address, data, error in handler(address, data, error) }
            }
        }
    }


    func writeRaw(_ address: UInt16, _ data: Data, handler: @escaping (UInt16, Data, Error?) -> Void) {

        // Unlock
        print("NFC: sending 0xa4\(sensor.type.backdoor) command (\(sensor.type) unlock)")
        self.connectedTag?.customCommand(requestFlags: [.highDataRate], customCommandCode: 0xA4, customRequestParameters: Data(self.sensor.type.backdoor.bytes)) { (customResponse: Data, error: Error?) in
            print("NFC: unlock command response: 0x\(customResponse.hex), error: \(error?.localizedDescription ?? "none")")

            let addressToRead = (address / 8) * 8
            let startOffset = Int(address % 8)
            let endAddressToRead = ((Int(address) + data.count - 1) / 8) * 8 + 7
            let blocksToRead = (endAddressToRead - Int(addressToRead)) / 8 + 1
            self.readRaw(addressToRead, blocksToRead * 8) { readAddress, readData, error in
                var msg = error?.localizedDescription ?? readData.hexDump(header: "NFC: blocks to overwrite:", address: Int(readAddress))
                if error != nil {
                    handler(address, data, error)
                    return
                }
                var bytesToWrite = readData
                bytesToWrite.replaceSubrange(startOffset ..< startOffset + data.count, with: data)
                msg += "\(bytesToWrite.hexDump(header: "\nwith blocks:", address: Int(addressToRead)))"
                print(msg)
                let startBlock = Int(addressToRead / 8)
                let blocks = bytesToWrite.count / 8

                if startBlock > 255 {

                    for i in 0 ..< blocks {

                        let blockToWrite = bytesToWrite[i * 8 ... i * 8 + 7]

                        // FIXME: doesn't work as the custom commands C1 or A5 for other chips
                        self.connectedTag?.extendedWriteSingleBlock(requestFlags: [.highDataRate], blockNumber: startBlock + i, dataBlock: blockToWrite) { error in

                            if error != nil {
                                print("NFC: error while writing block 0x\(String(format: "%X", startBlock + i)) (\(i + 1) of \(blocks)) \(blockToWrite.hex) at 0x\(String(format: "%X", (startBlock + i) * 8)): \(error!.localizedDescription)")
                                if i != blocks - 1 { return }

                            } else {
                                print("NFC: wrote block 0x\(String(format: "%X", startBlock + i)) (\(i + 1) of \(blocks)) \(blockToWrite.hex) at 0x\(String(format: "%X", (startBlock + i) * 8))")
                            }

                            if i == blocks - 1 {

                                // Lock
                                self.connectedTag?.customCommand(requestFlags: [.highDataRate], customCommandCode: 0xA2, customRequestParameters: Data(self.sensor.type.backdoor.bytes)) { (customResponse: Data, error: Error?) in
                                    handler(address, data, error)
                                }

                            }
                        }
                    }

                } else { // startBlock < 256: write to FRAM instead to real 0x0000

                    let requestBlocks = 2 // 3 doesn't work

                    let requests = Int(ceil(Double(blocks) / Double(requestBlocks)))
                    let remainder = blocks % requestBlocks
                    var blocksToWrite = [Data](repeating: Data(), count: blocks)

                    for i in 0 ..< blocks {
                        blocksToWrite[i] = Data(bytesToWrite[i * 8 ... i * 8 + 7])
                    }

                    for i in 0 ..< requests {

                        let startIndex = startBlock + i * requestBlocks
                        let endIndex = startIndex + (i == requests - 1 ? (remainder == 0 ? requestBlocks : remainder) : requestBlocks) - (requestBlocks > 1 ? 1 : 0)
                        let blockRange = NSRange(UInt8(startIndex) ... UInt8(endIndex))

                        var dataBlocks = [Data]()
                        for j in startIndex ... endIndex { dataBlocks.append(blocksToWrite[j]) }

                        // TODO: write to 16-bit addresses as the custom cummand C4 for other chips
                        self.connectedTag?.writeMultipleBlocks(requestFlags: [.highDataRate, .address], blockRange: blockRange, dataBlocks: dataBlocks) { error in // TEST

                            if error != nil {
                                print("NFC: error while writing multiple blocks 0x\(String(format: "%X", startIndex)) - 0x\(String(format: "%X", endIndex))) \(dataBlocks.reduce("", { $0 + $1.hex })) at 0x\(String(format: "%X", (startBlock + i * requestBlocks) * 8)): \(error!.localizedDescription)")
                                if i != requests - 1 { return }

                            } else {
                                print("NFC: wrote blocks 0x\(String(format: "%X", startIndex)) - 0x\(String(format: "%X", endIndex))) \(dataBlocks.reduce("", { $0 + $1.hex })) at 0x\(String(format: "%X", (startBlock + i * requestBlocks) * 8))")
                            }

                            if i == requests - 1 {

                                // Lock
                                self.connectedTag?.customCommand(requestFlags: [.highDataRate], customCommandCode: 0xA2, customRequestParameters: Data(self.sensor.type.backdoor.bytes)) { (customResponse: Data, error: Error?) in
                                    print("NFC: lock command response: 0x\(customResponse.hex), error: \(error?.localizedDescription ?? "none")")
                                    handler(address, data, error)
                                }
                            }
                        } // TEST writeMultipleBlocks
                    }
                }
            }
        }
    }
}

struct CustomCommand {
    let code: Int
    let parameters = Data([0xc2, 0xad, 0x75, 0x21])
    let description = ""

    static let activate = CustomCommand(code: 0xA0)
    static let getPatchInfo = CustomCommand(code: 0xA1)
    static let lock = CustomCommand(code: 0xA2)
    static let rawRead = CustomCommand(code: 0xA3)
    static let libre2Universal = CustomCommand(code: 0xA1)
    static let readFram = CustomCommand(code: 0x1F)
}

fileprivate extension NFCISO15693Tag {
    func runCommand(_ cmd: CustomCommand, completion: @escaping (Result<Bool, LibreError>)-> Void) {
        self.customCommand(requestFlags: .highDataRate, customCommandCode: cmd.code, customRequestParameters: cmd.parameters) { data, error in
            guard error == nil else {
                completion(.failure(LibreError(errorCode: 3, errorMessage: error!.localizedDescription)))
                return
            }
            completion(.success(true))
        }
    }

    func activate(completion: @escaping (Result<Bool, LibreError>)-> Void) {
        runCommand(.activate, completion: completion)
    }

    func readFram(completion: @escaping (Result<Bool, LibreError>)-> Void) {
        // tst
        sensor.extractFram()
        runCommand(.readFram, completion: completion)
    }
}
