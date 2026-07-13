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
    public struct ComposeLogs: AsyncLoggableCommand {
        public init() {}

        public static let configuration = CommandConfiguration(
            commandName: "logs",
            abstract: "Show logs from the project's containers")

        // `-f` is reserved for --follow here (matching `docker compose logs`),
        // so --file has no short form on this subcommand.
        @Option(name: .customLong("file"), help: "Path to a Compose file")
        var file: String?

        @Option(name: [.short, .customLong("project-name")], help: "Project name")
        var projectName: String?

        @Flag(name: [.short, .long], help: "Follow log output")
        var follow = false

        @OptionGroup
        public var logOptions: Flags.Logging

        public func run() async throws {
            let (compose, path) = try Application.ComposeCommand.load(explicitFile: file)
            let project = Application.ComposeCommand.projectName(
                explicit: projectName, fileName: compose.name, composePath: path)
            let ids = try await Application.ComposeCommand.projectContainerIDs(project: project)

            if ids.isEmpty {
                print("no containers for project '\(project)'")
                return
            }

            // Launch one `container logs [-f] <id>` per container concurrently and
            // wait for all. Without --follow each dumps and exits; with --follow
            // they stream until interrupted.
            var processes: [Foundation.Process] = []
            for id in ids {
                var args = ["logs"]
                if follow {
                    args.append("-f")
                }
                args.append(id)
                processes.append(try Application.ComposeCommand.startContainerCLI(args))
            }
            for process in processes {
                process.waitUntilExit()
            }
        }
    }
}
