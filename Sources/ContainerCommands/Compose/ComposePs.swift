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
import Foundation

extension Application.ComposeCommand {
    public struct ComposePs: AsyncLoggableCommand {
        public init() {}

        public static let configuration = CommandConfiguration(
            commandName: "ps",
            abstract: "List the application's containers")

        @Option(name: [.short, .customLong("file")], help: "Path to a Compose file")
        var file: String?

        @Option(name: [.short, .customLong("project-name")], help: "Project name (defaults to the compose file's directory)")
        var projectName: String?

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

            var rows: [[String]] = [["NAME", "SERVICE", "IMAGE", "STATE"]]
            for container in containers.sorted(by: { $0.id < $1.id }) {
                let service = container.configuration.labels[Application.ComposeCommand.serviceLabel] ?? ""
                rows.append([
                    container.id,
                    service,
                    container.configuration.image.reference,
                    container.status.rawValue,
                ])
            }
            print(TableOutput(rows: rows).format())
        }
    }
}
