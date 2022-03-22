//
//  File.swift
//  
//
//  Created by Lasha Maruashvili on 13.12.21.
//

import Foundation


public protocol RnLibreToolsProtocol {
    func activate(completion: @escaping (Result<[[String : Bool]], LibreError>) -> Void)
    func startSession(completion: @escaping (Result<[[String:[Double]]], LibreError>) -> Void)
    func getSensorInfo(completion: @escaping (Result<[[String : String]], LibreError>) -> Void)
}
