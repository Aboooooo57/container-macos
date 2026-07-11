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
import ContainerizationError
import Foundation

extension Application {
    public struct ContainerPort: AsyncLoggableCommand {
        public init() {}

        public static let configuration = CommandConfiguration(
            commandName: "port",
            abstract: "List port mappings for a container")

        @OptionGroup
        public var logOptions: Flags.Logging

        @Argument(help: "Container ID")
        var containerId: String

        @Argument(help: "Filter to a private port, optionally with protocol (e.g. 80 or 80/tcp)")
        var privatePort: String?

        /// A single flattened host <- container mapping.
        private struct Mapping {
            let containerPort: UInt16
            let proto: String
            let hostAddress: String
            let hostPort: UInt16
        }

        public func run() async throws {
            let client = ContainerClient()
            let container = try await client.get(id: containerId)

            // Flatten every published-port spec, expanding ranges described by `count`.
            var mappings: [Mapping] = []
            for published in container.configuration.publishedPorts {
                for offset in 0..<published.count {
                    mappings.append(
                        Mapping(
                            containerPort: published.containerPort + offset,
                            proto: published.proto.rawValue,
                            hostAddress: published.hostAddress.description,
                            hostPort: published.hostPort + offset
                        )
                    )
                }
            }

            guard let privatePort else {
                // No filter: print every mapping, `<container-port>/<proto> -> <host-address>:<host-port>`.
                for mapping in mappings.sorted(by: { $0.containerPort < $1.containerPort }) {
                    print("\(mapping.containerPort)/\(mapping.proto) -> \(mapping.hostAddress):\(mapping.hostPort)")
                }
                return
            }

            // Filter form: `container port <id> <port>[/<proto>]` prints only the host binding(s).
            let (wantPort, wantProto) = try Self.parsePortFilter(privatePort)
            let matches = mappings.filter {
                $0.containerPort == wantPort && (wantProto == nil || $0.proto == wantProto)
            }
            guard !matches.isEmpty else {
                throw ContainerizationError(
                    .notFound,
                    message: "no public port '\(privatePort)' published for \(containerId)"
                )
            }
            for mapping in matches {
                print("\(mapping.hostAddress):\(mapping.hostPort)")
            }
        }

        /// Parse a `<port>` or `<port>/<proto>` filter argument.
        static func parsePortFilter(_ value: String) throws -> (port: UInt16, proto: String?) {
            let parts = value.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            guard let port = UInt16(parts[0]) else {
                throw ContainerizationError(.invalidArgument, message: "invalid port '\(value)'")
            }
            if parts.count == 2 {
                let proto = parts[1].lowercased()
                guard PublishProtocol(proto) != nil else {
                    throw ContainerizationError(.invalidArgument, message: "invalid protocol '\(parts[1])'")
                }
                return (port, proto)
            }
            return (port, nil)
        }
    }
}
