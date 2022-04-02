import CoreNFC

typealias SensorUid = Data
typealias PatchInfo = Data

protocol Sensor {
    var family: SensorFamily { get }
    var region: SensorRegion { get }

    var serial: String { get }
    var uid: SensorUid { get }
    var patchInfo: PatchInfo { get }
    var state: SensorState { get set } // TODO: should be likely just get
    var securityGeneration: Int { get }
    var lastReadingDate: Date { get set }
    var fram: Data { get set }
    var type: SensorType { get }
    
    var history: [Glucose] { get }
    var trend: [Glucose] { get }
    var factoryTrend: [Glucose] { get }
    var factoryHistory: [Glucose] { get }
        
    func activate(tag: NFCISO15693Tag) async throws
    func scanHistory(tag: NFCISO15693Tag) async throws
    
    @discardableResult
    func readFram(tag: NFCISO15693Tag) async throws -> Data
    
    func detailFRAM() throws -> SensorInfo
    
    // TODO: likely to be removed from protocol and should be kept private
    func read(tag: NFCISO15693Tag, fromBlock start: Int, count blocks: Int, requesting: Int, retries: Int) async throws -> (Int, Data)
    func readBlocks(tag: NFCISO15693Tag, from start: Int, count blocks: Int, requesting: Int) async throws -> (Int, Data)
    func nfcCommand(_ code:  Subcommand, parameters: Data, secret: UInt16) -> NFCCommand
    
    @discardableResult
    func send(_ cmd: NFCCommand, tag: NFCISO15693Tag) async throws -> Data
}

struct SensorInfo: Encodable {
    var type: String
    var family: String
    var region: String
    var serial: String
    var state: String
    var lastReadingDate: Date
    var age: Int
    var maxLife: Int
    var initializations: Int
}

@available(iOS 13.0, *)
enum SensorType: String, CustomStringConvertible {
    case libre1       = "Libre 1"
    case libreUS14day = "Libre US 14d"
    case libreProH    = "Libre Pro/H"
    case libre2       = "Libre 2"
    case libre2US     = "Libre 2 US"
    case libre2CA     = "Libre 2 CA"
    case libreSense   = "Libre Sense"
    case libre3       = "Libre 3"
    case unknown      = "Libre"

    init(patchInfo: PatchInfo) {
        switch patchInfo[0] {
        case 0xDF: self = .libre1
        case 0xA2: self = .libre1
        case 0xE5: self = .libreUS14day
        case 0x70: self = .libreProH
        case 0x9D: self = .libre2
        case 0x76: self = patchInfo[3] == 0x02 ? .libre2US : patchInfo[3] == 0x04 ? .libre2CA : patchInfo[2] >> 4 == 7 ? .libreSense : .unknown
        default:
            if patchInfo.count > 6 { // Libre 3's NFC A1 command ruturns 35 or 28 bytes
                self = .libre3
            } else {
                self = .unknown
            }
        }
    }

    var description: String { self.rawValue }
}

@available(iOS 13.0, *)
enum SensorFamily: Int, CustomStringConvertible {
    case libre      = 0
    case librePro   = 1
    case libre2     = 3
    case libreSense = 7

    var description: String {
        switch self {
        case .libre:      return "Libre"
        case .librePro:   return "Libre Pro"
        case .libre2:     return "Libre 2"
        case .libreSense: return "Libre Sense"
        }
    }
}

@available(iOS 13.0, *)
enum SensorRegion: Int, CustomStringConvertible {
    case unknown            = 0
    case european           = 1
    case usa                = 2
    case australianCanadian = 4
    case eastern            = 8

    var description: String {
        switch self {
        case .unknown:            return "unknown"
        case .european:           return "European"
        case .usa:                return "USA"
        case .australianCanadian: return "Australian / Canadian"
        case .eastern:            return "Eastern"
        }
    }
}

@available(iOS 13.0, *)
enum SensorState: UInt8, CustomStringConvertible {
    case unknown      = 0x00

    case notActivated = 0x01
    case warmingUp    = 0x02    // 60 minutes
    case active       = 0x03    // ≈ 14.5 days
    case expired      = 0x04    // 12 hours more; Libre 2: Bluetooth shutdown
    case shutdown     = 0x05    // 15th day onwards
    case failure      = 0x06

