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
import ContainerResource
import ContainerizationError
import ContainerizationOS
import Foundation

extension Application {
    public struct ContainerRestart: AsyncLoggableCommand {
        public init() {}

        public static let configuration = CommandConfiguration(
            commandName: "restart",
            abstract: "Restart one or more containers")

        @Flag(name: .shortAndLong, help: "Restart all containers")
        var all = false

        @Option(name: .shortAndLong, help: "Signal to send to the containers")
        var signal: String?

        @Option(name: .shortAndLong, help: "Seconds to wait before killing the containers")
        var time: Int32 = 5

        @OptionGroup
        public var logOptions: Flags.Logging

        @Argument(help: "Container IDs")
        var containerIds: [String] = []

        public func validate() throws {
            if containerIds.count == 0 && !all {
                throw ContainerizationError(.invalidArgument, message: "no containers specified and --all not supplied")
            }
            if containerIds.count > 0 && all {
                throw ContainerizationError(
                    .invalidArgument, message: "explicitly supplied container IDs conflict with the --all flag")
            }
        }

        public mutating func run() async throws {
            let client = ContainerClient()

            let containers: [String]
            if self.all {
                // Only currently-running containers, so `--all` does not unexpectedly
                // start containers that were previously stopped.
                let filters = ContainerListFilters(status: .running).withoutMachines()
                containers = try await client.list(filters: filters).map { $0.id }
            } else {
                containers = containerIds
            }

            let stopOptions = ContainerStopOptions(
                timeoutInSeconds: self.time,
                signal: self.signal
            )

            var errors: [any Error] = []
            for container in containers {
                do {
                    try await Self.restart(client: client, id: container, stopOptions: stopOptions)
                    print(container)
                } catch {
                    errors.append(error)
                }
            }
            if !errors.isEmpty {
                throw AggregateError(errors)
            }
        }

        /// Stop a container if it is running, then start it again detached.
        static func restart(client: ContainerClient, id: String, stopOptions: ContainerStopOptions) async throws {
            let container = try await client.get(id: id)

            if container.status == .running {
                try await client.stop(id: id, opts: stopOptions)
            }

            for mount in container.configuration.mounts where mount.isVirtiofs {
                if !FileManager.default.fileExists(atPath: mount.source) {
                    throw ContainerizationError(.invalidState, message: "mount source path '\(mount.source)' does not exist")
                }
            }

            let io = try ProcessIO.create(
                tty: container.configuration.initProcess.terminal,
                interactive: false,
                detach: true
            )
            defer {
                try? io.close()
            }

            var env: [String: String] = [:]
            if let sshAuthSock = ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"] {
                env["SSH_AUTH_SOCK"] = sshAuthSock
            }

            do {
                let process = try await client.bootstrap(id: container.id, stdio: io.stdio, dynamicEnv: env)
                try await process.start()
                try io.closeAfterStart()
            } catch {
                try? await client.stop(id: container.id)
                if error is ContainerizationError {
                    throw error
                }
                throw ContainerizationError(.internalError, message: "failed to restart container: \(error)")
            }
        }
    }
}
