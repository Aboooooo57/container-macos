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
    public struct ContainerWait: AsyncLoggableCommand {
        public init() {}

        public static let configuration = CommandConfiguration(
            commandName: "wait",
            abstract: "Wait for one or more containers to stop, then print their exit codes")

        @OptionGroup
        public var logOptions: Flags.Logging

        @Argument(help: "Container IDs")
        var containerIds: [String] = []

        public func validate() throws {
            if containerIds.isEmpty {
                throw ContainerizationError(.invalidArgument, message: "no containers specified")
            }
        }

        public func run() async throws {
            let client = ContainerClient()

            // Wait on each container in the order given, printing exit codes as
            // they finish, matching `docker wait` semantics.
            var errors: [any Error] = []
            for id in containerIds {
                do {
                    let exitCode = try await client.wait(id: id)
                    print(exitCode)
                } catch {
                    errors.append(error)
                }
            }
            if !errors.isEmpty {
                throw AggregateError(errors)
            }
        }
    }
}
