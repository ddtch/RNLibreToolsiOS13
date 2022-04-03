import AVFoundation
import Foundation
import Combine
import CoreNFC

// TODO: Localization

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

protocol NFCAbstractOperationListener: AnyObject {
    func operationCompleted(_ operation: NFCAbstractOperation)
}

class NFCAbstractOperation: NSObject, NFCTagReaderSessionDelegate {

    private weak var listener: NFCAbstractOperationListener?
    private var tagSession: NFCTagReaderSession?
    var connectedTag: NFCISO15693Tag?
    var sensor: Sensor?
    var executionStarted: Date?

    var isNFCAvailable: Bool {
        return NFCTagReaderSession.readingAvailable
    }
    
    deinit {
        var stringComponents = ["\(whoami) deinit"]
        if let executionStarted = executionStarted {
            let executionTime = Date().timeIntervalSince(executionStarted)
            stringComponents.append("execution time: \(executionTime.asString)")
        }
        
        logger.info(stringComponents.joined(separator: ", "))
    }
    
    let logger: Logging
    let completion: (Result<Sensor, LibreError>) -> Void
    let debugLevel: Int
    
    init(logger: Logging, debugLevel: Int, completion: @escaping (Result<Sensor, LibreError>) -> Void) {
        self.logger = logger.with(prefix: "[\(UUID().uuidString)]")
        self.completion = completion
        self.debugLevel = debugLevel
    }

    func start(listener: NFCAbstractOperationListener) {
        self.executionStarted = Date()
        self.listener = listener
        // execute in the .main queue because of publishing changes to main's observables
        guard let tagSession = NFCTagReaderSession(pollingOption: [.iso15693], delegate: self, queue: .main) else {
            logger.error("Failed to create NFCTagReaderSession")
            errorHandler(LibreError.unknown("Failed to create NFCTagReaderSession"))
            return
        }
        logger.info("\(whoami) started")
        self.tagSession = tagSession
        tagSession.alertMessage = "Hold the top of your iPhone near the Libre sensor until the second longer vibration"
        tagSession.begin()
    }

    public func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        logger.info("NFC: session did become active")
    }

    public func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        guard let readerError = error as? NFCReaderError else {
            logger.error("NFC tagReaderSession didInvalidateWithError: unknown error")
            let err = LibreError.unknown("Connection failure: unknown error")
            session.invalidate(errorMessage: err.errorMessage)
            errorHandler(err)
            return
        }
        
        guard readerError.code != .readerSessionInvalidationErrorUserCanceled else {
            logger.info("NFC tagReaderSession didInvalidateWithError: user cancelled")
            return
        }
        
        logger.error("NFC tagReaderSession didInvalidateWithError: \(readerError.localizedDescription)")
        let err = LibreError.connectionFailed("Connection failure: \(readerError.localizedDescription)")
        session.invalidate(errorMessage: err.errorMessage)
        errorHandler(err)
    }
    
    open func performTask(tag: NFCISO15693Tag, sensor: Sensor) async throws {
        fatalError("not implemented")
    }

    public func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        logger.info("NFC: did detect tags")

        guard let firstTag = tags.first else {
            logger.warning("No tags")
            return
        }
    
        // TODO: process more than one tag?
        guard case .iso15693(let tag) = firstTag else {
            logger.warning("Non-iso15693 tag")
            return
        }

        session.alertMessage = "Scan Complete"

        Task { [weak self] in
            do {
                try await session.connect(to: firstTag)
                self?.connectedTag = tag
            } catch {
                logger.error("NFC tagReaderSession: \(error.localizedDescription)")
                let err = LibreError.connectionFailed("Connection failure: \(error.localizedDescription)")
                session.invalidate(errorMessage: err.errorMessage)
                errorHandler(err)
                return
            }
            
            do {
                let (patchInfo, systemInfo) = try await readPatchInfo(tag: tag, withRetries: 5)
            
                let toolbox = LibreToolbox(logger: logger, debugLevel: debugLevel)
                let sensorFactory = SensorFactory(toolbox: toolbox)
                let sensor = await sensorFactory.build(tag: tag,
                                  patchInfo: patchInfo,
                                  systemInfo: systemInfo)
                            
                try await self?.performTask(tag: tag, sensor: sensor)
                session.invalidate()
                completion(.success(sensor))
                
                guard let strongSelf = self else { return }
                listener?.operationCompleted(strongSelf)
            } catch {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                session.invalidate(errorMessage: error.localizedDescription)
                if let err = error as? LibreError {
                    errorHandler(err)
                } else {
                    errorHandler(LibreError.gettingSystemInfoFailed(error.localizedDescription))
                }
            }
        }
    }
    
    private func readPatchInfo(tag: NFCISO15693Tag, withRetries: Int) async throws -> (PatchInfo, NFCISO15693SystemInfo) {
        var patchInfo: PatchInfo = Data()
        var systemInfo: NFCISO15693SystemInfo?
        var requestedRetry = 0
        var failedToScan = false
        repeat {
            failedToScan = false
            if requestedRetry > 0 {
                AudioServicesPlaySystemSound(1520)    // "pop" vibration
                logger.warning("NFC: retry # \(requestedRetry)...")
                // try await Task.sleep(nanoseconds: 250_000_000) not needed: too long
            }

            // Libre 3 workaround: calling A1 before tag.sytemInfo makes them work
            // The first reading prepends further 7 0xA5 dummy bytes
            do {
                patchInfo = Data(try await tag.customCommand(requestFlags: .highDataRate, customCommandCode: 0xA1, customRequestParameters: Data()))
                logger.info("NFC: patch info (first reading): \(patchInfo.hex) (\(patchInfo.count) bytes), string: \"\(patchInfo.string)\"")
            } catch {
                failedToScan = true
            }

            do {
                systemInfo = try await tag.systemInfo(requestFlags: .highDataRate)
                AudioServicesPlaySystemSound(1520)    // initial "pop" vibration
            } catch {
                logger.warning("NFC: error while getting system info: \(error.localizedDescription)")
                if requestedRetry > withRetries {
                    let err = LibreError.gettingSystemInfoFailed("Error while getting system info: \(error.localizedDescription)")
                    throw err
                }
                failedToScan = true
                requestedRetry += 1
            }

            do {
                patchInfo = Data(try await tag.customCommand(requestFlags: .highDataRate, customCommandCode: 0xA1, customRequestParameters: Data()))
            } catch {
                logger.warning("NFC: error while getting patch info: \(error.localizedDescription)")
                if requestedRetry > withRetries && systemInfo != nil {
                    requestedRetry = 0 // break repeat
                } else {
                    if !failedToScan {
                        failedToScan = true
                        requestedRetry += 1
                    }
                }
            }
        } while failedToScan && requestedRetry > 0
        
        guard let unwrappedSystemInfo = systemInfo else {
            logger.error("readPatchInfo: Failed to get system info")
            let err = LibreError.gettingSystemInfoFailed("Failed to get system info")
            throw err
        }
        return (patchInfo, unwrappedSystemInfo)
    }
    
    func errorHandler(_ error: LibreError) {
        completion(.failure(error))
        listener?.operationCompleted(self)
    }
}



