import AVFoundation
import Foundation
import CoreBluetooth
import CoreNFC

// https://github.com/UPetersen/LibreMonitor/blob/Swift4/LibreMonitor/Model/CRC.swift
@available(iOS 13.0, *)
func crc16(_ data: Data) -> UInt16 {
    let crc16table: [UInt16] = [0, 4489, 8978, 12955, 17956, 22445, 25910, 29887, 35912, 40385, 44890, 48851, 51820, 56293, 59774, 63735, 4225, 264, 13203, 8730, 22181, 18220, 30135, 25662, 40137, 36160, 49115, 44626, 56045, 52068, 63999, 59510, 8450, 12427, 528, 5017, 26406, 30383, 17460, 21949, 44362, 48323, 36440, 40913, 60270, 64231, 51324, 55797, 12675, 8202, 4753, 792, 30631, 26158, 21685, 17724, 48587, 44098, 40665, 36688, 64495, 60006, 55549, 51572, 16900, 21389, 24854, 28831, 1056, 5545, 10034, 14011, 52812, 57285, 60766, 64727, 34920, 39393, 43898, 47859, 21125, 17164, 29079, 24606, 5281, 1320, 14259, 9786, 57037, 53060, 64991, 60502, 39145, 35168, 48123, 43634, 25350, 29327, 16404, 20893, 9506, 13483, 1584, 6073, 61262, 65223, 52316, 56789, 43370, 47331, 35448, 39921, 29575, 25102, 20629, 16668, 13731, 9258, 5809, 1848, 65487, 60998, 56541, 52564, 47595, 43106, 39673, 35696, 33800, 38273, 42778, 46739, 49708, 54181, 57662, 61623, 2112, 6601, 11090, 15067, 20068, 24557, 28022, 31999, 38025, 34048, 47003, 42514, 53933, 49956, 61887, 57398, 6337, 2376, 15315, 10842, 24293, 20332, 32247, 27774, 42250, 46211, 34328, 38801, 58158, 62119, 49212, 53685, 10562, 14539, 2640, 7129, 28518, 32495, 19572, 24061, 46475, 41986, 38553, 34576, 62383, 57894, 53437, 49460, 14787, 10314, 6865, 2904, 32743, 28270, 23797, 19836, 50700, 55173, 58654, 62615, 32808, 37281, 41786, 45747, 19012, 23501, 26966, 30943, 3168, 7657, 12146, 16123, 54925, 50948, 62879, 58390, 37033, 33056, 46011, 41522, 23237, 19276, 31191, 26718, 7393, 3432, 16371, 11898, 59150, 63111, 50204, 54677, 41258, 45219, 33336, 37809, 27462, 31439, 18516, 23005, 11618, 15595, 3696, 8185, 63375, 58886, 54429, 50452, 45483, 40994, 37561, 33584, 31687, 27214, 22741, 18780, 15843, 11370, 7921, 3960]
    var crc = data.reduce(UInt16(0xFFFF)) { ($0 >> 8) ^ crc16table[Int(($0 ^ UInt16($1)) & 0xFF)] }
    var reverseCrc = UInt16(0)
    for _ in 0 ..< 16 {
        reverseCrc = reverseCrc << 1 | crc & 1
        crc >>= 1
    }
    return reverseCrc
}


// https://github.com/dabear/LibreTransmitter/blob/main/LibreSensor/SensorContents/SensorData.swift
@available(iOS 13.0, *)
func readBits(_ buffer: Data, _ byteOffset: Int, _ bitOffset: Int, _ bitCount: Int) -> Int {
    guard bitCount != 0 else {
        return 0
    }
    var res = 0
    for i in 0 ..< bitCount {
        let totalBitOffset = byteOffset * 8 + bitOffset + i
        let byte = Int(floor(Float(totalBitOffset) / 8))
        let bit = totalBitOffset % 8
        if totalBitOffset >= 0 && ((buffer[byte] >> bit) & 0x1) == 1 {
            res |= 1 << i
        }
    }
    return res
}
@available(iOS 13.0, *)
func writeBits(_ buffer: Data, _ byteOffset: Int, _ bitOffset: Int, _ bitCount: Int, _ value: Int) -> Data {
    var res = buffer
    for i in 0 ..< bitCount {
        let totalBitOffset = byteOffset * 8 + bitOffset + i
        let byte = Int(floor(Double(totalBitOffset) / 8))
        let bit = totalBitOffset % 8
        let bitValue = (value >> i) & 0x1
        res[byte] = (res[byte] & ~(1 << bit) | (UInt8(bitValue) << bit))
    }
    return res
}

