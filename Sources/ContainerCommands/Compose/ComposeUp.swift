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

extension Application.ComposeCommand {
    public struct ComposeUp: AsyncLoggableCommand {
        public init() {}

        public static let configuration = CommandConfiguration(
            commandName: "up",
            abstract: "Create and start the application's services (runs detached)")

        @Option(name: [.short, .customLong("file")], help: "Path to a Compose file")
        var file: String?

        @Option(name: [.short, .customLong("project-name")], help: "Project name (defaults to the compose file's directory)")
        var projectName: String?

        @Flag(name: .long, help: "Build images before starting the services")
        var build = false

        @Flag(name: .long, help: "Do not build images, even if a service defines a build section")
        var noBuild = false

        @Flag(name: [.short, .long], help: "Run in the background (v1 always detaches; accepted for compatibility)")
        var detach = false

        @OptionGroup
        public var logOptions: Flags.Logging

        public func run() async throws {
            let (compose, path) = try Application.ComposeCommand.load(explicitFile: file)
            let project = Application.ComposeCommand.projectName(
                explicit: projectName, fileName: compose.name, composePath: path)
            let order = try Application.ComposeCommand.topologicalOrder(services: compose.services)

            let declaredVolumes = Set((compose.volumes ?? [:]).keys)

            // Warn once about Compose keys that have no `container` equivalent yet.
            Application.ComposeCommand.warnUnsupported(services: compose.services, log: log)

            // Create named volumes up front, project-prefixed (idempotent).
            for name in declaredVolumes.sorted() {
                let prefixed = Application.ComposeCommand.prefixedVolume(project: project, volume: name)
                _ = try? Application.ComposeCommand.runContainerCLI(["volume", "create", prefixed])
            }

            // v2 still relies on default networking; custom networks (macOS 26
            // only) are not created yet.

            for service in order {
                guard let spec = compose.services[service] else { continue }

                if let buildSpec = spec.build, !noBuild, build || spec.image == nil {
                    print("Building \(service)...")
                    try Application.ComposeCommand.runContainerCLI(
                        Application.ComposeCommand.buildArguments(project: project, service: service, build: buildSpec))
                }

                print("Starting \(service)...")
                try Application.ComposeCommand.runContainerCLI(
                    Application.ComposeCommand.runArguments(
                        project: project, service: service, spec: spec, namedVolumes: declaredVolumes))
            }

            print("Started project '\(project)' (\(order.count) service(s))")
        }
    }
}
