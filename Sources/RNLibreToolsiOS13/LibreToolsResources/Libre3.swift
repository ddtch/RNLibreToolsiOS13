import Foundation
import CoreNFC


class Libre3: AbstractLibre {


    enum State: UInt8, CustomStringConvertible {
        case manufacturing      = 0x00    // PATCH_STATE_MANUFACTURING
        case storage            = 0x01    // PATCH_STATE_STORAGE
        case insertionDetection = 0x02    // PATCH_STATE_INSERTION_DETECTION
        case insertionFailed    = 0x03    // PATCH_STATE_INSERTION_FAILED
        case paired             = 0x04    // PATCH_STATE_PAIRED
        case expired            = 0x05    // PATCH_STATE_EXPIRED
        case terminated         = 0x06    // PATCH_STATE_TERMINATED_NORMAL
        case error              = 0x07    // PATCH_STATE_ERROR
        case errorTerminated    = 0x08    // PATCH_STATE_ERROR_TERMINATED

        var description: String {
            switch self {
            case .manufacturing:      return "Manufacturing"
            case .storage:            return "Not activated"
            case .insertionDetection: return "Insertion detection"
            case .insertionFailed:    return "Insertion failed"
            case .paired:             return "Paired"
            case .expired:            return "Expired"
            case .terminated:         return "Terminated"
            case .error:              return "Error"
            case .errorTerminated:    return "Terminated (error)"
            }
        }
    }


    enum LifeState: Int {           // SensorLifeState
        case missing         = 1    // MISSING
        case warmup          = 2    // WARMUP
        case ready           = 3    // READY
        case expired         = 4    // EXPIRED
        case active          = 5    // ACTIVE
        case ended           = 6    // ENDED
        case insertionFailed = 7    // INSERTION_FAILED
    }


    enum ProductType: Int, CustomStringConvertible {
        case others = 1
        case sensor = 4

        var description: String {
            switch self {
            case .others: return "OTHERS"
            case .sensor: return "SENSOR"
            }
        }
    }


    // TODO: var members, struct references

    // libre3DPCRLInterface

    struct ActivationInfo {
        let signatureActivation: Int
        let signatureEnableBle: Int
        let wearDuration: Int
        let obpState: Int
    }


    struct PatchInfo {
        let NFC_Key: Int
        let localization: Int
        let generation: Int
        let puckGeneration: Int
        let wearDuration: Int
        let warmupTime: Int
        let productType: Int
        let state: State
        let fwVersion: Data
        let compressedSN: Data
        let securityVersion: Int
    }


    struct ErrorData {
        let errorCode: Int
        let data: Data
    }


    struct GlucoseData {
        let lifeCount: UInt16
        let readingMgDl: UInt16
        let dqError: UInt16
        let historicalLifeCount: UInt16
        let historicalReading: UInt16
        let projectedGlucose: UInt16
        let historicalReadingDQError: UInt16
        let rateOfChange: UInt16
        let trend: Int
        let esaDuration: UInt16
        let temperatureStatus: Int
        let actionableStatus: Int
        let glycemicAlarmStatus: Int
        let glucoseRangeStatus: Int
        let resultRangeStatus: Int
        let sensorCondition: Int
        let uncappedCurrentMgDl: Int
        let uncappedHistoricMgDl: Int
        let temperature: Int
        let fastData: Data
        let reservedData: Data
    }


    struct HistoricalData {
        let reading: Int
        let dqError: Int
        let lifeCount: Int
    }


    struct ActivationResponse {
        let bdAddress: Data
        let BLE_Pin: Data
        let activationTime: Int
    }


    struct EventLog {
        let lifeCount: Int
        let errorData: Int
        let eventData: Int
        let index: Int
    }


    struct FastData {
        let lifeCount: Int
        let uncappedReadingMgdl: Int
        let uncappedHistoricReadingMgDl: Int
        let dqError: Int
        let temperature: Int
        let rawData: Data
    }


    struct PatchStatus {
        let patchState: Int
        let totalEvents: Int
        let lifeCount: Int
        let errorData: Int
        let eventData: Int
        let index: Int
        let currentLifeCount: Int
        let stackDisconnectReason: Int
        let appDisconnectReason: Int
    }


    enum UUID: String, CustomStringConvertible, CaseIterable {

        /// Advertised primary data service
        case data = "089810CC-EF89-11E9-81B4-2A2AE2DBCCE4"

