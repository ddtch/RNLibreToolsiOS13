import Foundation

protocol Logging {
    func error(_ s: String)
    func info(_ s: String)
    func warning(_ s: String)
    
    func with(prefix: String) -> Logging
}

public final class NaiveLogger: Logging {
    
    private let prefix: String
    
    init(prefix: String = "") {
        self.prefix = prefix
    }
    
    func error(_ s: String) {
        print("[ERR]\(prefix) \(s)")
    }
    
    func info(_ s: String) {
        print("[INFO]\(prefix) \(s)")
    }
        
    func warning(_ s: String) {
        print("[WARN]\(prefix) \(s)")
    }
    
    func with(prefix: String) -> Logging {
        return NaiveLogger(prefix: prefix)
    }
}

public final class DummyLogger: Logging {
    func error(_ s: String) {}
    func info(_ s: String) {}
    func warning(_ s: String) {}
    
    func with(prefix: String) -> Logging {
        return self
    }
}
