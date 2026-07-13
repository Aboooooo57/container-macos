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
    /// Apply a per-container verb (`stop`/`start`/`restart`) to every container
    /// in the project by delegating to the matching `container` command.
    static func applyLifecycle(verb: String, file: String?, projectName: String?) async throws {
        let (compose, path) = try load(explicitFile: file)
        let project = Self.projectName(explicit: projectName, fileName: compose.name, composePath: path)
        let ids = try await projectContainerIDs(project: project)
        if ids.isEmpty {
            print("no containers for project '\(project)'")
            return
        }
        for id in ids {
            _ = try? runContainerCLI([verb, id])
        }
    }

    public struct ComposeStop: AsyncLoggableCommand {
        public init() {}
        public static let configuration = CommandConfiguration(
            commandName: "stop", abstract: "Stop the project's containers without removing them")

        @Option(name: [.short, .customLong("file")], help: "Path to a Compose file")
        var file: String?
        @Option(name: [.short, .customLong("project-name")], help: "Project name")
        var projectName: String?
        @OptionGroup public var logOptions: Flags.Logging

        public func run() async throws {
            try await Application.ComposeCommand.applyLifecycle(verb: "stop", file: file, projectName: projectName)
        }
    }

    public struct ComposeStart: AsyncLoggableCommand {
        public init() {}
        public static let configuration = CommandConfiguration(
            commandName: "start", abstract: "Start the project's existing containers")

        @Option(name: [.short, .customLong("file")], help: "Path to a Compose file")
        var file: String?
        @Option(name: [.short, .customLong("project-name")], help: "Project name")
        var projectName: String?
        @OptionGroup public var logOptions: Flags.Logging

        public func run() async throws {
            try await Application.ComposeCommand.applyLifecycle(verb: "start", file: file, projectName: projectName)
        }
    }

    public struct ComposeRestart: AsyncLoggableCommand {
        public init() {}
        public static let configuration = CommandConfiguration(
            commandName: "restart", abstract: "Restart the project's containers")

        @Option(name: [.short, .customLong("file")], help: "Path to a Compose file")
        var file: String?
        @Option(name: [.short, .customLong("project-name")], help: "Project name")
        var projectName: String?
        @OptionGroup public var logOptions: Flags.Logging

        public func run() async throws {
            try await Application.ComposeCommand.applyLifecycle(verb: "restart", file: file, projectName: projectName)
        }
    }
}