        /// Requests data by writing 13 bytes embedding a "patch control command" (7 bytes?)
        /// and a final sequential Int (starting by 01 00) since it is enqueued
        /// Notifies at the end of the data stream 10 bytes ending in the enqueued id
        /// (for example 01 00 and 02 00 when receiving historic and clinical data on 195A and 1AB8)
        case patchControl = "08981338-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify", "Write"]

        // Receiving "Encryption is insufficient" error when activating notifications before the security commands
        /// Notifies 18 bytes ending in 01 00 during a connection
        case patchStatus = "08981482-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify", "Read"]

        /// Notifies every minute 35 bytes as two packets of 15 + 20 bytes ending in a sequential id
        /// Very probably 10 recent readings of 3 bytes are encoded
        case oneMinuteReading = "0898177A-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify"]

        /// Notifies a first stream of historic data
        /// Very probably 6 readings of 3 bytes are encoded in each packet (12 readings per hour)
        case historicalData = "0898195A-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify"]

        /// Notifies a second longer stream of clinical data
        case clinicalData = "08981AB8-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify"]

        /// Notifies 20 + 20 bytes towards the end of activation
        /// Notifies 20 bytes when shutting down a sensor (CTRL_CMD_SHUTDOWN_PATCH)
        /// and at the first connection after activation
        case eventLog = "08981BEE-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify"]

        /// Notifies the final stream of data during activation
        case factoryData = "08981D24-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify"]

        /// Security service
        case security = "0898203A-EF89-11E9-81B4-2A2AE2DBCCE4"

        /// Writes a single byte command as defined in libre3SecurityConstants' `CMD_`
        /// May notify two bytes: the successful status (also defined as `CMD_READY/DONE/FAILURE`)
        /// and the effective length of the payload streamed on 22CE / 23FA
        /// 01: very first command when activating a sensor
        /// 02: written immediately after 01
        /// 03: third command sent during activation
        /// 04: notified immediately after 03
        /// 08: read the final 67-byte session info, notifies 08 43 -> 22CE notifies 67 bytes + prefixes
        /// 09: during activation notifies A0 8C -> 23FA notifies 140 bytes + prefixes
        /// 0D: during activation is written before 0E
        /// 0E: during activation notifies 0F 41 -> 23FA notifies 69 bytes
        /// 11: read the 23-byte security challenge, notifies 08 17
        case securityCommands = "08982198-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify", "Write"]

        /// Notifies the 23-byte security challenge + prefixes
        /// Writes the 40-byte unlock payload + prefixes
        /// Notifies the 67-byte session info + prefixes
        /// The first two of the last seven notified bytes (16 + 7, 60 + 7) are a progressive Int since activation
        case challengeData = "089822CE-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify", "Write"]

        /// Writes and notifies 20-byte packets during activation and repairing a sensor
        case certificateData = "089823FA-EF89-11E9-81B4-2A2AE2DBCCE4"  // ["Notify", "Write"]

        // TODO:
        case debug = "08982400-EF89-11E9-81B4-2A2AE2DBCCE44"
        case bleLogin = "F001"

        var description: String {
            switch self {
            case .data:             return "data service"
            case .patchControl:     return "patch control"
            case .patchStatus:      return "patch status"
            case .oneMinuteReading: return "one-minute reading"
            case .historicalData:   return "historical data"
            case .clinicalData:     return "clinical data"
            case .eventLog:         return "event log"
            case .factoryData:      return "factory data"
            case .security:         return "security service"
            case .securityCommands: return "security commands"
            case .challengeData:    return "challenge data"
            case .certificateData:  return "certificate data"
            case .debug:            return "debug service"
            case .bleLogin:         return "BLE login"
            }
        }
    }

    class var knownUUIDs: [String] { UUID.allCases.map{$0.rawValue} }


    // maximum packet size is 20
    // notified packets are prefixed by 00, 01, 02, ...
    // written packets are prefixed by 00 00, 12 00, 24 00, 36 00, ...
    // data packets end in a sequential Int: 01 00, 02 00, ...
    //
    // Connection:
    // enable notifications for 2198, 23FA and 22CE
    // write  2198  11
    // notify 2198  08 17
    // notify 22CE  20 + 5 bytes        // 23-byte challenge
    // write  22CE  20 + 20 + 6 bytes   // 40-byte unlock payload
    // write  2198  08
    // notify 2198  08 43
    // notify 22CE  20 * 3 + 11 bytes   // 67-byte session info
    // enable notifications for 1338, 1BEE, 195A, 1AB8, 1D24, 1482
    // notify 1482  18 bytes            // patch status
    // enable notifications for 177A
    // write  1338  13 bytes            // ending in 01 00
    // notify 177A  15 + 20 bytes       // one-minute reading
    // notify 195A  20-byte packets     // historical data
    // notify 1338  10 bytes            // ending in 01 00
    // write  1338  13 bytes            // ending in 02 00
    // notify 1AB8  20-byte packets     // clinical data
    // notify 1338  10 bytes            // ending in 02 00
    //
    // Activation:
    // enable notifications for 2198, 23FA and 22CE
    // write  2198  01
    // write  2198  02
    // write  23FA  20 * 9 bytes        // fixed certificate data
    // write  2198  03
    // notify 2198  04
    // write  2198  09
    // notify 2198  A0 8C
    // notify 23FA  20 * 7 + 8 bytes
    // write  2198  0D
    // write  23FA  20 * 3 + 13 bytes
    // write  2198  0E
    // notify 2198  0F 41
    // notify 23FA  20 * 3 + 9 bytes
    // write  2198  11
    // notify 2198  08 17
    // notify 22CE  20 + 5 bytes        // 23-byte challenge
    // write  22CE  20 * 2 + 6 bytes    // 40-byte unlock payload
    // write  2198  08
    // notify 2198  08 43
    // notify 22CE  20 * 3 + 11 bytes   // 67-byte session info
    // enable notifications for 1338, 1BEE, 195A, 1AB8, 1D24, 1482
    // notify 1482  18 bytes            // patch status
    // enable notifications for 177A
    // write  1338  13 bytes            // ending in 01 00
    // notify 1BEE  20 + 20 bytes       // event log
    // notify 1338  10 bytes            // ending in 01 00
    // write  1338  13 bytes            // ending in 02 00
    // notify 1D24  20 * 10 + 15 bytes  // factory data
    // notify 1338  10 bytes            // ending in 02 00
    //
    // Shutdown:
    // write  1338  13 bytes            // ending in 03 00
    // notify 1BEE  20 bytes            // event log
    // write  1338  13 bytes            // ending in 04 00


    /// Single byte command written to the .securityCommands characteristic 0x2198
    enum SecurityCommand: UInt8, CustomStringConvertible {

        // can be sent sequentially during both the initial activation and when repairing a sensor
        case security_01 = 0x01
        case security_02 = 0x02
        case security_03 = 0x03
        case security_09 = 0x09
        case security_0D = 0x0D
        case security_0E = 0x0E

        /// final command to get a 67-byte session info
        case getSessionInfo = 0x08

        /// first command sent when reconnecting
        case readChallenge  = 0x11

        var description: String {
            switch self {
            case .security_01:    return "security 0x01 command"
            case .security_02:    return "security 0x02 command"
            case .security_03:    return "security 0x03 command"
            case .security_09:    return "security 0x09 command"
            case .security_0D:    return "security 0x0D command"
            case .security_0E:    return "security 0x0E command"
            case .getSessionInfo: return "get session info"
            case .readChallenge:  return "read security challenge"
            }
        }
    }

    /// 13 bytes written to the .patchControl characteristic 0x1338:
    /// - PATCH_CONTROL_COMMAND_SIZE = 7
    /// - a final sequential Int starting by 01 00 since it is enqueued
    enum ControlCommand {
        case historic(Data)       // 1 - CTRL_CMD_HISTORIC
        case backfill(Data)       // 2 - CTRL_CMD_BACKFILL
        case eventLog(Data)       // 3 - CTRL_CMD_EVENTLOG
        case factoryData(Data)    // 4 - CTRL_CMD_FACTORY_DATA
        case shutdownPatch(Data)  // 5 - CTRL_CMD_SHUTDOWN_PATCH
    }

    var buffer: Data = Data()
    var currentControlCommand:  ControlCommand?
    var currentSecurityCommand: SecurityCommand?
    var expectedStreamSize = 0

    override func readBlocks(tag: NFCISO15693Tag, from start: Int, count blocks: Int, requesting: Int = 3) async throws -> (Int, Data) {
        guard securityGeneration >= 1 else {
            logger.error("readBlocks() B3 command not supported by \(type)")
            throw LibreError.commandNotSupported("B3")
        }

        return try await super.readBlocks(tag: tag, from: start, count: blocks, requesting: requesting)
    }
    
    /*
    override func parsePatchInfo(tag: NFCISO15693Tag) async {
        if patchInfo.count == 28 {
            // TODO: ignore the first two bytes A5 00?
            logger.info("Libre 3: patch info: \(patchInfo.hexBytes), CRC: \(Data(patchInfo.suffix(2).reversed()).hex), computed CRC: \(patchInfo[2...25].crc16.hex)")
            // TODO: verify
            let securityVersion = UInt16(patchInfo[2...3])
            let localization    = UInt16(patchInfo[4...5])
            let puckGeneration  = UInt16(patchInfo[6...7])
            logger.info("Libre 3: security version: \(securityVersion) (0x\(securityVersion.hex)), localization: \(localization) (0x\(localization.hex)), puck generation: \(puckGeneration) (0x\(puckGeneration.hex))")
            let wearDuration = patchInfo[8...9]
            maxLife = Int(UInt16(wearDuration))
            logger.info("Libre 3: wear duration: \(maxLife) minutes (\(maxLife.formattedInterval), 0x\(maxLife.hex))")
            let fwVersion = patchInfo.subdata(in: 10 ..< 14)
            logger.info("Libre 3: firmware version: \(fwVersion[3]).\(fwVersion[2]).\(fwVersion[1]).\(fwVersion[0])")
            let productType = Int(patchInfo[14])  // 04 = SENSOR
            logger.info("Libre 3: product type: \(ProductType(rawValue: productType)?.description ?? "unknown") (0x\(productType.hex))")
            // state 04 (.paired) detected already after 15 minutes, 08 for a detached sensor (ERROR_TERMINATED)
            // 05 (.expired) lasts more than further 12 hours, almost 24, before BLE shutdown (06 = .terminated)
            // TODO: verify
            let warmupTime = patchInfo[15]
            logger.info("Libre 3: warmup time: \(warmupTime * 5) minutes (0x\(warmupTime.hex))")
            let sensorState = patchInfo[16]
            // TODO: manage specific Libre 3 states
            state = SensorState(rawValue: sensorState <= 2 ? sensorState: sensorState - 1) ?? .unknown
            logger.info("Libre 3: specific state: \(State(rawValue: sensorState)!.description.lowercased()) (0x\(sensorState.hex)), state: \(state.description.lowercased()) ")
            let serialNumber = Data(patchInfo[17...25])
            serial = serialNumber.string
            logger.info("Libre 3: serial number: \(serialNumber.string) (0x\(serialNumber.hex))")
        }
        
        do {
            let aa = try await send(NFCCommand(code: 0xAA), tag: tag)
            logger.info("NFC: Libre 3 `AA` command output: \(aa.hexBytes), CRC: \(Data(aa.suffix(2).reversed()).hex), computed CRC: \(aa.prefix(aa.count-2).crc16.hex), string: \"\(aa.string)\"")
        } catch {
            logger.error("libre 3 output exception: \(error.localizedDescription)")
        }
    }
     */


    func send(securityCommand cmd: SecurityCommand) {
        /*
        logger.info("Bluetooth: sending to \(type) \(transmitter!.peripheral!.name!) `\(cmd.description)` command 0x\(cmd.rawValue.hex)")
        currentSecurityCommand = cmd
        transmitter!.write(Data([cmd.rawValue]), for: UUID.securityCommands.rawValue, .withResponse)
         */
    }


    func parsePackets(_ data: Data) -> (Data, String) {
        var payload = Data()
        var str = ""
        var offset = data.startIndex
        var offsetEnd = offset
        let endIndex = data.endIndex
        while offset < endIndex {
            str += data[offset].hex + "  "
            _ = data.formIndex(&offsetEnd, offsetBy: 20, limitedBy: endIndex)
            str += data[offset + 1 ..< offsetEnd].hexBytes
            payload += data[offset + 1 ..< offsetEnd]
            _ = data.formIndex(&offset, offsetBy: 20, limitedBy: endIndex)
            if offset < endIndex { str += "\n" }
        }
        return (payload, str)
    }


    func write(_ data: Data, for uuid: UUID = .challengeData) {
        /*
        let packets = (data.count - 1) / 18 + 1
        for i in 0 ... packets - 1 {
            let offset = i * 18
            let id = Data([UInt8(offset & 0xFF), UInt8(offset >> 8)])
            let packet = id + data[offset ... min(offset + 17, data.count - 1)]
            logger.info("Bluetooth: writing packet \(packet.hexBytes) to \(transmitter!.peripheral!.name!)'s \(uuid.description) characteristic")
            transmitter!.write(packet, for: uuid.rawValue, .withResponse)
        }
         */
    }


    /// called by Abbott Transmitter class
    func read(_ data: Data, for uuid: String) {

        switch UUID(rawValue: uuid) {

        case .patchControl:
            if data.count == 10 {
                let suffix = data.suffix(2).hex
                // TODO: manage enqueued id
                if suffix == "0100" {
                    // logger.info("\(type) \(transmitter!.peripheral!.name!): received \(buffer.count/20) packets of historical data")
                    // TODO
                } else if suffix == "0200" {
                    // logger.info("\(type) \(transmitter!.peripheral!.name!): received \(buffer.count/20) packets of clinical data")
                    // TODO
                }
                buffer = Data()
            }

            // The Libre 3 sends every minute 35 bytes as two packets of 15 + 20 bytes
            // The final Int is a sequential id
        case .oneMinuteReading:
            if buffer.count == 0 {
                buffer = Data(data)
            } else {
                buffer += data
                if buffer.count == 35 {
                    let payload = buffer.prefix(33)
                    let id = UInt16(buffer.suffix(2))
                    // logger.info("\(type) \(transmitter!.peripheral!.name!): received \(buffer.count) bytes of \(UUID(rawValue: uuid)!) (payload: \(payload.count) bytes): \(payload.hex), id: \(id.hex)")
                    buffer = Data()
                }
            }

        case .historicalData, .clinicalData, .eventLog, .factoryData:
            if buffer.count == 0 {
                buffer = Data(data)
            } else {
                buffer += data
            }
            let payload = data.prefix(18)
            let id = UInt16(data.suffix(2))
            // logger.info("\(type) \(transmitter!.peripheral!.name!): received \(data.count) bytes of \(UUID(rawValue: uuid)!) (payload: \(payload.count) bytes): \(payload.hex), id: \(id.hex)")

        case .patchStatus:
            if buffer.count == 0 {
                let payload = data.prefix(16)
                let id = UInt16(data.suffix(2))
                // logger.info("\(type) \(transmitter!.peripheral!.name!): received \(data.count) bytes of \(UUID(rawValue: uuid)!) (payload: \(payload.count) bytes): \(payload.hex), id: \(id.hex)")
            }
            // TODO


        case .securityCommands:
            if data.count == 2 {
                expectedStreamSize = Int(data[1] + data[1] / 20 + 1)
                // logger.info("\(type) \(transmitter!.peripheral!.name!): expected response size: \(expectedStreamSize) bytes (payload: \(data[1]) bytes)")
                // TEST: when sniffing Trident:
                if data[1] == 23 {
                    currentSecurityCommand = .readChallenge
                } else if data[1] == 67 {
                    currentSecurityCommand = .getSessionInfo
                }
            }

        case .challengeData:
            if buffer.count == 0 {
                buffer = Data(data)
            } else {
                buffer += data

                if buffer.count == expectedStreamSize {

                    let (payload, hexDump) = parsePackets(buffer)
                    // logger.info("\(type) \(transmitter!.peripheral!.name!): received \(buffer.count) bytes of \(UUID(rawValue: uuid)!) (payload: \(payload.count) bytes):\n\(hexDump)")

                    switch currentSecurityCommand {

                    case .readChallenge:

                        // getting: df4bd2f783178e3ab918183e5fed2b2b c201 0000 e703a7
                        //                                        increasing

                        let challengeCount = UInt16(payload[16...17])
                        // logger.info("\(type) \(transmitter!.peripheral!.name!): security challenge # \(challengeCount.hex): \(payload.hex)")

                        // TODO
                        /*
                        if main.settings.debugLevel > 2 {
                            let certificate = "03 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F 10 00 01 5F 14 9F E1 01 00 00 00 00 00 00 00 00 04 E2 36 95 4F FD 06 A2 25 22 57 FA A7 17 6A D9 0A 69 02 E6 1D DA FF 40 FB 36 B8 FB 52 AA 09 2C 33 A8 02 32 63 2E 94 AF A8 28 86 AE 75 CE F9 22 CD 88 85 CE 8C DA B5 3D AB 2A 4F 23 9B CB 17 C2 6C DE 74 9E A1 6F 75 89 76 04 98 9F DC B3 F0 C7 BC 1D A5 E6 54 1D C3 CE C6 3E 72 0C D9 B3 6A 7B 59 3C FC C5 65 D6 7F 1E E1 84 64 B9 B9 7C CF 06 BE D0 40 C7 BB D5 D2 2F 35 DF DB 44 58 AC 7C 46 15".bytes
                            write(certificate, for: .certificateData)
                        }

                        if main.settings.debugLevel < 2 { // TEST: sniff Trident
                            log("\(type) \(transmitter!.peripheral!.name!): writing 40-zero challenge data (it should be the unlock payload)")
                            let challengeData = Data(count: 40)
                            write(challengeData)
                            // writing .getSessionInfo makes the Libre 3 disconnect
                            send(securityCommand: .getSessionInfo)
                        }
                         */

                    case .getSessionInfo:
                        let challengeCountPlusOne = UInt16(payload[60...61])
                        // logger.info("\(type) \(transmitter!.peripheral!.name!): session info: \(payload.hex) (security challenge # + 1: \(challengeCountPlusOne.hex))")
                        // transmitter!.peripheral?.setNotifyValue(true, for: transmitter!.characteristics[UUID.patchStatus.rawValue]!)
                        // logger.info("\(type) \(transmitter!.peripheral!.name!): enabling notifications on the patch status characteristic")


                    default:
                        break // currentCommand
                    }

                    buffer = Data()
                    expectedStreamSize = 0
                    currentControlCommand = nil
                    currentSecurityCommand = nil

                }
            }

        default:
            break  // uuid
        }

    }


    // MARK: - Constants


    // Libre3BLESensor
    static let STATE_NONE           = 0
    static let STATE_AUTHENTICATING = 5
    static let STATE_AUTHORIZING    = 8
    static let MAX_WRITE_OFFSET_DATA_LENGTH = 18
    static let HISTORIC_POINT_LATENCY = 17


    // Trident MSLibre3Constants
    static let LIBRE3_HISTORIC_LIFECOUNT_INTERVAL = 5
    static let LIBRE3_MAX_HISTORIC_READING_IN_PACKET = 10
    static let LIBRE3_DQERROR_MAX = 0xFFFF
    static let LIBRE3_DQERROR_DQ              = 0x8000  // 32768
    static let LIBRE3_DQERROR_SENSOR_TOO_HOT  = 0xA000  // 40960
    static let LIBRE3_DQERROR_SENSOR_TOO_COLD = 0xC000  // 49152
    static let LIBRE3_DQERROR_OUTLIER_FILTER_DELTA = 2
    static let LIBRE3_SENSOR_CONDITION_OK = 0
    static let LIBRE3_SENSOR_CONDITION_INVALID = 1
    static let LIBRE3_SENSOR_CONDITION_ESA_CHECK = 2


    // Libre3.libre3DPCRLInterface
    static let ABT_NO_ERROR = 0x0
    static let ABT_ERR3_TIME_CHANGE = 0x2e
    static let ABT_ERR3_SENSOR_EXPIRED = 0x33
    static let ABT_ERR3_SENSOR_RSSI_ERROR = 0x39
    static let ABT_ERR3_BLE_TURNED_OFF = 0x4b
    static let ABT_ERR3_REPLACE_SENSOR_ERROR = 0x16d
    static let ABT_ERR3_SENSOR_FALL_OUT_ERROR = 0x16e
    static let ABT_ERR3_INCOMPATIBLE_SENSOR_TYPE_ERROR = 0x16f
    static let ABT_ERR3_SENSOR_CAL_CODE_ERROR = 0x170
    static let ABT_ERR3_SENSOR_DYNAMIC_DATA_CRC_ERROR = 0x171
    static let ABT_ERR3_SENSOR_FACTORY_DATA_CRC_ERROR = 0x172
    static let ABT_ERR3_SENSOR_LOG_DATA_CRC_ERROR = 0x173
    static let ABT_ERR3_SENSOR_NOT_YOURS_ERROR = 0x174
    static let ABT_ERR3_REALTIME_RESULT_DQ_ERROR = 0x175
    static let ABT_ERR3_SENSOR_ESA_DETECTED = 0x17c
    static let ABT_ERR3_SENSOR_NOT_IN_GLUCOSE_MEASUREMENT_STATE = 0x181
    static let ABT_ERR3_BLE_PACKET_ERROR = 0x182
    static let ABT_ERR3_INVALID_DATA_SIZE_ERROR = 0x183
    static let ABT_ERR9_LIB_NOT_INITIALIZED_ERROR = 0x3d6
    static let ABT_ERR9_MEMORY_SIZE_ERROR = 0x3d7
    static let ABT_ERR9_NV_MEMORY_CRC_ERROR = 0x3da
    static let ABT_ERROR_DATA_BYTES = 0x8
    static let LIBRE3_DP_LIBRARY_PARSE_ERROR = ~0x0
    static let NFC_ACTIVATION_COMMAND_PAYLOAD_SIZE = 0xa
    static let PATCH_CONTROL_BACKFILL_GREATER_SIZE = 0xb
    static let ABT_HISTORICAL_POINTS_PER_NOTIFICATION = 0x6
    static let LIB3_RECORD_ORDER_NEWEST_TO_OLDEST = 0x0
    static let LIB3_RECORD_ORDER_OLDEST_TO_NEWEST = 0x1
    static let PATCH_CONTROL_COMMAND_SIZE = 0x7
    static let PATCH_NFC_EVENT_LOG_NUM_EVENTS = 0x3
    static let ABT_EVENT_LOGS_PER_NOTIFICATION = 0x2
    static let ABT_ERR10_INVALID_USER = 0x582
    static let ABT_ERR10_DUPLICATE_USER = 0x596
    static let ABT_ERR10_INVALID_TOKEN = 0x5a6
    static let ABT_ERR10_INVALID_DEVICE = 0x5aa
    static let ABT_ERR0_BLE_TURNED_OFF = 0x1f7
    static let SCRATCH_PAD_BUFFER_SIZE = 0x400
    static let CRL_NV_MEMORY_SIZE = 0x400
    static let LIBRE3_DEFAULT_WARMUP_TIME = 0x3c
    static let MAX_SERIAL_NUMBER_SIZE = 0xf


    // Trident ISecurityContext
    static let IV_ENC_SIZE = 8
    static let MODE_DECRYPT = 2
    static let MODE_ENCRYPT = 1
    static let PACKET_TYPE_CONTROL_COMMAND = 0
    static let PACKET_TYPE_CONTROL_RESPONSE = 1
    static let PACKET_TYPE_PATCH_STATUS = 2
    static let PACKET_TYPE_CURRENT_GLUCOSE = 3
    static let PACKET_TYPE_BACKFILL_HISTORIC = 4
    static let PACKET_TYPE_BACKFILL_CLINICAL = 5
    static let PACKET_TYPE_EVENT_LOG = 6
    static let PACKET_TYPE_FACTORY_DATA = 7


    // Trident libre3SecurityConstants
    static let CERT_PATCH_DATE_STAMP_LENGTH: UInt = 0xDEADBEEF
    static let CERT_PATCH_LENGTH: UInt = 0xDEADBEEF
    static let CERT_PATCH_VERSION_LENGTH: UInt = 0xDEADBEEF
    static let CERT_PUBLIC_KEY_LENGTH: UInt = 0xDEADBEEF
    static let CERT_SERIAL_NUMBER_LENGTH: UInt = 0xDEADBEEF
    static let CERT_SIGNATURE_LENGTH: UInt = 0xDEADBEEF

    static let CMD_AUTHORIZATION_CHALLENGE: UInt8 = 42
    static let CMD_AUTHORIZED: UInt8 = 42
    static let CMD_AUTHORIZE_ECDSA: UInt8 = 42
    static let CMD_AUTHORIZE_SYMMETRIC: UInt8 = 42
    static let CMD_CERT_ACCEPTED: UInt8 = 42
    static let CMD_CERT_READY: UInt8 = 42
    static let CMD_CHALLENGE_LOAD_DONE: UInt8 = 42
    static let CMD_ECDH_COMPLETE: UInt8 = 42
    static let CMD_ECDH_START: UInt8 = 42
    static let CMD_EPHEMERAL_KEY_READY: UInt8 = 42
    static let CMD_EPHEMERAL_LOAD_DONE: UInt8 = 42
    static let CMD_IV_AUTHENTICATED_SEND: UInt8 = 42
    static let CMD_IV_READY: UInt8 = 42
    static let CMD_KEY_AGREEMENT: UInt8 = 42
    static let CMD_LOAD_CERT_DATA: UInt8 = 42
    static let CMD_LOAD_CERT_DONE: UInt8 = 42
    static let CMD_MODE_SWITCH: UInt8 = 42
    static let CMD_SEND_CERT: UInt8 = 42
    static let CMD_VERIFICATION_FAILURE: UInt8 = 42

    static let CRYPTO_KEY_LENGTH_BYTES: UInt = 0xDEADBEEF
    static let CRYPTO_MAC_LENGTH_BYTES: UInt = 0xDEADBEEF
    static let L3_SEC_ERROR_AUTHENTICATION_FAILED: UInt = 0xDEADBEEF
    static let L3_SEC_ERROR_AUTHORIZATION_FAILED: UInt = 0xDEADBEEF
    static let L3_SEC_ERROR_DECRYPTION_FAILED: UInt = 0xDEADBEEF
    static let L3_SEC_ERROR_ENCRYPTION_FAILED: UInt = 0xDEADBEEF
    static let L3_SEC_ERROR_INVALID_CERTIFICATE: UInt = 0xDEADBEEF
    static let L3_SEC_ERROR_LIB_ERROR: UInt = 0xDEADBEEF

}