extension Error {
    var iso15693Code: Int {
        if let code = (self as NSError).userInfo[NFCISO15693TagResponseErrorKey] as? Int {
            return code
        } else {
            return 0
        }
    }
    var iso15693Description: String { IS015693Error(rawValue: self.iso15693Code)?.description ?? "[code: 0x\(self.iso15693Code.hex)]" }
}

enum IS015693Error: Int, CustomStringConvertible {
    case none                   = 0x00
    case commandNotSupported    = 0x01
    case commandNotRecognized   = 0x02
    case optionNotSupported     = 0x03
    case unknown                = 0x0f
    case blockNotAvailable      = 0x10
    case blockAlreadyLocked     = 0x11
    case contentCannotBeChanged = 0x12

    var description: String {
        switch self {
        case .none:                   return "none"
        case .commandNotSupported:    return "command not supported"
        case .commandNotRecognized:   return "command not recognized (e.g. format error)"
        case .optionNotSupported:     return "option not supported"
        case .unknown:                return "unknown"
        case .blockNotAvailable:      return "block not available (out of range, doesn’t exist)"
        case .blockAlreadyLocked:     return "block already locked -- can’t be locked again"
        case .contentCannotBeChanged: return "block locked -- content cannot be changed"
        }
    }
}

extension AbstractLibre {

    var backdoor: Data {
        switch self.type {
        case .libre1:    return Data([0xc2, 0xad, 0x75, 0x21])
        case .libreProH: return Data([0xc2, 0xad, 0x00, 0x90])
        default:         return Data([0xde, 0xad, 0xbe, 0xef])
        }
    }

    var universalCommand: NFCCommand    { NFCCommand(code: 0xA1, description: "A1 universal prefix") }
    var getPatchInfoCommand: NFCCommand { NFCCommand(code: 0xA1, description: "get patch info") }

    // Libre 1
    var lockCommand: NFCCommand         { NFCCommand(code: 0xA2, parameters: backdoor, description: "lock") }
    var readRawCommand: NFCCommand      { NFCCommand(code: 0xA3, parameters: backdoor, description: "read raw") }
    var unlockCommand: NFCCommand       { NFCCommand(code: 0xA4, parameters: backdoor, description: "unlock") }

    // Libre 2 / Pro
    // SEE: custom commands C0-C4 in TI RF430FRL15xH Firmware User's Guide
    var readBlockCommand: NFCCommand    { NFCCommand(code: 0xB0, description: "B0 read block") }
    var readBlocksCommand: NFCCommand   { NFCCommand(code: 0xB3, description: "B3 read blocks") }

    /// replies with error 0x12 (.contentCannotBeChanged)
    var writeBlockCommand: NFCCommand   { NFCCommand(code: 0xB1, description: "B1 write block") }

    /// replies with errors 0x12 (.contentCannotBeChanged) or 0x0f (.unknown)
    /// writing three blocks is not supported because it exceeds the 32-byte input buffer
    var writeBlocksCommand: NFCCommand  { NFCCommand(code: 0xB4, description: "B4 write blocks") }

    /// Usual 1252 blocks limit:
    /// block 04e3 => error 0x11 (.blockAlreadyLocked)
    /// block 04e4 => error 0x10 (.blockNotAvailable)
    var lockBlockCommand: NFCCommand   { NFCCommand(code: 0xB2, description: "B2 lock block") }

}

fileprivate extension NFCAbstractOperation {
    
    var whoami: String {
        return NSStringFromClass(type(of: self))
    }
}

fileprivate extension TimeInterval {
    
    var asString: String {
        guard self > 0 && self < Double.infinity else {
            return "unknown"
        }
        
        let time = Int(self)
        let ms = Int((self.truncatingRemainder(dividingBy: 1)) * 1000)
        let seconds = time % 60

        return String(format: "%0.2d.%0.3d", seconds, ms)
    }
}
