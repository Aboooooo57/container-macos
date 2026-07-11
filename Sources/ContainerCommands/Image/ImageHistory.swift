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
import ContainerPersistence
import ContainerResource
import ContainerizationError
import ContainerizationOCI
import Foundation

extension Application {
    public struct ImageHistory: AsyncLoggableCommand {
        public init() {}

        public static let configuration = CommandConfiguration(
            commandName: "history",
            abstract: "Show the history of an image"
        )

        @Option(name: .shortAndLong, help: "Architecture of the image variant to inspect")
        var arch: String?

        @Option(help: "OS of the image variant to inspect")
        var os: String?

        @Option(help: "Platform of the image variant to inspect (format: os/arch[/variant], takes precedence over --os and --arch)")
        var platform: String?

        @Flag(name: .long, help: "Don't truncate output")
        var noTrunc = false

        @Option(name: .long, help: "Format of the output")
        var format: ListFormat = .table

        @OptionGroup
        public var logOptions: Flags.Logging

        @Argument(help: "Image name")
        var image: String

        struct HistoryEntry: Codable {
            let created: String
            let createdBy: String
            let size: Int64
            let comment: String
        }

        public func run() async throws {
            let containerSystemConfig: ContainerSystemConfig = try await Application.loadContainerSystemConfig()
            let resolvedPlatform = try DefaultPlatform.resolveWithDefaults(
                platform: platform,
                os: os ?? "linux",
                arch: arch ?? Arch.hostArchitecture().rawValue,
                log: log
            )

            let clientImage = try await ClientImage.get(reference: image, containerSystemConfig: containerSystemConfig)
            let config = try await clientImage.config(for: resolvedPlatform)
            let manifest = try await clientImage.manifest(for: resolvedPlatform)

            let layerSizes = manifest.layers.map { $0.size }
            // OCI history is ordered oldest-first; Docker displays newest-first.
            let entries = Self.buildEntries(history: config.history ?? [], layerSizes: layerSizes).reversed()

            try Output.render(payload: Array(entries), format: format, jsonOptions: .pretty) {
                Self.historyTable(Array(entries), noTrunc: noTrunc)
            }
        }

        /// Associate each history record with the size of the layer it produced.
        ///
        /// History records flagged `emptyLayer` do not correspond to a filesystem
        /// layer, so they are reported with size 0 and do not consume a layer.
        /// Non-empty records consume the next manifest layer in order.
        static func buildEntries(history: [History], layerSizes: [Int64]) -> [HistoryEntry] {
            var entries: [HistoryEntry] = []
            var layerIndex = 0
            for record in history {
                let isEmpty = record.emptyLayer ?? false
                var size: Int64 = 0
                if !isEmpty {
                    if layerIndex < layerSizes.count {
                        size = layerSizes[layerIndex]
                    }
                    layerIndex += 1
                }
                entries.append(
                    HistoryEntry(
                        created: record.created ?? "",
                        createdBy: record.createdBy ?? "",
                        size: size,
                        comment: record.comment ?? ""
                    )
                )
            }
            return entries
        }

        private static func historyTable(_ entries: [HistoryEntry], noTrunc: Bool) -> String {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file

            var rows: [[String]] = [["CREATED", "CREATED BY", "SIZE", "COMMENT"]]
            for entry in entries {
                let createdBy = noTrunc ? entry.createdBy : truncate(entry.createdBy, to: 45)
                rows.append([
                    entry.created.isEmpty ? "N/A" : entry.created,
                    createdBy,
                    formatter.string(fromByteCount: entry.size),
                    entry.comment,
                ])
            }
            return TableOutput(rows: rows).format()
        }

        static func truncate(_ value: String, to length: Int) -> String {
            guard value.count > length else {
                return value
            }
            return String(value.prefix(length - 1)) + "…"
        }
    }
}