@available(iOS 13.0, *)
struct CalibrationInfo: Codable, Equatable {
    var i1: Int = 0
    var i2: Int = 0
    var i3: Int = 0
    var i4: Int = 0
    var i5: Int = 0
    var i6: Int = 0

    static var empty = CalibrationInfo()
}

@available(iOS 13.0, *)
class AbstractLibre: ObservableObject, Sensor {

    let logger: Logging

    open var type: SensorType {
        return .unknown
    }
    
    let family: SensorFamily
    
    var region: SensorRegion
    
    var readerSerial = Data()
    
    var serial: String {
        let lookupTable = ["0","1","2","3","4","5","6","7","8","9","A","C","D","E","F","G","H","J","K","L","M","N","P","Q","R","T","U","V","W","X","Y","Z"]
        guard uid.count == 8 else { return "" }
        let bytes = Array(uid.reversed().suffix(6))
        var fiveBitsArray = [UInt8]()
        fiveBitsArray.append( bytes[0] >> 3 )
        fiveBitsArray.append( bytes[0] << 2 + bytes[1] >> 6 )
        fiveBitsArray.append( bytes[1] >> 1 )
        fiveBitsArray.append( bytes[1] << 4 + bytes[2] >> 4 )
        fiveBitsArray.append( bytes[2] << 1 + bytes[3] >> 7 )
        fiveBitsArray.append( bytes[3] >> 2 )
        fiveBitsArray.append( bytes[3] << 3 + bytes[4] >> 5 )
        fiveBitsArray.append( bytes[4] )
        fiveBitsArray.append( bytes[5] >> 3 )
        fiveBitsArray.append( bytes[5] << 2 )
        return fiveBitsArray.reduce("\(family.rawValue)", {
            $0 + lookupTable[ Int(0x1F & $1) ]
        })
    }
    
    let debugLevel: Int

    @Published var state: SensorState = .unknown
    @Published var lastReadingDate = Date.distantPast
    @Published var age: Int = 0
    @Published var maxLife: Int = 0
    @Published var initializations: Int = 0

    var crcReport: String = ""
    open var key: [UInt16] = [0xA0C5, 0x6860, 0x0000, 0x14C6]

    private(set) var securityGeneration: Int = 0
    
    open var framBlocksToRead: Int {
        return 43
    }
    
    let patchInfo: PatchInfo

    open var activationCommand: NFCCommand {
        return NFCCommand(code: 0x00)
    }

    init(tag: NFCISO15693Tag, systemInfo: NFCISO15693SystemInfo, patchInfo: PatchInfo, toolbox: LibreToolbox) {
        self.patchInfo = patchInfo
        self.logger = toolbox.logger
        self.debugLevel = toolbox.debugLevel
        
        if patchInfo.count > 3 {
            region = SensorRegion(rawValue: Int(patchInfo[3])) ?? .unknown
        } else {
            region = .unknown
        }
        
        if patchInfo.count >= 6 {
            family = SensorFamily(rawValue: Int(patchInfo[2] >> 4)) ?? .libre
            let generation = patchInfo[2] & 0x0F
            if family == .libre2 {
                securityGeneration = generation < 9 ? 1 : 2
            }
            if family == .libreSense {
                securityGeneration = generation < 4 ? 1 : 2
            }
        } else {
            family = .libre
        }
        
        var manufacturer = tag.icManufacturerCode.hex
        if manufacturer == "07" {
            manufacturer.append(" (Texas Instruments)")
        } else if manufacturer == "7a" {
            manufacturer.append(" (Abbott Diabetes Care)")
            securityGeneration = 3 // TODO
        }
        logger.info("NFC: IC manufacturer code: 0x\(manufacturer)")
        logger.info("NFC: IC serial number: \(tag.icSerialNumber.hex)")

        var firmware = "RF430"
        switch tag.identifier[2] {
        case 0xA0: firmware += "TAL152H Libre 1 A0 "
        case 0xA4: firmware += "TAL160H Libre 2/Pro A4 "
        case 0x00: firmware = "unknown Libre 3 "
        default:   firmware += " unknown "
        }
        logger.info("NFC: \(firmware)firmware")

        logger.info(String(format: "NFC: IC reference: 0x%X", systemInfo.icReference))
        if systemInfo.applicationFamilyIdentifier != -1 {
            logger.info(String(format: "NFC: application family id (AFI): %d", systemInfo.applicationFamilyIdentifier))
        }
        if systemInfo.dataStorageFormatIdentifier != -1 {
            logger.info(String(format: "NFC: data storage format id: %d", systemInfo.dataStorageFormatIdentifier))
        }

        logger.info(String(format: "NFC: memory size: %d blocks", systemInfo.totalBlocks))
        logger.info(String(format: "NFC: block size: %d", systemInfo.blockSize))

        uid = Data(tag.identifier.reversed())
        logger.info("NFC: sensor uid: \(uid.hex)")
    }