/// whiteCryption Secure Key Box
struct Libre3SKBCryptoLib {
    let g_engine: Int
    let CRYPTO_EXTENSION_INIT_LIB: Int
    let CRYPTO_RETURN_SUCCESS: Int
    let CRYPTO_EXTENSION_INIT_ECDH: Int
    let CRYPTO_EXTENSION_SET_PATCH_ATTRIB: Int
    let CRYPTO_EXTENSION_SET_CERTIFICATE: Int
    let CRYPTO_EXTENSION_GENERATE_EPHEMERAL: Int
    let CRYPTO_EXTENSION_GENERATE_KAUTH: Int
    let CRYPTO_EXTENSION_ENCRYPT: Int
    let CRYPTO_EXTENSION_DECRYPT: Int
    let CRYPTO_EXTENSION_EXPORT_KAUTH: Int
    let PUBLIC_KEY_TYPE_UNCOMPRESSED: UInt8
    let CRYPTO_PUBLIC_KEY_SIZE: Int
    let CRYPTO_EXTENSION_WRAP_DIAGNOSTIC_DATA: Int
    let CRYPTO_RETURN_INVALID_PARAM: Int
    let patchSigningKey: Int
    let securityVersion: Int
    let max_key_index: Int
    let app_private_key: Int
    let app_certificate: Int
}


