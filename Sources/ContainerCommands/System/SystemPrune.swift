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

extension Application {
    public struct SystemPrune: AsyncLoggableCommand {
        public init() {}

        public static let configuration = CommandConfiguration(
            commandName: "prune",
            abstract: "Remove unused containers, images, and networks"
        )

        @Flag(name: .shortAndLong, help: "Remove all unused images, not just dangling ones")
        var all = false

        @Flag(name: .shortAndLong, help: "Do not prompt for confirmation")
        var force = false

        @Flag(name: .long, help: "Also prune unused volumes")
        var volumes = false

        @OptionGroup
        public var logOptions: Flags.Logging

        public func run() async throws {
            if !force {
                var warning = "WARNING! This will remove:\n"
                warning += "  - all stopped containers\n"
                warning += "  - all networks not used by at least one container\n"
                warning += all ? "  - all images without at least one container associated to them\n" : "  - all dangling images\n"
                if volumes {
                    warning += "  - all volumes not used by at least one container\n"
                }
                print(warning, terminator: "")
                print("Are you sure you want to continue? [y/N]: ", terminator: "")
                guard let answer = readLine(strippingNewline: true), answer.lowercased() == "y" else {
                    log.info("system prune cancelled")
                    return
                }
            }

            // Fan out to the existing per-resource prune commands, reusing their
            // exact deletion logic rather than duplicating it.
            print("Deleted Containers:")
            var containerPrune = ContainerPrune()
            containerPrune.logOptions = logOptions
            try await containerPrune.run()

            print("Deleted Images:")
            var imagePrune = ImagePrune()
            imagePrune.logOptions = logOptions
            imagePrune.all = all
            try await imagePrune.run()

            if #available(macOS 26, *) {
                print("Deleted Networks:")
                var networkPrune = NetworkCommand.NetworkPrune()
                networkPrune.logOptions = logOptions
                try await networkPrune.run()
            }

            if volumes {
                print("Deleted Volumes:")
                var volumePrune = VolumeCommand.VolumePrune()
                volumePrune.logOptions = logOptions
                try await volumePrune.run()
            }
        }
    }
}