    var description: String {
        switch self {
        case .notActivated: return "Not activated"
        case .warmingUp:    return "Warming up"
        case .active:       return "Active"
        case .expired:      return "Expired"
        case .shutdown:     return "Shut down"
        case .failure:      return "Failure"
        default:            return "Unknown"
        }
    }
}


struct NFCCommand {
    let code: Int
    var parameters: Data = Data()
    var description: String = ""
}

enum Subcommand: UInt8, CustomStringConvertible {
    case unlock          = 0x1a    // lets read FRAM in clear and dump further blocks with B0/B3
    case activate        = 0x1b
    case enableStreaming = 0x1e
    case getSessionInfo  = 0x1f    // GEN_SECURITY_CMD_GET_SESSION_INFO
    case unknown0x10     = 0x10    // returns the number of parameters + 3
    case unknown0x1c     = 0x1c
    case unknown0x1d     = 0x1d    // disables Bluetooth
    // Gen2
    case readChallenge   = 0x20    // returns 25 bytes
    case readBlocks      = 0x21
    case readAttribute   = 0x22    // returns 6 bytes ([0]: sensor state)
    var description: String {
        switch self {
        case .unlock:          return "unlock"
        case .activate:        return "activate"
        case .enableStreaming: return "enable BLE streaming"
        case .getSessionInfo:  return "get session info"
        case .readChallenge:   return "read security challenge"
        case .readBlocks:      return "read FRAM blocks"
        case .readAttribute:   return "read patch attribute"
        default:               return "[unknown: 0x\(rawValue.hex)]"
        }
    }
}


final class SensorFactory {
    
    private let toolbox: LibreToolbox
    
    init(toolbox: LibreToolbox) {
        self.toolbox = toolbox
    }
    
    func build(tag: NFCISO15693Tag, patchInfo: PatchInfo, systemInfo: NFCISO15693SystemInfo) async -> Sensor {
        let uid = tag.identifier.hex
        toolbox.logger.info("NFC: IC identifier: \(uid)")

        let sensor: Sensor
        let sensorType = SensorType(patchInfo: patchInfo)
        switch sensorType {
        case .libre3:
            sensor = Libre3(tag: tag, systemInfo: systemInfo, patchInfo: patchInfo, toolbox: toolbox)
        case .libre2:
            sensor = Libre2CA(tag: tag, systemInfo: systemInfo, patchInfo: patchInfo, toolbox: toolbox)
        case .libre2US:
            sensor = Libre2US(tag: tag, systemInfo: systemInfo, patchInfo: patchInfo, toolbox: toolbox)
        case .libreUS14day:
            sensor = Libre14US(tag: tag, systemInfo: systemInfo, patchInfo: patchInfo, toolbox: toolbox)
        case .libreProH:
            sensor = LibrePro(tag: tag, systemInfo: systemInfo, patchInfo: patchInfo, toolbox: toolbox)
        default:
            sensor = Libre1(tag: tag, systemInfo: systemInfo, patchInfo: patchInfo, toolbox: toolbox)
        }

        if patchInfo.count > 0 {
            toolbox.logger.info("NFC: patch info: \(patchInfo.hex)")
            toolbox.logger.info("NFC: sensor type: \(sensor.type.rawValue)\(patchInfo.hex.hasPrefix("a2") ? " (new 'A2' kind)" : "")")
            toolbox.logger.info("NFC: sensor security generation [0-3]: \(sensor.securityGeneration)")
        }

        toolbox.logger.info("NFC: sensor serial number: \(sensor.serial)")

        // https://www.st.com/en/embedded-software/stsw-st25ios001.html#get-software

        return sensor
    }
}

extension Sensor {
    
    func readBlocks(tag: NFCISO15693Tag, from start: Int, count blocks: Int) async throws -> (Int, Data) {
        return try await readBlocks(tag: tag, from: start, count: blocks, requesting: 3)
    }
    
    func read(tag: NFCISO15693Tag, fromBlock start: Int, count blocks: Int) async throws -> (Int, Data) {
        return try await read(tag: tag, fromBlock: start, count: blocks, requesting: 3, retries: 5)
    }
    
    func nfcCommand(_ code: Subcommand) -> NFCCommand {
        return nfcCommand(code, parameters: Data(), secret: 0)
    }
}
