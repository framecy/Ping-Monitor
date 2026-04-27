import Foundation
import AppKit

/// Manages privileged command execution with a persistent authorization session.
/// Uses a background osascript process and a FIFO (named pipe) to avoid multiple password prompts.
///
/// FIFO lives in a per-instance, mode-0700 directory under the user's private
/// temp dir (`NSTemporaryDirectory()`), with `umask 077` set before `mkfifo`.
/// This eliminates the TOCTOU window of the previous `/tmp/pingmonitor_priv_fifo`
/// implementation, where another local user could race between mkfifo and chmod
/// to inject commands into the root osascript loop.
@MainActor
final class PrivilegedManager: Sendable {
    static let shared = PrivilegedManager()

    private let privDir: String
    private let fifoPath: String
    private var runnerProcess: Process?
    private var isInitialized = false

    private init() {
        let base = NSTemporaryDirectory() as NSString
        privDir = base.appendingPathComponent("pingmonitor.\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            atPath: privDir,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
        )
        fifoPath = (privDir as NSString).appendingPathComponent("priv.fifo")
    }

    /// Initializes the privileged runner. This will trigger the osascript password prompt.
    func initialize() {
        guard !isInitialized else { return }

        setupFIFO()
        startRunner()
        isInitialized = true
        LogManager.shared.info("PrivilegedManager initialized")
    }

    private func setupFIFO() {
        if FileManager.default.fileExists(atPath: fifoPath) {
            try? FileManager.default.removeItem(atPath: fifoPath)
        }

        // umask 077 → mkfifo creates the node as 0600 atomically.
        // No chmod race window. Restored before returning.
        let oldMask = umask(0o077)
        defer { _ = umask(oldMask) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/mkfifo")
        proc.arguments = [fifoPath]
        try? proc.run()
        proc.waitUntilExit()
    }

    private func startRunner() {
        // Single-quote the FIFO path inside bash so any unusual characters in
        // NSTemporaryDirectory/UUID can't break the loop. Embedded single quotes
        // (not expected from UUID, but defensive) are escaped via '\''.
        let safeFifo = fifoPath.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        bash -c "while true; do if read cmd < '\(safeFifo)'; then if [ \\\"$cmd\\\" == \\\"exit\\\" ]; then break; fi; eval \\\"$cmd\\\"; fi; done"
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
        try? FileManager.default.removeItem(atPath: privDir)
        runnerProcess?.terminate()
        isInitialized = false
    }
    
    deinit {
        // Singleton doesn't really deinit during app lifecycle
    }
}
