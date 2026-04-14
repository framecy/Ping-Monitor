import Foundation
import AppKit

/// Manages privileged command execution with a persistent authorization session.
/// Uses a background osascript process and a FIFO (named pipe) to avoid multiple password prompts.
@MainActor
final class PrivilegedManager: Sendable {
    static let shared = PrivilegedManager()
    
    private let fifoPath = "/tmp/pingmonitor_priv_fifo"
    private var runnerProcess: Process?
    private var isInitialized = false
    
    private init() {}
    
    /// Initializes the privileged runner. This will trigger the osascript password prompt.
    func initialize() {
        guard !isInitialized else { return }
        
        setupFIFO()
        startRunner()
        isInitialized = true
        LogManager.shared.info("PrivilegedManager initialized")
    }
    
    private func setupFIFO() {
        // Clean up old FIFO if exists
        if FileManager.default.fileExists(atPath: fifoPath) {
            try? FileManager.default.removeItem(atPath: fifoPath)
        }
        
        // Create new FIFO
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/mkfifo")
        proc.arguments = [fifoPath]
        try? proc.run()
        proc.waitUntilExit()
        
        // Set permissions so only current user can write, but root (script) can read
        // Actually bash running as root can read anything.
        // We set 600 for current user security.
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["600", fifoPath]
        try? chmod.run()
        chmod.waitUntilExit()
    }
    
    private func startRunner() {
        // The script loop that reads from FIFO and executes as root
        // We use a robust loop that reopens the FIFO after each command (or use a persistent read)
        let script = """
        bash -c "while true; do if read cmd < \(fifoPath); then if [ \\\"$cmd\\\" == \\\"exit\\\" ]; then break; fi; eval \\\"$cmd\\\"; fi; done"
        """
        
        let osaProc = Process()
        osaProc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osaProc.arguments = ["-e", "do shell script \"\(script)\" with administrator privileges"]
        
        // Run in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                self?.runnerProcess = osaProc
                try osaProc.run()
                osaProc.waitUntilExit()
                LogManager.shared.info("Privileged runner process exited")
                self?.isInitialized = false
            } catch {
                LogManager.shared.error("Failed to start privileged runner: \(error)")
                self?.isInitialized = false
            }
        }
    }
    
    /// Runs a command with administrator privileges.
    /// - Parameter command: The bash command to run.
    func run(_ command: String) {
        if !isInitialized {
            initialize()
            // Give it a moment to start and prompt
        }
        
        // Write to FIFO
        // We use a small delay if just initialized, but usually the prompt blocks.
        // If the user hasn't authenticated yet, this write will block until the FIFO is opened for reading by the script.
        // This is exactly what we want: it waits for the privileged shell to start.
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // To prevent blocking the main thread if the runner died, we use a timeout or check process
            if let handle = FileHandle(forWritingAtPath: self.fifoPath) {
                let cmdWithNewline = command + "\n"
                if let data = cmdWithNewline.data(using: .utf8) {
                    handle.write(data)
                }
                try? handle.close()
            }
        }
    }
    
    func stop() {
        run("exit")
        try? FileManager.default.removeItem(atPath: fifoPath)
        runnerProcess?.terminate()
        isInitialized = false
    }
    
    deinit {
        // Singleton doesn't really deinit during app lifecycle
    }
}