    let uid: SensorUid

    var trend: [Glucose] = []
    var history: [Glucose] = []

    var calibrationInfo = CalibrationInfo()

    var factoryTrend: [Glucose] { trend.map { factoryGlucose(rawGlucose: $0, calibrationInfo: calibrationInfo) }}
    var factoryHistory: [Glucose] { history.map { factoryGlucose(rawGlucose: $0, calibrationInfo: calibrationInfo) }}

    var fram = Data()
    var encryptedFram: Data = Data()

    // Libre 2 and BLE streaming parameters
    @Published var initialPatchInfo: PatchInfo = Data()
    var streamingUnlockCode: UInt32 = 42
    @Published var streamingUnlockCount: UInt16 = 0
    
    // Gen2
    var streamingAuthenticationData: Data = Data(count: 10)    // formed when passed as third inout argument to verifyEnableStreamingResponse()
    
    open func update(fram: Data) {
        self.fram = fram
        encryptedFram = Data()
        parseFRAM()
    }

    open func scanHistory(tag: NFCISO15693Tag) async throws {}
    
    open func activate(tag: NFCISO15693Tag) async throws {
        let output = try await send(activationCommand, tag: tag)
        logger.info("NFC: after trying to activate received \(output.hex) for the patch info \(patchInfo.hex)")
    }

    @discardableResult
    func send(_ cmd: NFCCommand, tag: NFCISO15693Tag) async throws -> Data {
         var data = Data()
         do {
             logger.info("NFC: sending \(type) '\(cmd.code.hex)\(cmd.parameters.count == 0 ? "" : " \(cmd.parameters.hex)")' custom command\(cmd.description == "" ? "" : " (\(cmd.description))")")
             let output = try await tag.customCommand(requestFlags: .highDataRate, customCommandCode: cmd.code, customRequestParameters: cmd.parameters)
             data = Data(output)
         } catch {
             logger.info("NFC: \(type) '\(cmd.description) \(cmd.code.hex)\(cmd.parameters.count == 0 ? "" : " \(cmd.parameters.hex)")' custom command error: \(error.localizedDescription) (ISO 15693 error 0x\(error.iso15693Code.hex): \(error.iso15693Description))")
             throw error
         }
         return data
     }

    func read(tag: NFCISO15693Tag, fromBlock start: Int, count blocks: Int, requesting: Int = 3, retries: Int = 5) async throws -> (Int, Data) {
        var buffer = Data()

        var remaining = blocks
        var requested = requesting
        var retry = 0

        while remaining > 0 && retry <= retries {
            let blockToRead = start + buffer.count / 8

            do {
                let dataArray = try await tag.readMultipleBlocks(requestFlags: .highDataRate, blockRange: NSRange(blockToRead ... blockToRead + requested - 1))

                for data in dataArray {
                    buffer += data
                }

                remaining -= requested

                if remaining != 0 && remaining < requested {
                    requested = remaining
                }
            } catch {
                logger.error("NFC: error while reading multiple blocks #\(blockToRead.hex) - #\((blockToRead + requested - 1).hex) (\(blockToRead)-\(blockToRead + requested - 1)): \(error.localizedDescription) (ISO 15693 error 0x\(error.iso15693Code.hex): \(error.iso15693Description))")
                retry += 1
                if retry <= retries {
                    AudioServicesPlaySystemSound(1520)    // "pop" vibration
                    logger.info("NFC: retry # \(retry)...")
                    try await Task.sleep(nanoseconds: 250_000_000)
                } else {
                    throw LibreError.readFailure(error.localizedDescription)
                }
            }
        }

        return (start, buffer)
    }


