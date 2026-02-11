import Foundation

func testLogic(customCommand: String, address: String) -> String {
    let commandString: String
    if customCommand.isEmpty {
        commandString = "ping -i 1 \(address)"
    } else if customCommand.contains("$") {
        commandString = customCommand.replacingOccurrences(of: "$address", with: address)
                                   .replacingOccurrences(of: "${address}", with: address)
    } else if customCommand.hasPrefix("ping ") && !customCommand.contains(address) {
        commandString = "\(customCommand) \(address)"
    } else {
        commandString = customCommand
    }
    return commandString
}

print("Test 1: Normal ping")
print(testLogic(customCommand: "ping -i 5 100.100.1.20", address: "100.100.1.20"))

print("\nTest 2: Implicit address append")
print(testLogic(customCommand: "ping -i 5", address: "100.100.1.20"))

print("\nTest 3: Different address")
print(testLogic(customCommand: "ping -i 5 100.100.1.20", address: "192.168.1.1"))

print("\nTest 4: Placeholder")
print(testLogic(customCommand: "ping -c 1 $address", address: "100.100.1.20"))

print("\nTest 5: Leading space")
print(testLogic(customCommand: " ping -i 5", address: "100.100.1.20"))

print("\nTest 6: Full path")
print(testLogic(customCommand: "/sbin/ping -i 5", address: "100.100.1.20"))
