import CoreNFC
import Foundation

class SecurityManager {
    
    private var sensor: Sensor
    private let tag: NFCISO15693Tag
    private let logger: Logging
    private let debugLevel: Int
    
    private var authContext: Int?
    private var sessionInfo: Data?
    
    init(sensor: Sensor, tag: NFCISO15693Tag, toolbox: LibreToolbox) {
        self.sensor = sensor
        self.tag = tag
        self.logger = toolbox.logger
        self.debugLevel = toolbox.debugLevel
    }
    
    func performSecuritySetupIfNeeded() async {
        guard sensor.securityGeneration > 1 else { return }
        
        var commands: [NFCCommand] = [sensor.nfcCommand(.readAttribute),
                                      sensor.nfcCommand(.readChallenge)]

        if debugLevel > 0 {
            for c in 0xA0 ... 0xDF {
                commands.append(NFCCommand(code: c, parameters: Data(), description: c.hex))
            }

            // Gen2 supported commands: A1, B1, B2, B4
            // Libre 3:
            // getting 28 bytes from A1: a5 00 01 00 01 00 00 00 c0 4e 1e 0f 00 01 04 0c 01 30 34 34 5a 41 38 43 4c 36 79 38
            // getting 0xC1 error from A0, A1 20-22, A8, A9, C8, C9
            // getting 64 0xA5 bytes from A2-A7, AB-C7, CA-DF
            // getting 22 bytes from AA: 44 4f 43 34 32 37 31 35 2d 31 30 31 11 26 20 12 09 00 80 67 73 e0
            // getting zeros from standard read command 0x23
        }
        
        for cmd in commands {
            logger.info("NFC: sending \(sensor.type) '\(cmd.description)' command: code: 0x\(cmd.code.hex), parameters: \(cmd.parameters.count == 0 ? "[]" : "0x\(cmd.parameters.hex)")")
            do {
                let output = try await tag.customCommand(requestFlags: .highDataRate, customCommandCode: cmd.code, customRequestParameters: cmd.parameters)
                logger.info("NFC: '\(cmd.description)' command output (\(output.count) bytes): 0x\(output.hex)")
                if output.count == 6 { // .readAttribute
                    sensor.state = SensorState(rawValue: output[0]) ?? .unknown
                    logger.info("\(sensor.type) state: \(sensor.state.description.lowercased()) (0x\(sensor.state.rawValue.hex))")
                }
            } catch {
                logger.error("NFC: '\(cmd.description)' command error: \(error.localizedDescription) (ISO 15693 error 0x\(error.iso15693Code.hex): \(error.iso15693Description))")
            }
        }
    }
    
    func passPostSecurityChallengedIfNeeded(data: Data) async throws {
        guard sensor.securityGeneration == 2 else { return }
        
        guard let authContext = authContext,
            let sessionInfo = sessionInfo else {
                let msg = "passPostSecurityChallengedIfNeeded was called without passSecurityChallengeIfNeeded"
                logger.error(msg)
                throw LibreError.unexpected(msg)
        }
 
                            
        do {
            _ = try await postOOP(OOPServer.gen2.nfcDataAlgorithmEndpoint!, ["p1": authContext, "authData": sessionInfo.hex, "content": data.hex, "patchUid": sensor.uid.hex, "patchInfo": sensor.patchInfo.hex])
        } catch {
            logger.error("NFC: OOP error: \(error.localizedDescription)")
        }
    }
    
