import Foundation

/// Runs an installed CLI off the main actor, either to completion or as a stream of output lines.
nonisolated enum CLIProcess {
    struct Result: Sendable {
        let status: Int32
        let output: String
        let error: String
    }

    /// Owns the process across queues; `Process` itself is not `Sendable`.
    private final class Handle: @unchecked Sendable {
        let process = Process()
        private let lock = NSLock()
        private var stderr = Data()

        func appendError(_ data: Data) {
            lock.withLock { stderr.append(data) }
        }

        var errorText: String {
            lock.withLock { String(decoding: stderr, as: UTF8.self) }
        }

        func terminate() {
            if process.isRunning { process.terminate() }
        }
    }

    private static let queue = DispatchQueue(
        label: "comet.cli", qos: .userInitiated, attributes: .concurrent)

    static func run(
        executable: URL, arguments: [String], workspace: URL, environment: [String: String],
        input: Data? = nil, timeout: Duration = .seconds(15)
    ) async -> Result {
        await withCheckedContinuation { continuation in
            queue.async {
                let handle = Handle()
                let stdout = Pipe()
                let stderr = Pipe()
                let stdin = Pipe()
                let process = handle.process
                process.executableURL = executable
                process.arguments = arguments
                process.currentDirectoryURL = workspace
                process.environment = environment
                process.standardOutput = stdout
                process.standardError = stderr
                process.standardInput = input == nil ? FileHandle.nullDevice : stdin
                do {
                    try process.run()
                } catch {
                    continuation.resume(
                        returning: Result(status: -1, output: "", error: error.localizedDescription))
                    return
                }
                if let input { write(input, to: stdin) }
                let seconds = Double(timeout.components.seconds)
                queue.asyncAfter(deadline: .now() + seconds) { handle.terminate() }
                stderr.fileHandleForReading.readabilityHandler = { file in
                    handle.appendError(file.availableData)
                }
                let output = stdout.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                stderr.fileHandleForReading.readabilityHandler = nil
                continuation.resume(
                    returning: Result(
                        status: process.terminationStatus,
                        output: String(decoding: output, as: UTF8.self),
                        error: handle.errorText))
            }
        }
    }

    /// Each stdout line as it arrives; a non-zero exit fails the stream with the CLI's stderr.
    static func lines(
        executable: URL, arguments: [String], workspace: URL, environment: [String: String],
        input: Data
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let handle = Handle()
            continuation.onTermination = { _ in handle.terminate() }
            queue.async {
                let stdout = Pipe()
                let stderr = Pipe()
                let stdin = Pipe()
                let process = handle.process
                process.executableURL = executable
                process.arguments = arguments
                process.currentDirectoryURL = workspace
                process.environment = environment
                process.standardOutput = stdout
                process.standardError = stderr
                process.standardInput = stdin
                stderr.fileHandleForReading.readabilityHandler = { file in
                    handle.appendError(file.availableData)
                }
                do {
                    try process.run()
                } catch {
                    continuation.finish(
                        throwing: AIProviderError.unavailable(
                            executable.lastPathComponent + " could not start: "
                                + error.localizedDescription))
                    return
                }
                // A child that exits before reading must fail the write, not SIGPIPE the app.
                _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
                write(input, to: stdin)
                var buffer = Data()
                let reader = stdout.fileHandleForReading
                while true {
                    let chunk = reader.availableData
                    if chunk.isEmpty { break }
                    buffer.append(chunk)
                    while let newline = buffer.firstIndex(of: 0x0A) {
                        let line = buffer[buffer.startIndex..<newline]
                        buffer.removeSubrange(buffer.startIndex...newline)
                        if !line.isEmpty { continuation.yield(String(decoding: line, as: UTF8.self)) }
                    }
                }
                if !buffer.isEmpty { continuation.yield(String(decoding: buffer, as: UTF8.self)) }
                process.waitUntilExit()
                stderr.fileHandleForReading.readabilityHandler = nil
                let status = process.terminationStatus
                if status != 0, process.terminationReason == .exit {
                    let detail = handle.errorText.trimmingCharacters(in: .whitespacesAndNewlines)
                    let message =
                        detail.isEmpty
                        ? executable.lastPathComponent + " exited with status \(status)."
                        : String(detail.suffix(600))
                    continuation.finish(throwing: AIProviderError.responseFailed(message))
                } else {
                    continuation.finish()
                }
            }
        }
    }

    /// Written from its own queue, so a large picture never deadlocks against unread stdout.
    private static func write(_ data: Data, to pipe: Pipe) {
        queue.async {
            let file = pipe.fileHandleForWriting
            try? file.write(contentsOf: data)
            try? file.close()
        }
    }
}
