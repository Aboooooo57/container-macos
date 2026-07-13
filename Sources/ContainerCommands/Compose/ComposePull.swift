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
    public struct ComposePull: AsyncLoggableCommand {
        public init() {}

        public static let configuration = CommandConfiguration(
            commandName: "pull",
            abstract: "Pull images for services that reference one")

        @Option(name: [.short, .customLong("file")], help: "Path to a Compose file")
        var file: String?

        @Option(name: [.short, .customLong("project-name")], help: "Project name")
        var projectName: String?

        @OptionGroup
        public var logOptions: Flags.Logging

        public func run() async throws {
            let (compose, _) = try Application.ComposeCommand.load(explicitFile: file)

            // Unique images across services, so a shared image is pulled once.
            var images: [String] = []
            for service in compose.services.keys.sorted() {
                if let image = compose.services[service]?.image, !images.contains(image) {
                    images.append(image)
                }
            }

            if images.isEmpty {
                print("no service images to pull")
                return
            }

            for image in images {
                print("Pulling \(image)...")
                try Application.ComposeCommand.runContainerCLI(["image", "pull", image])
            }
        }
    }
}