    open func readBlocks(tag: NFCISO15693Tag, from start: Int, count blocks: Int, requesting: Int = 3) async throws -> (Int, Data) {
        var buffer = Data()

        var remaining = blocks
        var requested = requesting

        while remaining > 0 {

            let blockToRead = start + buffer.count / 8

            var readCommand = NFCCommand(code: 0xB3, parameters: Data([UInt8(blockToRead & 0xFF), UInt8(blockToRead >> 8), UInt8(requested - 1)]))
            if requested == 1 {
                readCommand = NFCCommand(code: 0xB0, parameters: Data([UInt8(blockToRead & 0xFF), UInt8(blockToRead >> 8)]))
            }

            // FIXME: the Libre 3 replies to 'A1 21' with the error code C1
            if securityGeneration > 1 {
                if blockToRead <= 255 {
                    readCommand = nfcCommand(.readBlocks, parameters: Data([UInt8(blockToRead), UInt8(requested - 1)]))
                }
            }

            if buffer.count == 0 {
                logger.info("NFC: sending '\(readCommand.code.hex) \(readCommand.parameters.hex)' custom command (\(type) read blocks)")
            }

            do {
                let output = try await tag.customCommand(requestFlags: .highDataRate, customCommandCode: readCommand.code, customRequestParameters: readCommand.parameters)
                let data = Data(output)

                if securityGeneration < 2 {
                    buffer += data
                } else {
                    logger.info("'\(readCommand.code.hex) \(readCommand.parameters.hex) \(readCommand.description)' command output (\(data.count) bytes): 0x\(data.hex)")
                    buffer += data.suffix(data.count - 8)    // skip leading 0xA5 dummy bytes
                }
                remaining -= requested

                if remaining != 0 && remaining < requested {
                    requested = remaining
                }

            } catch {
                logger.error(buffer.hexDump(header: "\(securityGeneration > 1 ? "`A1 21`" : "B0/B3") command output (\(buffer.count/8) blocks):", startBlock: start))

                if requested == 1 {
                    logger.error("NFC: error while reading block #\(blockToRead.hex): \(error.localizedDescription) (ISO 15693 error 0x\(error.iso15693Code.hex): \(error.iso15693Description))")
                } else {
                    logger.error("NFC: error while reading multiple blocks #\(blockToRead.hex) - #\((blockToRead + requested - 1).hex) (\(blockToRead)-\(blockToRead + requested - 1)): \(error.localizedDescription) (ISO 15693 error 0x\(error.iso15693Code.hex): \(error.iso15693Description))")
                }
                throw LibreError.readFailure("readBlock failed")
            }
        }

        return (start, buffer)
    }
    
    func prepareVariables(id: SensorUid, x: UInt16, y: UInt16) -> [UInt16] {
        let s1 = UInt16(truncatingIfNeeded: UInt(UInt16(id[5], id[4])) + UInt(x) + UInt(y))
        let s2 = UInt16(truncatingIfNeeded: UInt(UInt16(id[3], id[2])) + UInt(key[2]))
        let s3 = UInt16(truncatingIfNeeded: UInt(UInt16(id[1], id[0])) + UInt(x) * 2)
        let s4 = 0x241a ^ key[3]

        return [s1, s2, s3, s4]
    }
    
    func processCrypto(input: [UInt16]) -> [UInt16] {
        func op(_ value: UInt16) -> UInt16 {
            // We check for last 2 bits and do the xor with specific value if bit is 1
            var res = value >> 2 // Result does not include these last 2 bits

            if value & 1 != 0 { // If last bit is 1
                res = res ^ key[1]
            }

            if value & 2 != 0 { // If second last bit is 1
                res = res ^ key[0]
            }

            return res
        }

        let r0 = op(input[0]) ^ input[3]
        let r1 = op(r0) ^ input[2]
        let r2 = op(r1) ^ input[1]
        let r3 = op(r2) ^ input[0]
        let r4 = op(r3)
        let r5 = op(r4 ^ r0)
        let r6 = op(r5 ^ r1)
        let r7 = op(r6 ^ r2)

        let f1 = r0 ^ r4
        let f2 = r1 ^ r5
        let f3 = r2 ^ r6
        let f4 = r3 ^ r7

        return [f4, f3, f2, f1]
    }
    
