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
    public struct ComposeExec: AsyncLoggableCommand {
        public init() {}

        public static let configuration = CommandConfiguration(
            commandName: "exec",
            abstract: "Run a command in a running service's container")

        @Option(name: [.short, .customLong("file")], help: "Path to a Compose file")
        var file: String?

        @Option(name: [.short, .customLong("project-name")], help: "Project name")
        var projectName: String?

        @Flag(name: [.short, .customLong("interactive")], help: "Keep stdin open")
        var interactive = false

        @Flag(name: [.short, .customLong("tty")], help: "Allocate a TTY")
        var tty = false

        @Argument(help: "Service name")
        var service: String

        @Argument(parsing: .captureForPassthrough, help: "Command and arguments to run")
        var command: [String]

        public func run() async throws {
            let (compose, path) = try Application.ComposeCommand.load(explicitFile: file)
            let project = Application.ComposeCommand.projectName(
                explicit: projectName, fileName: compose.name, composePath: path)

            guard let spec = compose.services[service] else {
                throw ContainerizationError(.notFound, message: "no such service: \(service)")
            }
            guard !command.isEmpty else {
                throw ContainerizationError(.invalidArgument, message: "no command specified")
            }

            let name = Application.ComposeCommand.containerName(project: project, service: service, spec: spec)
            try Application.ComposeCommand.runContainerCLI(
                Application.ComposeCommand.execArguments(
                    containerName: name, interactive: interactive, tty: tty, command: command))
        }
    }
}
