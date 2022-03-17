import Foundation

class NFCSensor {
    
    func enque(operation: NFCAbstractOperation) {
        // TODO: consider implementing queue mechanism if needed
        print(operation)
        operation.start()
    }
}