    @discardableResult
    func readFram(tag: NFCISO15693Tag) async throws -> Data {
        let blocks = framBlocksToRead
        let (start, data) = try await securityGeneration < 2 ?
        read(tag: tag, fromBlock: 0, count: blocks) : readBlocks(tag: tag, from: 0, count: blocks)
        lastReadingDate = Date()
        update(fram: Data(data))
        logger.info(data.hexDump(header: "NFC: did read \(data.count / 8) FRAM blocks:", startBlock: start))
        return fram
    }

    open func parseFRAM() {
        updateCRCReport()
        guard !crcReport.contains("FAILED") else {
            state = .unknown
            return
        }

        if fram.count < 344 && encryptedFram.count > 0 { return }

        if let sensorState = SensorState(rawValue: fram[4]) {
            state = sensorState
        }

        guard fram.count >= 320 else { return }

        age = Int(fram[316]) + Int(fram[317]) << 8    // body[-4]
        let startDate = lastReadingDate - Double(age) * 60
        initializations = Int(fram[318])

        trend = []
        history = []
        let trendIndex = Int(fram[26])      // body[2]
        let historyIndex = Int(fram[27])    // body[3]

        for i in 0 ... 15 {
            var j = trendIndex - 1 - i
            if j < 0 { j += 16 }
            let offset = 28 + j * 6         // body[4 ..< 100]
            let rawValue = readBits(fram, offset, 0, 0xe)
            let quality = UInt16(readBits(fram, offset, 0xe, 0xb)) & 0x1FF
            let qualityFlags = (readBits(fram, offset, 0xe, 0xb) & 0x600) >> 9
            let hasError = readBits(fram, offset, 0x19, 0x1) != 0
            let rawTemperature = readBits(fram, offset, 0x1a, 0xc) << 2
            var temperatureAdjustment = readBits(fram, offset, 0x26, 0x9) << 2
            let negativeAdjustment = readBits(fram, offset, 0x2f, 0x1)
            if negativeAdjustment != 0 { temperatureAdjustment = -temperatureAdjustment }
            let id = age - i
            let date = startDate + Double(age - i) * 60
            trend.append(Glucose(rawValue: rawValue, rawTemperature: rawTemperature, temperatureAdjustment: temperatureAdjustment, id: id, date: date, hasError: hasError, dataQuality: Glucose.DataQuality(rawValue: Int(quality)), dataQualityFlags: qualityFlags))
        }

        // FRAM is updated with a 3 minutes delay:
        // https://github.com/UPetersen/LibreMonitor/blob/Swift4/LibreMonitor/Model/SensorData.swift

        let preciseHistoryIndex = ((age - 3) / 15 ) % 32
        let delay = (age - 3) % 15 + 3
        var readingDate = lastReadingDate
        if preciseHistoryIndex == historyIndex {
            readingDate.addTimeInterval(60.0 * -Double(delay))
        } else {
            readingDate.addTimeInterval(60.0 * -Double(delay - 15))
        }

        for i in 0 ... 31 {
            var j = historyIndex - 1 - i
            if j < 0 { j += 32 }
            let offset = 124 + j * 6    // body[100 ..< 292]
            let rawValue = readBits(fram, offset, 0, 0xe)
            let quality = UInt16(readBits(fram, offset, 0xe, 0xb)) & 0x1FF
            let qualityFlags = (readBits(fram, offset, 0xe, 0xb) & 0x600) >> 9
            let hasError = readBits(fram, offset, 0x19, 0x1) != 0
            let rawTemperature = readBits(fram, offset, 0x1a, 0xc) << 2
            var temperatureAdjustment = readBits(fram, offset, 0x26, 0x9) << 2
            let negativeAdjustment = readBits(fram, offset, 0x2f, 0x1)
            if negativeAdjustment != 0 { temperatureAdjustment = -temperatureAdjustment }
            let id = age - delay - i * 15
            let date = id > -1 ? readingDate - Double(i) * 15 * 60 : startDate
            history.append(Glucose(rawValue: rawValue, rawTemperature: rawTemperature, temperatureAdjustment: temperatureAdjustment, id: id, date: date, hasError: hasError, dataQuality: Glucose.DataQuality(rawValue: Int(quality)), dataQualityFlags: qualityFlags))
        }

        guard fram.count >= 344 else { return }

        // fram[322...323] (footer[2..3]) corresponds to patchInfo[2...3]
        region = SensorRegion(rawValue: Int(fram[323])) ?? .unknown
        maxLife = Int(fram[326]) + Int(fram[327]) << 8
//        DispatchQueue.main.async {
//            self.main?.settings.activeSensorMaxLife = self.maxLife
//        }

        let i1 = readBits(fram, 2, 0, 3)
        let i2 = readBits(fram, 2, 3, 0xa)
        let i3 = readBits(fram, 0x150, 0, 8)    // footer[-8]
        let i4 = readBits(fram, 0x150, 8, 0xe)
        let negativei3 = readBits(fram, 0x150, 0x21, 1) != 0
        let i5 = readBits(fram, 0x150, 0x28, 0xc) << 2
        let i6 = readBits(fram, 0x150, 0x34, 0xc) << 2

        calibrationInfo = CalibrationInfo(i1: i1, i2: i2, i3: negativei3 ? -i3 : i3, i4: i4, i5: i5, i6: i6)
//        DispatchQueue.main.async {
//            self.main?.settings.activeSensorCalibrationInfo = self.calibrationInfo
//        }

    }
    