    func passSecurityChallengeIfNeeded() async throws {
        guard sensor.securityGeneration == 2 else { return }

        // TODO: use Gen2.communicateWithPatch(nfc: self)
        // FIXME: OOP nfcAuth endpoint still offline
        let securityChallenge = try await sensor.send(sensor.nfcCommand(.readChallenge), tag: tag)

        // FIXME: "404 Not Found"
        guard let nfcAuthEndpoint = OOPServer.gen2.nfcAuthEndpoint else {
            throw LibreError.unexpected("nfcAuthEndpoint is nil")
        }
        
        guard let nfcDataEndpoint = OOPServer.gen2.nfcDataEndpoint else {
            throw LibreError.unexpected("nfcDataEndpoint is nil")
        }
        
        _ = try await postOOP(nfcAuthEndpoint, ["patchUid": sensor.uid.hex, "authData": securityChallenge.hex])

        guard let oopResponse = try await postOOP(nfcDataEndpoint, ["patchUid": sensor.uid.hex, "authData": securityChallenge.hex]) as? OOPGen2Response else {
            throw LibreError.oop("unexpected oopResponse shape")
        }
        authContext = oopResponse.p1
        let authenticatedCommand = oopResponse.data.bytes
        logger.info("OOP: context: \(authContext), authenticated `A1 1F get session info` command: \(authenticatedCommand.hex)")
        var getSessionInfoCommand = sensor.nfcCommand(.getSessionInfo)
        getSessionInfoCommand.parameters = authenticatedCommand.suffix(authenticatedCommand.count - 3)
        let sessionInfo = try await sensor.send(getSessionInfoCommand, tag: tag)
        self.sessionInfo = sessionInfo
        // TODO: drop leading 0xA5s?
        // sessionInfo = sessionInfo.suffix(sessionInfo.count - 8)
        logger.info("NFC: session info = \(sessionInfo.hex)")
    }
    
    func testOOPActivation() async throws {
        // FIXME: await main.settings.oopServer
        let server = OOPServer.default
        logger.info("OOP: posting sensor data to \(server.siteURL)/\(server.activationEndpoint!)...")

        let (dataOptional, _, queryItems) = try await postToOOP(server: server, patchUid: sensor.uid, patchInfo: sensor.patchInfo)
        logger.info("OOP: query parameters: \(queryItems)")
        guard let data = dataOptional else { return }
        
        logger.info("OOP: server activation response: \(data.string)")
        if let oopActivationResponse = try? JSONDecoder().decode(GlucoseSpaceActivationResponse.self, from: data) {
            logger.info("OOP: activation response: \(oopActivationResponse), activation command: \(UInt8(Int16(oopActivationResponse.activationCommand) & 0xFF).hex)")
        }
//        logger.info(x"x\(sensor.type) computed activation command: \(sensor.activationCommand.code.hex.uppercased()) \(sensor.activationCommand.parameters.hex.uppercased())" )
    }
    
    private func postOOP(_ endpoint: String, _ jsonObject: Any) async throws -> Any {
        let server = OOPServer.gen2
        let jsonData = try? JSONSerialization.data(withJSONObject: jsonObject)
        var request = URLRequest(url: URL(string: "\(server.siteURL)/\(endpoint)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        do {
            logger.info("OOP: posting to \(request.url!.absoluteString) \(jsonData!.string)")
            let (data, urlResponse) = try await URLSession.shared.data(for: request)
            logger.info("OOP: response: \(data.string)")
            do {
                switch endpoint {
                case server.nfcDataEndpoint:
                    let json = try JSONDecoder().decode(OOPGen2Response.self, from: data)
                    logger.info("OOP: decoded response: \(json)")
                    return json
                case server.historyAndCalibrationA2Endpoint:
                    let json = try JSONDecoder().decode(GlucoseSpaceA2HistoryResponse.self, from: data)
                    logger.info("OOP: decoded response: \(json)")
                    return json
                default:
                    logger.warning("unhandled endpoint: \(endpoint)")
                    break
                }
            } catch {
                logger.error("OOP: error while decoding response: \(error.localizedDescription), response header: \(urlResponse.description)")
                throw LibreError.oop("failed to decode response")
            }
        } catch {
            if let err = error as? LibreError {
                throw err
            }
            
            logger.error("OOP: server error: \(error.localizedDescription)")
            throw LibreError.oop("no connection")
        }
        return ["": ""]
    }
}

