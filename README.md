# RNLibreToolsiOS13

RNLibreToolsiOS framework required iOS SDK version of 13.0

Configure Xcode project

Add Near Field Communication Tag Reading capability in your tagret Signing & Capabilities tab. Add NFCReaderUsageDescription key to Info.plist and provide a usage description.

Usage

import RNLibreToolsiOS13
RNLibreToolsiOS13.shared.startSession { result in switch result { case .success(let gluecose): DispatchQueue.main.async { self.gluecoseLabel.text = "(gluecose)" } case .failure(let error): print(error.localizedDescription) } }