    /// The customRequestParameters for 0xA1 are built by appending
    /// code + parameters + usefulFunction(uid, code, secret)
    open func nfcCommand(_ code: Subcommand, parameters: Data = Data(), secret: UInt16 = 0) -> NFCCommand {
        return NFCCommand(code: 0xA1, parameters: Data([code.rawValue]) + parameters, description: code.description)
    }


    open func isCrcReportFailed(_ crcReport: String) -> Bool {
        return crcReport.contains("FAILED") && history.count > 0
    }

    open func detailFRAM() throws -> SensorInfo {

        let response = SensorInfo(
            type: String(describing: type),
            family: String(describing: family),
            region: String(describing: region),
            serial: serial,
            state: state.description,
            lastReadingDate: lastReadingDate,
            age: age,
            maxLife: maxLife,
            initializations: initializations
        )

        if encryptedFram.count > 0 && fram.count >= 344 {
            logger.info("\(fram.hexDump(header: "Sensor decrypted FRAM:", startBlock: 0))")
        }

        if crcReport.count > 0 {
            logger.info("crcReport: \(crcReport)")
            if isCrcReportFailed(crcReport) {
                throw LibreError.dataValidation("detailFram sensor data")
            }
        }

        logger.info("Sensor state: \(state.description.lowercased()) (0x\(state.rawValue.hex))")

        if state == .failure {
            let errorCode = fram[6]
            let failureAge = Int(fram[7]) + Int(fram[8]) << 8
            let failureInterval = failureAge == 0 ? "an unknown time" : "\(failureAge) minutes (\(failureAge.formattedInterval))"
            logger.error("Sensor failure error 0x\(errorCode.hex) (\(decodeFailure(error: errorCode))) at \(failureInterval) after activation.")
        }

        // TODO:
        if fram.count >= 344 {
            if debugLevel > 0 {
                logger.info("Sensor factory values: raw minimum threshold: \(fram[330]) (tied to SENSOR_SIGNAL_LOW error, should be 150 for a Libre 1), maximum ADC delta: \(fram[332]) (tied to FILTER_DELTA error, should be 90 for a Libre 1)")
            }

            if initializations > 0 {
                logger.info("Sensor initializations: \(initializations)")
            }

            logger.info("Sensor region: \(region.description) (0x\(fram[323].hex))")
        }

        if maxLife > 0 {
            logger.info("Sensor maximum life: \(maxLife) minutes (\(maxLife.formattedInterval))")
        }

        if age > 0 {
            logger.info("Sensor age: \(age) minutes (\(age.formattedInterval)), started on: \((lastReadingDate - Double(age) * 60).shortDateTime)")
        }
        return response
    }

