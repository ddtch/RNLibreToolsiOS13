import Foundation

class NFCSensor: NFCAbstractOperationListener {
    
    private var currentOperation: NFCAbstractOperation?
    
    func enque(operation: NFCAbstractOperation) {
        // TODO: consider implementing queue mechanism if needed
        self.currentOperation = operation
        operation.start(listener: self)
    }
    
    // MARK: - NFCAbstractOperationListener
    
    func operationCompleted(_ operation: NFCAbstractOperation) {
        currentOperation = nil
    }
}
