import Foundation


// https://github.com/bubbledevteam/bubble-client-swift/blob/master/LibreSensor/


struct OOPServer {
    var siteURL: String
    var token: String
    var calibrationEndpoint: String?
    var historyEndpoint: String?
    var historyAndCalibrationEndpoint: String?
    var historyAndCalibrationA2Endpoint: String?
    var bleHistoryEndpoint: String?
    var activationEndpoint: String?
    var nfcAuthEndpoint: String?
    var nfcAuth2Endpoint: String?
    var nfcDataEndpoint: String?
    var nfcDataAlgorithmEndpoint: String?

    // TODO: Gen2:

    // /openapi/xabetLibre libreoop2AndCalibrate("patchUid", "patchInfo", "content", "accesstoken" = "xabet-202104", "session")

    // /libre2ca/bleAuth ("p1", "patchUid", "authData")
    // /libre2ca/bleAuth2 ("p1", "authData")
    // /libre2ca/bleAlgorithm ("p1", "pwd", "bleData", "patchUid", "patchInfo")

    // /libre2ca/nfcAuth ("patchUid", "authData")
    // /libre2ca/nfcAuth2 ("p1", "authData")
    // /libre2ca/nfcData ("patchUid", "authData")
    // /libre2ca/nfcDataAlgorithm ("p1", "authData", "content", "patchUid", "patchInfo")


    static let `default`: OOPServer = OOPServer(siteURL: "https://www.glucose.space",
                                                token: "bubble-201907",
                                                calibrationEndpoint: "calibrateSensor",
                                                historyEndpoint: "libreoop2",
                                                historyAndCalibrationEndpoint: "libreoop2AndCalibrate",
                                                historyAndCalibrationA2Endpoint: "callnoxAndCalibrate",
                                                bleHistoryEndpoint: "libreoop2BleData",
                                                activationEndpoint: "activation")
    static let gen2: OOPServer = OOPServer(siteURL: "https://www.glucose.space",
                                           token: "xabet-202104",
                                           nfcAuthEndpoint: "libre2ca/nfcAuth",
                                           nfcAuth2Endpoint: "libre2ca/nfcAuth2",
                                           nfcDataEndpoint: "libre2ca/nfcData",
                                           nfcDataAlgorithmEndpoint: "libre2ca/nfcDataAlgorithm")

}

enum OOPError: LocalizedError {
    case noConnection
    case jsonDecoding

    var errorDescription: String? {
        switch self {
        case .noConnection: return "no connection"
        case .jsonDecoding: return "JSON decoding"
        }
    }
}

struct OOPGen2Response: Codable {
    let p1: Int
    let data: String
    let error: String
}


struct OOP {

    enum TrendArrow: Int, CustomStringConvertible, CaseIterable {
        case unknown        = -1
        case notDetermined  = 0
        case fallingQuickly = 1
        case falling        = 2
        case stable         = 3
        case rising         = 4
        case risingQuickly  = 5

        var description: String {
            switch self {
            case .notDetermined:  return "NOT_DETERMINED"
            case .fallingQuickly: return "FALLING_QUICKLY"
            case .falling:        return "FALLING"
            case .stable:         return "STABLE"
            case .rising:         return "RISING"
            case .risingQuickly:  return "RISING_QUICKLY"
            default:              return ""
            }
        }

        init(string: String) {
            for arrow in TrendArrow.allCases {
                if string == arrow.description {
                    self = arrow
                    return
                }
            }
            self = .unknown
        }

        var symbol: String {
            switch self {
            case .fallingQuickly: return "↓"
            case .falling:        return "↘︎"
            case .stable:         return "→"
            case .rising:         return "↗︎"
            case .risingQuickly:  return "↑"
            default:              return "---"
            }
        }
    }

    enum Alarm: Int, CustomStringConvertible, CaseIterable {
        case unknown              = -1
        case notDetermined        = 0
        case lowGlucose           = 1
        case projectedLowGlucose  = 2
        case glucoseOK            = 3
        case projectedHighGlucose = 4
        case highGlucose          = 5