    func updateCRCReport() {
        if fram.count < 344 {
            crcReport = "NFC: FRAM read did not complete: can't verify CRC"

        } else {
            let headerCRC = UInt16(fram[0...1])
            let bodyCRC   = UInt16(fram[24...25])
            let footerCRC = UInt16(fram[320...321])
            let computedHeaderCRC = crc16(fram[2...23])
            let computedBodyCRC   = crc16(fram[26...319])
            let computedFooterCRC = crc16(fram[322...343])

            var report = "Sensor header CRC16: \(headerCRC.hex), computed: \(computedHeaderCRC.hex) -> \(headerCRC == computedHeaderCRC ? "OK" : "FAILED")"
            report += "\nSensor body CRC16: \(bodyCRC.hex), computed: \(computedBodyCRC.hex) -> \(bodyCRC == computedBodyCRC ? "OK" : "FAILED")"
            report += "\nSensor footer CRC16: \(footerCRC.hex), computed: \(computedFooterCRC.hex) -> \(footerCRC == computedFooterCRC ? "OK" : "FAILED")"

            if fram.count >= 344 + 195 * 8 {
                let commandsCRC = UInt16(fram[344...345])
                let computedCommandsCRC = crc16(fram[346 ..< 344 + 195 * 8])
                report += "\nSensor commands CRC16: \(commandsCRC.hex), computed: \(computedCommandsCRC.hex) -> \(commandsCRC == computedCommandsCRC ? "OK" : "FAILED")"
            }

            crcReport = report
        }
    }
}

func encodeStatusCode(_ status: UInt64) -> String {
    let alphabet = Array("0123456789ACDEFGHJKLMNPQRTUVWXYZ")
    var code = ""
    for i in 0...9 {
        code.append(alphabet[Int(status >> (i * 5)) & 0x1F])
    }
    return code
}


func decodeStatusCode(_ code: String) -> UInt64 {
    let alphabet = Array("0123456789ACDEFGHJKLMNPQRTUVWXYZ")
    let chars = Array(code)
    var status: UInt64 = 0
    for i in 0...9 {
        status += UInt64(alphabet.firstIndex(of: chars[i])!) << (i * 5)
    }
    return status
}

@available(iOS 13.0, *)
func checksummedFRAM(_ data: Data) -> Data {
    var fram = data

    let headerCRC = crc16(fram[         2 ..<  3 * 8])
    let bodyCRC =   crc16(fram[ 3 * 8 + 2 ..< 40 * 8])
    let footerCRC = crc16(fram[40 * 8 + 2 ..< 43 * 8])

    fram[0 ... 1] = headerCRC.data
    fram[3 * 8 ... 3 * 8 + 1] = bodyCRC.data
    fram[40 * 8 ... 40 * 8 + 1] = footerCRC.data

    if fram.count > 43 * 8 {
        let commandsCRC = crc16(fram[43 * 8 + 2 ..< (244 - 6) * 8])    // Libre 1 DF: 429e, A2: f9ae
        fram[43 * 8 ... 43 * 8 + 1] = commandsCRC.data
    }
    return fram
}

@available(iOS 13.0, *)
struct LibreMemoryRegion {
    let numberOfBytes: Int
    let startAddress: Int
}

@available(iOS 13.0, *)
// TODO
func decodeFailure(error: UInt8) -> String {
    switch error {
    case 0x01: return "ADC IRQ overflow"
    case 0x05: return "MMI interrupt"
    case 0x09: return "error in patch table"
    case 0x0A: return "low voltage occurred"
    case 0x0B: return "low voltage occurred"
    case 0x0C: return "FRAM header section CRC error"
    case 0x0D: return "FRAM body section CRC error"
    case 0x0E: return "FRAM footer section CRC error"
    case 0x0F: return "FRAM code section CRC error"
    case 0x10: return "FRAM Lock Table error"
    case 0x13: return "brownout"
    case 0x28: return "battery low indication"
    case 0x34: return "from custom E1 and E2 command"
    default:   return "no specific info"
    }
}
