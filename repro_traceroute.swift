import Foundation

// --- Copy of the logic to be tested ---

struct TracerouteHop: Identifiable, Sendable {
    let id = UUID()
    let hopNumber: Int
    var hostName: String
    var ip: String
    var latencies: [Double?]
    var avgLatency: Double?
    var packetLoss: Double
    var isTimeout: Bool
}

func parseHopLine(_ line: String) -> TracerouteHop? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return nil }
    
    // 1. Hop Number
    // Must start with a number followed by space
    let range = NSRange(location: 0, length: trimmed.utf16.count)
    let hopRegex = try! NSRegularExpression(pattern: "^(\\d+)\\s+(.*)$")
    guard let match = hopRegex.firstMatch(in: trimmed, options: [], range: range) else {
        return nil
    }
    
    let hopNumRange = match.range(at: 1)
    let restRange = match.range(at: 2)
    
    guard let hopNumRangeInString = Range(hopNumRange, in: trimmed),
          let hopNumber = Int(trimmed[hopNumRangeInString]),
          let restRangeInString = Range(restRange, in: trimmed) else {
        return nil
    }
    
    // The rest of the string after the hop number
    let content = String(trimmed[restRangeInString]).trimmingCharacters(in: .whitespaces)
    
    // Tokenize by spaces
    let tokens = content.split(separator: " ").map { String($0) }
    
    var hostName = "*"
    var ip = "*"
    var latencies: [Double?] = []
    
    // State machine or token iterator
    var i = 0
    
    // 2. Try to parse Hostname/IP at the beginning
    // Heuristic: The first token(s) are likely Host/IP if they are not latencies or *
    // A latency usually looks like "12.3 ms" or "*"
    // An IP/Host usually doesn't have "ms" after it (unless it's a weird hostname)
    
    // We can iterate and consume tokens.
    // If we see "ms", the previous token was a latency.
    // If we see "*", it's a timeout latency.
    // If we see something else, it might be Host/IP or an error flag (!X)
    
    // However, Host/IP usually comes FIRST.
    // Standard formats:
    // "router (1.1.1.1)  1ms 2ms 3ms" -> Tokens: ["router", "(1.1.1.1)", "1ms", "2ms", "3ms"] (or space separated ms)
    // "1.1.1.1 (1.1.1.1)  1ms ..."
    // "1.1.1.1  1ms ..."
    
    // Let's look for the first token that looks like a latency or *.
    // Everything before that is Host/IP.
    
    var latencyStartIndex = 0
    var foundLatencyStart = false
    
    while i < tokens.count {
        let t = tokens[i]
        
        // Check if t is "*" (timeout)
        if t == "*" {
            foundLatencyStart = true
            latencyStartIndex = i
            break
        }
        
        // Check if t is a number and next is "ms"
        if let _ = Double(t), i + 1 < tokens.count, tokens[i+1] == "ms" {
            foundLatencyStart = true
            latencyStartIndex = i
            break
        }
        
        // Check if t is a number+ms (e.g. "12ms") - though usually separated
        // Check if t is strictly a float (some implementations might omit ms? unlikely for standard traceroute)
        // Actually, sometimes parsing "1.1.1.1" as Double works? No, distinct usage.
        
        i += 1
    }
    
    if foundLatencyStart {
        // Everything before i is Host/IP
        let hostTokens = tokens[0..<latencyStartIndex]
        if !hostTokens.isEmpty {
            // Join them back to parse properly
            let hostStr = hostTokens.joined(separator: " ")
            
            // Try to extract Host and IP
            // "router (1.1.1.1)"
            // "1.1.1.1"
            let ipParenRegex = try! NSRegularExpression(pattern: "^(\\S+)\\s+\\(([\\d\\.:]+)\\)")
            let simpleIpRegex = try! NSRegularExpression(pattern: "^([\\d\\.:]+)$")
            
            let hostRange = NSRange(location: 0, length: hostStr.utf16.count)
            
            if let m = ipParenRegex.firstMatch(in: hostStr, options: [], range: hostRange) {
                if let r1 = Range(m.range(at: 1), in: hostStr),
                   let r2 = Range(m.range(at: 2), in: hostStr) {
                    hostName = String(hostStr[r1])
                    ip = String(hostStr[r2])
                }
            } else if let _ = simpleIpRegex.firstMatch(in: hostStr, options: [], range: hostRange) {
                // Just IP
                hostName = hostStr
                ip = hostStr
            } else {
                // Fallback: treat whole thing as hostname
                 hostName = hostStr
                 ip = hostStr // or ""?
            }
        }
    }
    
    // 3. Parse Latencies from latencyStartIndex
    i = latencyStartIndex
    while i < tokens.count {
        let t = tokens[i]
        
        if t == "*" {
            latencies.append(nil)
            i += 1
        } else if let val = Double(t), i+1 < tokens.count, tokens[i+1] == "ms" {
            latencies.append(val)
            i += 2
        } else if t.hasPrefix("!") {
            // Error flag like !X, !N, !H
            // Usually indicates failure for the *previous* probe? Or just info?
            // " * !X" or " 10ms !X"
            // We can ignore it for simple latency parsing, or treat as a special status.
            i += 1
        } else {
            // Unknown token, maybe an IP if multiple probes hit different IPs?
            // "1.1.1.1  10ms  2.2.2.2  20ms"
            // If we encounter a new IP structure here, we might want to note it.
            // But for this simple struct, we only store one Host/IP per line.
            // We'll skip for now.
            i += 1
        }
    }

    // fallback for empty latencies if we found Host/IP but no latencies (unlikely in standard output, maybe all timeouts?)
    // If line was " 1 * * *", hostTokens is empty.
    
    
    // Calculate stats
    let validLatencies = latencies.compactMap { $0 }
    let avg = validLatencies.isEmpty ? nil : validLatencies.reduce(0, +) / Double(validLatencies.count)
    let totalProbes = max(latencies.count, 1) 
    let timeoutCount = latencies.filter { $0 == nil }.count
    
    let loss = Double(timeoutCount) / Double(totalProbes) * 100
    
    return TracerouteHop(
        hopNumber: hopNumber,
        hostName: hostName,
        ip: ip,
        latencies: latencies,
        avgLatency: avg,
        packetLoss: loss,
        isTimeout: validLatencies.isEmpty
    )
}

// --- Test Cases ---

let testLines = [
    " 1  router.local (192.168.1.1)  1.234 ms  1.456 ms  1.789 ms",
    " 2  * * *",
    " 3  10.0.0.1 (10.0.0.1)  5.678 ms  *  6.123 ms",
    " 4  172.16.0.1  10.000 ms  11.000 ms  12.000 ms",
    " 5  host-with-dashes (1.2.3.4)  20.5 ms !X  21.0 ms  22.0 ms",
    " 6  1.1.1.1  5.0 ms  2.2.2.2  6.0 ms  7.0 ms", // Multiple IPs - simplification: takes first as host
    " 7  *  10 ms  *"
]

print("Starting Tests...")
for line in testLines {
    print("---")
    print("Parsing: '\(line)'")
    if let hop = parseHopLine(line) {
        print("Hop: \(hop.hopNumber)")
        print("Host: \(hop.hostName) (\(hop.ip))")
        print("Latencies: \(hop.latencies)")
        print("Avg: \(String(describing: hop.avgLatency))")
        print("Loss: \(hop.packetLoss)%")
    } else {
        print("FAILED to parse")
    }
}