        var description: String {
            switch self {
            case .notDetermined:        return "NOT_DETERMINED"
            case .lowGlucose:           return "LOW_GLUCOSE"
            case .projectedLowGlucose:  return "PROJECTED_LOW_GLUCOSE"
            case .glucoseOK:            return "GLUCOSE_OK"
            case .projectedHighGlucose: return "PROJECTED_HIGH_GLUCOSE"
            case .highGlucose:          return "HIGH_GLUCOSE"
            default:                    return ""
            }
        }

        init(string: String) {
            for alarm in Alarm.allCases {
                if string == alarm.description {
                    self = alarm
                    return
                }
            }
            self = .unknown
        }

        var shortDescription: String {
            switch self {
            case .lowGlucose:           return "LOW"
            case .projectedLowGlucose:  return "GOING LOW"
            case .glucoseOK:            return "OK"
            case .projectedHighGlucose: return "GOING HIGH"
            case .highGlucose:          return "HIGH"
            default:                    return ""
            }
        }
    }

}


// TODO: Codable
class OOPHistoryResponse {
    var currentGlucose: Int = 0
    var historyValues: [Glucose] = []
}

protocol GlucoseSpaceHistory {
    var isError: Bool { get }
    var sensorTime: Int? { get }
    var canGetParameters: Bool { get }
    var sensorState: SensorState { get }
    var valueError: Bool { get }
    func glucoseData(date: Date) -> (Glucose?, [Glucose])
}


struct OOPHistoryValue: Codable {
    let bg: Double
    let quality: Int
    let time: Int
}

struct GlucoseSpaceHistoricGlucose: Codable {
    let value: Int
    let dataQuality: Int    // if != 0, the value is erroneous
    let id: Int
}


class GlucoseSpaceHistoryResponse: OOPHistoryResponse, Codable { // TODO: implement the GlucoseSpaceHistory protocol
    var alarm: String?
    var esaMinutesToWait: Int?
    var historicGlucose: [GlucoseSpaceHistoricGlucose] = []
    var isActionable: Bool?
    var lsaDetected: Bool?
    var realTimeGlucose: GlucoseSpaceHistoricGlucose = GlucoseSpaceHistoricGlucose(value: 0, dataQuality: 0, id: 0)
    var trendArrow: String?
    var msg: String?
    var errcode: String?
    var endTime: Int?    // if != 0, the sensor expired

    enum Msg: String {
        case RESULT_SENSOR_STORAGE_STATE
        case RESCAN_SENSOR_BAD_CRC

        case TERMINATE_SENSOR_NORMAL_TERMINATED_STATE    // errcode: 10
        case TERMINATE_SENSOR_ERROR_TERMINATED_STATE
        case TERMINATE_SENSOR_CORRUPT_PAYLOAD

        // HTTP request bad arguments
        case FATAL_ERROR_BAD_ARGUMENTS

        // sensor state
        case TYPE_SENSOR_NOT_STARTED
        case TYPE_SENSOR_STARTING
        case TYPE_SENSOR_Expired
        case TYPE_SENSOR_END
        case TYPE_SENSOR_ERROR
        case TYPE_SENSOR_OK
        case TYPE_SENSOR_DETERMINED
    }


    func glucoseData(sensorAge: Int, readingDate: Date) -> [Glucose] {
        historyValues = [Glucose]()
        let startDate = readingDate - Double(sensorAge) * 60
        // let current = Glucose(realTimeGlucose.value, id: realTimeGlucose.id, date: startDate + Double(realTimeGlucose.id * 60))
        currentGlucose = realTimeGlucose.value
        var history = historicGlucose
        if (history.first?.id ?? 0) < (history.last?.id ?? 0) {
            history = history.reversed()
        }
        for g in history {
            let glucose = Glucose(g.value, id: g.id, date: startDate + Double(g.id * 60), dataQuality: Glucose.DataQuality(rawValue: g.dataQuality), source: "OOP" )
            historyValues.append(glucose)
        }
        return historyValues
    }
}

class GlucoseSpaceHistoryAndCalibrationResponse: OOPHistoryResponse, Codable { // TODO: implement the GlucoseSpaceHistory protocol
    var errcode: Int?
    var data: GlucoseSpaceHistoryResponse?
    var slope: Calibration?
    var oopType: String?    // "oop1", "oop2"
    var session: String?
}


