import Foundation

protocol Logging {
    func error(_ s: String)
    func info(_ s: String)
    func warning(_ s: String)
}

public final class NaiveLogger: Logging {
    
    func error(_ s: String) {
        print("[ERR] \(s)")
    }
    
    func info(_ s: String) {
        print("[INFO] \(s)")
    }
        
    func warning(_ s: String) {
        print("[WARN] \(s)")
    }
}

public final class DummyLogger: Logging {
    func error(_ s: String) {}
    func info(_ s: String) {}
    func warning(_ s: String) {}
}
