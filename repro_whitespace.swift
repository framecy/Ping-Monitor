import Foundation

func testLogic(customCommand: String, addressInput: String) -> String {
    let customCommandTrimmed = customCommand.trimmingCharacters(in: .whitespacesAndNewlines)
    let address = addressInput // Simulate raw input
    
    // Logic from PingMonitorApp.swift
    let commandString: String
    if customCommandTrimmed.isEmpty {
        commandString = "ping -i 1 \(address)"
    } else {
        var result = customCommandTrimmed.replacingOccurrences(of: "$address", with: address)
                                  .replacingOccurrences(of: "${address}", with: address)
        
        // Logic from PingMonitorApp.swift
        let usedPlaceholder = customCommandTrimmed.contains("$address") || customCommandTrimmed.contains("${address}")
        
        if !usedPlaceholder && !result.contains(address) {
            result += " \(address)"
        }
        commandString = result
    }
    return commandString
}

print("Test 1: Normal ping")
print(testLogic(customCommand: "ping -i 5 223.5.5.5", addressInput: "223.5.5.5"))

print("\nTest 2: Address with trailing space")
print(testLogic(customCommand: "ping -i 5 223.5.5.5", addressInput: "223.5.5.5 "))

print("\nTest 3: Address with leading space")
print(testLogic(customCommand: "ping -i 5 223.5.5.5", addressInput: " 223.5.5.5"))

print("\nTest 4: Command with extra spaces")
print(testLogic(customCommand: "  ping -i 5 223.5.5.5  ", addressInput: "223.5.5.5"))

print("\nTest 5: Explicit placeholder with whitespace address")
print(testLogic(customCommand: "ping -i 5 $address", addressInput: "223.5.5.5 "))
