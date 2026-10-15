import Combine
import CoreFoundation
import Darwin
import Foundation

/// Explicitly started upload measurement. The caller must confirm with the user
/// and reject starts during production; initialization never accesses the network.
@MainActor
final class UploadProbe: ObservableObject {
    @Published private(set) var measuredMbps: Double?
    @Published private(set) var measuredAt: Date?
    @Published private(set) var isRunning = false
    @Published private(set) var status = "Upload ainda não medido"
    @Published private(set) var error: String?

    private let command: UploadProbeCommand
    private let timeout: TimeInterval
    private var executor: UploadProbeExecutor?
    private var task: Task<Void, Never>?
    private var cancellationPending = false

    // 59 seconds plus at most 1 second for forced teardown: a 60-second budget.
    init(command: UploadProbeCommand = .system, timeout: TimeInterval = 59) {
        self.command = command
        self.timeout = timeout.isFinite ? min(max(timeout, 0.05), 59) : 59
    }

    /// Runs only the upload test. In Apple's CLI -d skips DOWNLOAD; -u skips UPLOAD.
    func start() {
        guard !isRunning else { return }
        measuredMbps = nil
        measuredAt = nil
        error = nil
        cancellationPending = false
        isRunning = true
        status = "Medindo upload…"
        let worker = UploadProbeExecutor(command: command, timeout: timeout)
        executor = worker
        task = Task { [weak self] in
            let result = await Task.detached(priority: .utility) { worker.run() }.value
            guard let self else { return }
            self.isRunning = false
            self.executor = nil
            self.task = nil
            let completedResult: Result<Double, UploadProbeFailure> = self.cancellationPending ? .failure(.cancelled) : result
            self.cancellationPending = false
            switch completedResult {
            case .success(let mbps):
                self.measuredMbps = mbps
                self.measuredAt = Date()
                self.status = "Upload medido"
            case .failure(let failure):
                self.error = failure.localizedDescription
                self.status = failure == .cancelled ? "Medição cancelada" : "Não foi possível medir o upload"
            }
        }
    }

    /// Cancellation is asynchronous; isRunning remains true until our child exits.
    func cancel() {
        guard isRunning else { return }
        status = "Cancelando medição…"
        cancellationPending = true
        executor?.cancel()
    }

    deinit { executor?.cancel() }

    /// Apple's networkQuality(8), COMPUTER OUTPUT FIELD DESCRIPTION, specifies
    /// ul_throughput in bits per second. Mbps here is decimal (1,000,000 bit/s).
    /// Raw output, interface information and remote endpoint details are not logged.
    nonisolated static func parseMbps(from data: Data) throws -> Double {
        guard data.count <= UploadProbeExecutor.maximumOutputBytes,
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            throw UploadProbeFailure.invalidOutput
        }
        // The manual says these fields appear when the test could not complete.
        if dictionary["error_code"] != nil || dictionary["error_domain"] != nil {
            throw UploadProbeFailure.reportedFailure
        }
        guard let value = dictionary["ul_throughput"] else {
            throw UploadProbeFailure.missingThroughput
        }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            throw UploadProbeFailure.invalidThroughput
        }
        let bitsPerSecond = number.doubleValue
        let mbps = bitsPerSecond / 1_000_000
        guard bitsPerSecond.isFinite, bitsPerSecond > 0, mbps.isFinite, mbps > 0 else {
            throw UploadProbeFailure.invalidThroughput
        }
        return mbps
    }
}

/// Internal injection point for offline process fixtures; production uses .system.
struct UploadProbeCommand: Sendable {
    let executable: URL
    let arguments: [String]
    static let system = UploadProbeCommand(executable: URL(fileURLWithPath: "/usr/bin/networkQuality"),
                                           arguments: ["-d", "-c"])
}

enum UploadProbeFailure: Error, LocalizedError, Equatable, Sendable {
    case unavailable, launchFailed, processFailed(Int32), timedOut, cancelled
    case invalidOutput, reportedFailure, missingThroughput, invalidThroughput, outputTooLarge

