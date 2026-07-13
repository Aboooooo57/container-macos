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
import Foundation

extension Application.ComposeCommand {
    public struct ComposeConfig: AsyncLoggableCommand {
        public init() {}

        public static let configuration = CommandConfiguration(
            commandName: "config",
            abstract: "Validate and inspect the Compose file")

        @Option(name: [.short, .customLong("file")], help: "Path to a Compose file")
        var file: String?

        @Option(name: [.short, .customLong("project-name")], help: "Project name")
        var projectName: String?

        @Flag(name: .long, help: "Print the service names, one per line")
        var services = false

        @Flag(name: .long, help: "Print the named volume names, one per line")
        var volumes = false

        @OptionGroup
        public var logOptions: Flags.Logging

        public func run() async throws {
            // Loading parses the file, which validates it (throws on malformed
            // YAML, dependency cycles are caught by callers that order services).
            let (compose, path) = try Application.ComposeCommand.load(explicitFile: file)
            let project = Application.ComposeCommand.projectName(
                explicit: projectName, fileName: compose.name, composePath: path)

            if services {
                for service in compose.services.keys.sorted() {
                    print(service)
                }
                return
            }
            if volumes {
                for volume in (compose.volumes ?? [:]).keys.sorted() {
                    print(volume)
                }
                return
            }

            // Default: a validated summary. Also fails the topological sort here
            // so `config` surfaces dependency cycles / unknown dependencies.
            _ = try Application.ComposeCommand.topologicalOrder(services: compose.services)
            print("project: \(project)")
            print("services:")
            for service in compose.services.keys.sorted() {
                let spec = compose.services[service]
                let image = spec?.image ?? Application.ComposeCommand.imageTag(project: project, service: service)
                let deps = spec?.dependsOn?.services.sorted() ?? []
                let depsText = deps.isEmpty ? "" : " (depends_on: \(deps.joined(separator: ", ")))"
                print("  - \(service): \(image)\(depsText)")
            }
            if let namedVolumes = compose.volumes, !namedVolumes.isEmpty {
                print("volumes: \(namedVolumes.keys.sorted().joined(separator: ", "))")
            }
        }
    }
}