// "callnox" endpoint specific for Libre 1 A2

struct OOPCurrentValue: Codable {
    let currentTime: Int?
    let currentTrend: Int?
    let serialNumber: String?
    let historyValues: [OOPHistoryValue]?
    let currentBg: Double?
    let timestamp: Int?
    enum CodingKeys: String, CodingKey {
        case currentTime
        case currentTrend = "currenTrend"
        case serialNumber
        case historyValues = "historicBg"
        case currentBg
        case timestamp
    }
}

struct GlucoseSpaceList: Codable {
    let content: OOPCurrentValue?
    let timestamp: Int?
}

class GlucoseSpaceA2HistoryResponse: OOPHistoryResponse, Codable { // TODO: implement the GlucoseSpaceHistory protocol
    var errcode: Int?
    var list: [GlucoseSpaceList]?

    var content: OOPCurrentValue? {
        return list?.first?.content
    }
}


/// errcode: 4, msg: "content crc16 false"
/// errcode: 5, msg: "oop result error" with terminated sensors

struct OOPCalibrationResponse: Codable {
    let errcode: Int
    let parameters: Calibration
    enum CodingKeys: String, CodingKey {
        case errcode
        case parameters = "slope"
    }
}



// https://github.com/bubbledevteam/bubble-client-swift/blob/master/LibreSensor/LibreOOPResponse.swift

// TODO: when adding URLQueryItem(name: "appName", value: "diabox")
struct GetCalibrationStatusResult: Codable {
    var status: String?
    var slopeSlope: String?
    var slopeOffset: String?
    var offsetOffset: String?
    var offsetSlope: String?
    var uuid: String?
    var isValidForFooterWithReverseCRCs: Double?

    enum CodingKeys: String, CodingKey {
        case status
        case slopeSlope = "slope_slope"
        case slopeOffset = "slope_offset"
        case offsetOffset = "offset_offset"
        case offsetSlope = "offset_slope"
        case uuid
        case isValidForFooterWithReverseCRCs = "isValidForFooterWithReverseCRCs"
    }
}


struct GlucoseSpaceActivationResponse: Codable {
    let error: Int
    let productFamily: Int
    let activationCommand: Int
    let activationPayload: String
}


func postToOOP(server: OOPServer, bytes: Data = Data(), date: Date = Date(), patchUid: SensorUid? = nil, patchInfo: PatchInfo? = nil, session: String? = "") async throws -> (Data?, URLResponse?, [URLQueryItem])  {

    var urlComponents = URLComponents(string: server.siteURL + "/" + (patchInfo == nil ? server.calibrationEndpoint! : (bytes.count > 0 ? (bytes.count > 46 ? (session == "" ? server.historyEndpoint! : server.historyAndCalibrationEndpoint!) : server.bleHistoryEndpoint!) : server.activationEndpoint!)))!

    var queryItems: [URLQueryItem] = bytes.count > 0 ? [URLQueryItem(name: "content", value: bytes.hex)] : []
    let date = Int64((date.timeIntervalSince1970 * 1000.0).rounded())
    if let patchInfo = patchInfo {
        queryItems += [
            URLQueryItem(name: "accesstoken", value: server.token),
            URLQueryItem(name: "patchUid", value: patchUid!.hex),
            URLQueryItem(name: "patchInfo", value: patchInfo.hex),
            URLQueryItem(name: "appName", value: "diabox"),
            URLQueryItem(name: "oopType", value: "OOP1AndOOP2"),
            URLQueryItem(name: "session", value: session)
        ]
        if bytes.count == 46 {
            queryItems += [
                URLQueryItem(name: "appName", value: "Diabox"),
                URLQueryItem(name: "cgmType", value: "libre2ble")
            ]
        }
    } else {
        queryItems += [
            URLQueryItem(name: "token", value: server.token),
            URLQueryItem(name: "timestamp", value: "\(date)")
            // , URLQueryItem(name: "appName", value: "diabox")
        ]
    }
    urlComponents.queryItems = queryItems
    var request = URLRequest(url: urlComponents.url!)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    let (data, urlResponse) = try await URLSession.shared.data(for: request)
    return (data, urlResponse, queryItems)
}
