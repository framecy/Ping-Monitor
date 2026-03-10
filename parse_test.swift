import Foundation

let output = """
COMMAND     PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
rapportd   1054 framed   13u  IPv4 0x16ded1f672846d5e      0t0  TCP *:49180 (LISTEN)
identitys  1067 framed   50u  IPv6 0x9397c008a7a78da6      0t0  TCP [fe80:19::5789:74cf:f538:1c13]:1024->[fe80:19::288a:a89c:46ab:ec59]:1024 (ESTABLISHED)
"""

let lines = output.components(separatedBy: "\n")
for line in lines.dropFirst() {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { continue }
    let parts = trimmed.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true).map(String.init)
    print(parts)
    print(parts.count)
}
