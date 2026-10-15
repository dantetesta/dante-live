import Foundation

@main
enum UploadProbeTests {
    @MainActor
    static func main() async throws {
        func parse(_ json: String) throws -> Double { try UploadProbe.parseMbps(from: Data(json.utf8)) }
        let ordinary = try parse("{\"ul_throughput\":12500000}")
        let fractional = try parse("{\"ul_throughput\":2500000.5,\"dl_throughput\":99999999}")
        precondition(ordinary == 12.5)
        precondition(fractional == 2.5000005)
        for invalid in ["{}", "[]", "garbage", "{\"ul_throughput\":true}",
                        "{\"ul_throughput\":\"12000000\"}", "{\"ul_throughput\":null}",
                        "{\"ul_throughput\":0}", "{\"ul_throughput\":-1}",
                        "{\"ul_throughput\":1e999}", "{\"dl_throughput\":10000000}",
                        "{\"ul_throughput\":10000000,\"error_code\":42}",
                        "{\"ul_throughput\":10000000,\"error_domain\":\"test\"}"] {
            var rejected = false
            do { _ = try parse(invalid) } catch { rejected = true }
            precondition(rejected, "Invalid fixture was accepted")
        }
        precondition(UploadProbeCommand.system.executable.path == "/usr/bin/networkQuality")
        precondition(UploadProbeCommand.system.arguments == ["-d", "-c"])

        func fixture(_ script: String, timeout: TimeInterval = 3) -> UploadProbe {
            UploadProbe(command: UploadProbeCommand(executable: URL(fileURLWithPath: "/bin/sh"),
                                                    arguments: ["-c", script]), timeout: timeout)
        }
        func wait(_ probe: UploadProbe) async throws {
            let deadline = Date().addingTimeInterval(5)
            while probe.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
            precondition(!probe.isRunning, "Own fixture process failed to finish within bound")
        }

        // More than pipe capacity on stderr must not block reading valid stdout.
        let success = fixture("i=0; while [ $i -lt 10000 ]; do printf 'fixture diagnostic only, discarded without logging\\n' >&2; i=$((i+1)); done; printf '{\"ul_throughput\":42000000}'")
        success.start()
        success.start() // overlapping start is a no-op
        try await wait(success)
        precondition(success.measuredMbps == 42 && success.measuredAt != nil && success.error == nil)

        let nonzero = fixture("printf '{\"ul_throughput\":42000000}'; exit 7")
        nonzero.start()
        try await wait(nonzero)
        precondition(nonzero.measuredMbps == nil && nonzero.error != nil)

        let timeout = fixture("exec /bin/sleep 10", timeout: 0.1)
        timeout.start()
        try await wait(timeout)
        precondition(timeout.measuredMbps == nil && timeout.error == UploadProbeFailure.timedOut.localizedDescription)

        let cancelled = fixture("exec /bin/sleep 10")
        cancelled.start()
        try await Task.sleep(for: .milliseconds(30))
        cancelled.cancel()
        precondition(cancelled.isRunning) // cancellation must wait for child teardown
        try await wait(cancelled)
        precondition(cancelled.measuredMbps == nil && cancelled.measuredAt == nil)
        precondition(cancelled.error == UploadProbeFailure.cancelled.localizedDescription)
        cancelled.start()
        cancelled.cancel() // cancellation before the child is launched is safe too
        try await wait(cancelled)
        precondition(cancelled.error == UploadProbeFailure.cancelled.localizedDescription)

        let ignoredTerminate = fixture("trap '' TERM; exec /bin/sleep 10", timeout: 0.1)
        ignoredTerminate.start()
        try await wait(ignoredTerminate)
        precondition(ignoredTerminate.error == UploadProbeFailure.timedOut.localizedDescription)

        let oversized = fixture("i=0; while [ $i -lt 30000 ]; do printf 'oversized offline fixture without personal information\\n'; i=$((i+1)); done")
        oversized.start()
        try await wait(oversized)
        precondition(oversized.error == UploadProbeFailure.outputTooLarge.localizedDescription)

        let unavailable = UploadProbe(command: UploadProbeCommand(executable: URL(fileURLWithPath: "/nonexistent/dante-offline-fixture"), arguments: []))
        unavailable.start()
        try await wait(unavailable)
        precondition(unavailable.error == UploadProbeFailure.unavailable.localizedDescription)
        print("PASS: upload parser units/errors and offline process success, stderr drain, cancellation, timeout, forced teardown, missing executable; no network measurement executed")
    }
}
