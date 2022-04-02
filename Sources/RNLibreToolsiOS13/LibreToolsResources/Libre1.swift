//
//  Libre1.swift
//  LibreWrapper
//
//  Created by Yury Dymov on 4/2/22.
//

import Foundation

final class Libre1: AbstractLibre {
        
    override var type: SensorType {
        return .libre1
    }
    
    override var framBlocksToRead: Int {
        return 244
    }
    
    override var activationCommand: NFCCommand {
        return NFCCommand(code: 0xA0, parameters: backdoor, description: "activate")
    }
}
