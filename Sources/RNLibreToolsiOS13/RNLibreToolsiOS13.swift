import Combine

public class RNLibreToolsiOS13 : RnLibreToolsProtocol {

    public static var shared : RnLibreToolsProtocol = RNLibreToolsiOS13()
    private let sensor = NFCSensor()
    private let logger = NaiveLogger()
    private let debugLevel = 0

    private init() {
    }

    var history = History()

    public func activate(completion: @escaping (Result<[[String : Bool]], LibreError>) -> Void) {
        sensor.enque(operation: NFCActivateOperation(logger: NaiveLogger(), debugLevel: debugLevel) { result in
            switch result {
            case .failure(let err): completion(.failure(err))
            case .success(let sensor): completion(.success(sensor.convertToActivateResponse()))
            }
        })
    }

    public func startSession(completion: @escaping (Result<[[String:[Double]]], LibreError>) -> Void) {
        sensor.enque(operation: NFCStartSessionOperation(logger: NaiveLogger(), debugLevel: debugLevel) { [weak self] result in
            switch result {
            case .failure(let err): completion(.failure(err))
            case .success(let sensor):
                guard let history = self?.history else { return }
                history.readDataFromSensor(sensor: sensor)
                completion(.success(sensor.convertToStartSessionResponse(history: history)))
            }
        })
    }

    public func getSensorInfo(completion: @escaping (Result<[[String: String]], LibreError>) -> Void) {
        sensor.enque(operation: NFCReadFramOperation(logger: NaiveLogger(), debugLevel: debugLevel) { result in
            switch result {
            case .failure(let err): completion(.failure(err))
            case .success(let sensor):
                do {
                    let sensorInfo = try sensor.detailFRAM()
                    let response = try sensor.convertToReadFramResponse(sensorInfo: sensorInfo)
                    self.logger.info("+++++++++++++++++++++++++++++++++++++++++++++++++++")
                    self.logger.info(response.description)
                    self.logger.info("+++++++++++++++++++++++++++++++++++++++++++++++++++")
                    completion(.success(response))
                } catch {
                   if let err = error as? LibreError {
                     completion(.failure(err))
                   } else {
                     completion(.failure(LibreError.unexpected(error.localizedDescription)))
                   }
                }
            }
        })
    }
}

@available(iOS 13.0, *)
class History: ObservableObject {
    @Published var values:        [Glucose] = []
    @Published var rawValues:     [Glucose] = []
    @Published var rawTrend:      [Glucose] = []
    @Published var factoryValues: [Glucose] = []
    @Published var factoryTrend:  [Glucose] = []
    @Published var calibratedValues: [Glucose] = []
    @Published var calibratedTrend:  [Glucose] = []
    @Published var storedValues:     [Glucose] = []
    @Published var nightscoutValues: [Glucose] = []

    func readDataFromSensor(sensor: Sensor) {
        if sensor.history.count > 0 && sensor.fram.count >= 344 {
            rawTrend = sensor.trend
            factoryTrend = sensor.factoryTrend
            rawValues = sensor.history
            factoryValues = sensor.factoryHistory
        }

        calibratedTrend = []
        calibratedValues = []
    }
}
