//===----------------------------------------------------------------------===//
// Copyright © 2025-2026 Apple Inc. and the container project authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//===----------------------------------------------------------------------===//

import ArgumentParser
import ContainerAPIClient
import ContainerizationError
import Foundation

extension Application {
    public struct ContainerTop: AsyncLoggableCommand {
        public init() {}

        public static let configuration = CommandConfiguration(
            commandName: "top",
            abstract: "Display the running processes of a container")

        @OptionGroup
        public var logOptions: Flags.Logging

        @Argument(help: "Container ID")
        var containerId: String

        @Argument(parsing: .captureForPassthrough, help: "ps options (default: -ef)")
        var psArguments: [String] = []

        public func run() async throws {
            var exitCode: Int32 = 127
            let client = ContainerClient()
            let container = try await client.get(id: containerId)
            try Application.ensureRunning(container: container)

            // `top` runs `ps` inside the container and streams its output. This
            // requires `ps` to exist in the image (busybox/procps); minimal
            // images without it will report an exec failure.
            var config = container.configuration.initProcess
            config.executable = "ps"
            config.arguments = psArguments.isEmpty ? ["-ef"] : psArguments
            config.terminal = false

            do {
                let io = try ProcessIO.create(tty: false, interactive: false, detach: false)
                defer {
                    try? io.close()
                }

                let process = try await client.createProcess(
                    containerId: container.id,
                    processId: UUID().uuidString.lowercased(),
                    configuration: config,
                    stdio: io.stdio
                )
                exitCode = try await io.handleProcess(process: process, log: log)
            } catch {
                if error is ContainerizationError {
                    throw error
                }
                throw ContainerizationError(.internalError, message: "failed to list container processes: \(error)")
            }

            if exitCode != 0 {
                throw ArgumentParser.ExitCode(exitCode)
            }
        }
    }
}
