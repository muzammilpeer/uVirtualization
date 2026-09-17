import Foundation
import Darwin
import UVCore
import UVGitLab

let environment = ProcessInfo.processInfo.environment
func loadArguments() throws -> (String, String, [String]) {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count >= 3, args[1] == "--config", ["config", "prepare", "run", "cleanup"].contains(args[0]) else {
        throw UVError("Usage: gitlab-uvm-executor config|prepare|run|cleanup --config /absolute/config.json [SCRIPT STAGE]")
    }
    guard args[2].hasPrefix("/") else { throw UVError("Use an absolute executor configuration path.") }
    return (args[0], args[2], Array(args.dropFirst(3)))
}

let task = Task {
    do {
        let (stage, path, arguments) = try loadArguments()
        let configuration = try ExecutorConfiguration.load(path)
        guard (stage == "run" && arguments.count == 2) || (stage != "run" && arguments.isEmpty) else { throw UVError("Unexpected executor stage arguments.") }
        guard let responsePath = environment["JOB_RESPONSE_FILE"] else { throw UVError("GitLab Runner must supply JOB_RESPONSE_FILE for trusted job identity.") }
        let responseURL = URL(fileURLWithPath: responsePath)
        try requireRegularFile(responseURL)
        guard (try responseURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 16_777_216 else { throw UVError("Oversized job response.") }
        let response = try Data(contentsOf: responseURL)
        if let job = try JSONSerialization.jsonObject(with: response) as? [String: Any],
           let services = job["services"] as? [Any], !services.isEmpty {
            throw UVError("GitLab services are not supported by this VM executor; use a prepared guest image without services.")
        }
        let driver = try GitLabExecutor(configuration: configuration, jobResponse: response)
        switch stage {
        case "config": FileHandle.standardOutput.write(try driver.configurationJSON() + Data([10]))
        case "prepare": try await driver.prepare()
        case "run": try await driver.run(script: arguments[0], stage: arguments[1], environment: environment)
        case "cleanup": try await driver.cleanup()
        default: throw UVError("Unknown stage.")
        }
        exit(0)
    } catch ExecutorFailure.build {
        exit(ExecutorContract.failureCode(build: true, environment: environment))
    } catch {
        UVLog.emit(error is CancellationError ? "Executor canceled; Runner cleanup will reclaim the job-owned VM." : error.localizedDescription)
        exit(ExecutorContract.failureCode(build: false, environment: environment))
    }
}
var signals: [DispatchSourceSignal] = []
for number in [SIGINT, SIGTERM] {
    signal(number, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
    source.setEventHandler { task.cancel() }
    source.resume(); signals.append(source)
}
dispatchMain()
