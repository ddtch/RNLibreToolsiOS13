//
//  File.swift
//  
//
//  Created by Lasha Maruashvili on 13.12.21.
//

import Foundation

public struct LibreError : Error {
    public let errorCode: Int
    public let errorMessage: String
    
    init(errorCode: Int, errorMessage: String) {
        self.errorCode = errorCode
        self.errorMessage = errorMessage
    }
    
    public static func unknown(_ msg: String) -> LibreError {
        return LibreError(errorCode: 0, errorMessage: msg)
    }
    
    public static func connectionFailed(_ msg: String) -> LibreError {
        return LibreError(errorCode: 1, errorMessage: msg)
    }
    
    public static func gettingSystemInfoFailed(_ msg: String) -> LibreError {
        return LibreError(errorCode: 2, errorMessage: msg)
    }
    
    public static func commandNotSupported(_ cmd: String) -> LibreError {
        return LibreError(errorCode: 3, errorMessage: "Command not supported: \(cmd)")
    }
    
    public static func activationError(_ msg: String) -> LibreError {
        return LibreError(errorCode: 4, errorMessage: "Activation error: \(msg)")
    }
    
    public static func readFailure(_ msg: String) -> LibreError {
        return LibreError(errorCode: 5, errorMessage: "Read error: \(msg)")
    }
    
    public static func unexpected(_ msg: String) -> LibreError {
        return LibreError(errorCode: 6, errorMessage: "Unexpected error: \(msg)")
    }
    
    public static func oop(_ msg: String) -> LibreError {
        return LibreError(errorCode: 7, errorMessage: "OOP error: \(msg)")
    }
    
    public static func dataValidation(_ msg: String) -> LibreError {
        return LibreError(errorCode: 8, errorMessage: "Data validation error: \(msg)")
    }
}
