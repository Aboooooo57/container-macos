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
    public struct ComposeBuild: AsyncLoggableCommand {
        public init() {}

        public static let configuration = CommandConfiguration(
            commandName: "build",
            abstract: "Build images for services that define a build section")

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
            let order = try Application.ComposeCommand.topologicalOrder(services: compose.services)

            var built = 0
            for service in order {
                guard let buildSpec = compose.services[service]?.build else { continue }
                print("Building \(service)...")
                try Application.ComposeCommand.runContainerCLI(
                    Application.ComposeCommand.buildArguments(project: project, service: service, build: buildSpec))
                built += 1
            }

            if built == 0 {
                print("No services with a build section to build")
            }
        }
    }
}