    var errorDescription: String? {
        switch self {
        case .unavailable: return "O utilitário de medição do macOS não está disponível. Informe o upload manualmente."
        case .launchFailed: return "Não foi possível iniciar o utilitário de medição. Tente novamente."
        case .processFailed(let code): return "A medição terminou com erro (código \(code)). Verifique a conexão ou informe o upload manualmente."
        case .timedOut: return "A medição excedeu o tempo limite. Tente novamente ou informe o upload manualmente."
        case .cancelled: return "A medição foi cancelada. Nenhum resultado novo foi salvo."
        case .invalidOutput: return "O macOS retornou uma resposta de medição inválida."
        case .reportedFailure: return "O macOS informou que não conseguiu concluir a medição."
        case .missingThroughput: return "A resposta do macOS não contém uma medição de upload."
        case .invalidThroughput: return "O valor de upload retornado pelo macOS não é válido."
        case .outputTooLarge: return "A resposta da medição excedeu o limite permitido."
        }
    }
}

/// The worker owns its Process exclusively. Cancellation shares only a locked
/// boolean; no process lookup, global signals, disk files or network JSON logs.
private final class UploadProbeExecutor: @unchecked Sendable {
    static let maximumOutputBytes = 1_048_576
    private let command: UploadProbeCommand
    private let timeout: TimeInterval
    private let lock = NSLock()
    private var cancellationRequested = false

    init(command: UploadProbeCommand, timeout: TimeInterval) {
        self.command = command
        self.timeout = timeout
    }

    func cancel() {
        lock.lock()
        cancellationRequested = true
        lock.unlock()
    }

    private var cancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancellationRequested
    }

    func run() -> Result<Double, UploadProbeFailure> {
        if cancelled { return .failure(.cancelled) }
        guard FileManager.default.isExecutableFile(atPath: command.executable.path) else {
            return .failure(.unavailable)
        }
        let process = Process()
        let output = Pipe()
        let diagnostics = Pipe()
        process.executableURL = command.executable
        process.arguments = command.arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = diagnostics
        let descriptors = [output.fileHandleForReading.fileDescriptor, diagnostics.fileHandleForReading.fileDescriptor]
        for descriptor in descriptors {
            let flags = fcntl(descriptor, F_GETFL)
            guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
                return .failure(.launchFailed)
            }
        }
        defer {
            try? output.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
            try? diagnostics.fileHandleForReading.close()
            try? diagnostics.fileHandleForWriting.close()
        }
        do { try process.run() } catch { return .failure(.launchFailed) }
        // Closing the parent's writers also makes EOF observable after child exit.
        try? output.fileHandleForWriting.close()
        try? diagnostics.fileHandleForWriting.close()
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        var overflow = false
        func drain(_ descriptor: Int32, capture: Bool) {
            // Bound each drain to allow timeout/cancellation even for a noisy child.
            for _ in 0..<16 {
                let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { break }
                if capture {
                    if bytes.count + count > Self.maximumOutputBytes { overflow = true }
                    else { bytes.append(contentsOf: buffer.prefix(count)) }
                }
            }
        }
        let started = ProcessInfo.processInfo.systemUptime
        var stopReason: UploadProbeFailure?
        var terminationSentAt: TimeInterval?
        while process.isRunning {
            drain(descriptors[0], capture: true)
            drain(descriptors[1], capture: false)
            let now = ProcessInfo.processInfo.systemUptime
            if stopReason == nil {
                if cancelled { stopReason = .cancelled }
                else if overflow { stopReason = .outputTooLarge }
                else if now - started >= timeout { stopReason = .timedOut }
            }
            if stopReason != nil, terminationSentAt == nil {
                process.terminate()
                terminationSentAt = now
            } else if let sent = terminationSentAt, now - sent >= 1, process.isRunning {
                // Signal only the exact child we created, never a name/PID search.
                _ = Darwin.kill(process.processIdentifier, SIGKILL)
            }
            usleep(10_000)
        }
        process.waitUntilExit()
        // Reads are nonblocking; an inherited writer cannot prevent completion.
        drain(descriptors[0], capture: true)
        drain(descriptors[1], capture: false)
        if let stopReason { return .failure(stopReason) }
        if cancelled { return .failure(.cancelled) }
        if overflow { return .failure(.outputTooLarge) }
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            return .failure(.processFailed(process.terminationStatus))
        }
        do { return .success(try UploadProbe.parseMbps(from: bytes)) }
        catch let failure as UploadProbeFailure { return .failure(failure) }
        catch { return .failure(.invalidOutput) }
    }
}
