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
import Foundation

extension Application.ComposeCommand {
    public struct ComposeDown: AsyncLoggableCommand {
        public init() {}

        public static let configuration = CommandConfiguration(
            commandName: "down",
            abstract: "Stop and remove the application's containers")

        @Option(name: [.short, .customLong("file")], help: "Path to a Compose file")
        var file: String?

        @Option(name: [.short, .customLong("project-name")], help: "Project name (defaults to the compose file's directory)")
        var projectName: String?

        @Flag(name: [.short, .long], help: "Also remove named volumes declared in the Compose file")
        var volumes = false

        @OptionGroup
        public var logOptions: Flags.Logging

        public func run() async throws {
            let (compose, path) = try Application.ComposeCommand.load(explicitFile: file)
            let project = Application.ComposeCommand.projectName(
                explicit: projectName, fileName: compose.name, composePath: path)

            let client = ContainerClient()
            let filters = ContainerListFilters(
                labels: [Application.ComposeCommand.projectLabel: "^\(project)$"]
            ).withoutMachines()
            let containers = try await client.list(filters: filters)

            var errors: [any Error] = []
            for container in containers {
                do {
                    try await client.delete(id: container.id, force: true)
                    print("Removed \(container.id)")
                } catch {
                    errors.append(error)
                }
            }

            if volumes {
                for name in (compose.volumes ?? [:]).keys.sorted() {
                    try? Application.ComposeCommand.runContainerCLI(["volume", "delete", name])
                }
            }

            if !errors.isEmpty {
                throw AggregateError(errors)
            }
            print("Stopped project '\(project)'")
        }
    }
}