// MARK: - PacketLogger logs

// Written to the .certificationData 0x23FA characteristic after the commands 01 and 02 during both activation and repairing a sensor:

// 00 00 03 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F 10
// 12 00 00 01 5F 14 9F E1 01 00 00 00 00 00 00 00 00 04 E2 36
// 24 00 95 4F FD 06 A2 25 22 57 FA A7 17 6A D9 0A 69 02 E6 1D
// 36 00 DA FF 40 FB 36 B8 FB 52 AA 09 2C 33 A8 02 32 63 2E 94
// 48 00 AF A8 28 86 AE 75 CE F9 22 CD 88 85 CE 8C DA B5 3D AB
// 5A 00 2A 4F 23 9B CB 17 C2 6C DE 74 9E A1 6F 75 89 76 04 98
// 6C 00 9F DC B3 F0 C7 BC 1D A5 E6 54 1D C3 CE C6 3E 72 0C D9
// 7E 00 B3 6A 7B 59 3C FC C5 65 D6 7F 1E E1 84 64 B9 B9 7C CF
// 90 00 06 BE D0 40 C7 BB D5 D2 2F 35 DF DB 44 58 AC 7C 46 15

// 03 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F 10 00 01 5F 14 9F E1 01 00 00 00 00 00 00 00 00 04 E2 36 95 4F FD 06 A2 25 22 57 FA A7 17 6A D9 0A 69 02 E6 1D DA FF 40 FB 36 B8 FB 52 AA 09 2C 33 A8 02 32 63 2E 94 AF A8 28 86 AE 75 CE F9 22 CD 88 85 CE 8C DA B5 3D AB 2A 4F 23 9B CB 17 C2 6C DE 74 9E A1 6F 75 89 76 04 98 9F DC B3 F0 C7 BC 1D A5 E6 54 1D C3 CE C6 3E 72 0C D9 B3 6A 7B 59 3C FC C5 65 D6 7F 1E E1 84 64 B9 B9 7C CF 06 BE D0 40 C7 BB D5 D2 2F 35 DF DB 44 58 AC 7C 46 15
