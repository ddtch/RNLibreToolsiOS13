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
        print("session started");
        sensor.enque(operation: NFCStartSessionOperation(logger: NaiveLogger(), debugLevel: debugLevel) {
            [weak self] result in
            switch result {
            case .failure(let err): completion(.failure(err))
            case .success(let sensor):
                guard let history = self?.history else { return }
                history.readDataFromSensor(sensor: sensor)
                completion(.success(sensor.convertToStartSessionResponse(history: history)))
            }
        })
    }

    public func getSensorInfo(completion: @escaping (Result<[Any], LibreError>) -> Void) {
        sensor.enque(operation: NFCReadFramOperation(logger: NaiveLogger(), debugLevel: debugLevel) { [weak self] result in
            switch result {
            case .failure(let err): completion(.failure(err))
            case .success(let sensor):
                guard let history = self?.history else { return }
                
                history.readDataFromSensor(sensor: sensor) // TODO @ddtch: validate if needed
                completion(.success(sensor.convertToReadFramResponse()))
            }
        })
    }


    func parseSensorData(_ sensor: Sensor) throws {
        try sensor.detailFRAM()
        if sensor.history.count > 0 && sensor.fram.count >= 344 {

            let _ = sensor.calibrationInfo

            history.rawTrend = sensor.trend

            let factoryTrend = sensor.factoryTrend
            history.factoryTrend = factoryTrend
            history.rawValues = sensor.history
            let factoryHistory = sensor.factoryHistory
            history.factoryValues = factoryHistory
        }
        didParseSensor(sensor)
    }


    func applyCalibration(sensor: Sensor?) {

        history.calibratedTrend = []
        history.calibratedValues = []

    }


    func didParseSensor(_ sensor: Sensor?) {
/*
        applyCalibration(sensor: sensor)

        guard let sensor = sensor else {
            return
        }
        guard history.factoryTrend.count > 0 else { return }
        let currentGlucose = history.factoryTrend[0].value
        var trend : [Double] = history.factoryTrend.map({Double($0.value)})
        //.map({((Double($0.value) / 18.0182) * 10).rounded() / 10})
        let current = trend.remove(at: 0)
        let rawHistory: [Double] = history.factoryValues.map({Double($0.value)})//.map({((Double($0.value) / 18.0182) * 10).rounded() / 10})

        let response = [[
            "currentGluecose" : [current],
            "trendHistory" : trend,
            "history" : rawHistory
        ]]
        sessionCompletionWithTrend?(.success(response))

        if history.values.count > 0 || history.factoryValues.count > 0 {
            var entries = [Glucose]()
            if history.values.count > 0 {
                entries += self.history.values
            } else {
                entries += self.history.factoryValues
            }
            entries += history.factoryTrend.dropFirst() + [Glucose(currentGlucose, date: sensor.lastReadingDate)]
            entries = entries.filter{ $0.value > 0 && $0.id > -1 }
        }
 */
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
            factoryTrend = factoryTrend
            rawValues = sensor.history
            factoryValues = sensor.factoryHistory
        }
        
        calibratedTrend = []
        calibratedValues = []
    }
}
