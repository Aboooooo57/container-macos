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
import ContainerVersion
import Foundation

extension Application {
    public struct SystemInfo: AsyncLoggableCommand {
        public static let configuration = CommandConfiguration(
            commandName: "info",
            abstract: "Display system-wide information"
        )

        @Option(name: .long, help: "Format of the output")
        var format: ListFormat = .table

        @OptionGroup
        public var logOptions: Flags.Logging

        public init() {}

        struct Info: Codable {
            let serverStatus: String
            let cliVersion: String
            let cliBuild: String
            let cliCommit: String
            let serverVersion: String
            let serverBuild: String
            let serverCommit: String
            let appRoot: String
            let installRoot: String
            let containersTotal: Int
            let containersRunning: Int
            let containersStopped: Int
            let images: Int
            let imagesSizeInBytes: UInt64
            let volumes: Int
            let osVersion: String
            let architecture: String
            let cpus: Int
            let memoryInBytes: UInt64
        }

        public func run() async throws {
            let cliVersion = ReleaseVersion.version()
            let cliBuild = ReleaseVersion.buildType()
            let cliCommit = ReleaseVersion.gitCommit() ?? "unspecified"

            // Server details are best-effort: `info` should still print CLI/host
            // details when the daemon is not running.
            var serverStatus = "not running"
            var serverVersion = ""
            var serverBuild = ""
            var serverCommit = ""
            var appRoot = ""
            var installRoot = ""
            if let health = try? await ClientHealthCheck.ping(timeout: .seconds(2)) {
                serverStatus = "running"
                serverVersion = health.apiServerVersion
                serverBuild = health.apiServerBuild
                serverCommit = health.apiServerCommit
                appRoot = health.appRoot.path(percentEncoded: false)
                installRoot = health.installRoot.path(percentEncoded: false)
            }

            var total = 0
            var running = 0
            var stopped = 0
            var imageCount = 0
            var imageSize: UInt64 = 0
            var volumeCount = 0
            if serverStatus == "running" {
                if let containers = try? await ContainerClient().list(filters: ContainerListFilters().withoutMachines()) {
                    total = containers.count
                    running = containers.filter { $0.status == .running }.count
                    stopped = containers.filter { $0.status == .stopped }.count
                }
                if let usage = try? await ClientDiskUsage.get() {
                    imageCount = usage.images.total
                    imageSize = usage.images.sizeInBytes
                    volumeCount = usage.volumes.total
                }
            }

            let procInfo = ProcessInfo.processInfo
            let info = Info(
                serverStatus: serverStatus,
                cliVersion: cliVersion,
                cliBuild: cliBuild,
                cliCommit: cliCommit,
                serverVersion: serverVersion,
                serverBuild: serverBuild,
                serverCommit: serverCommit,
                appRoot: appRoot,
                installRoot: installRoot,
                containersTotal: total,
                containersRunning: running,
                containersStopped: stopped,
                images: imageCount,
                imagesSizeInBytes: imageSize,
                volumes: volumeCount,
                osVersion: procInfo.operatingSystemVersionString,
                architecture: Arch.hostArchitecture().rawValue,
                cpus: procInfo.activeProcessorCount,
                memoryInBytes: procInfo.physicalMemory
            )

            try Output.render(payload: info, format: format, jsonOptions: .pretty) {
                Self.infoTable(info)
            }
        }

        private static func infoTable(_ info: Info) -> String {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let imagesSize = formatter.string(fromByteCount: Int64(info.imagesSizeInBytes))
            let memory = formatter.string(fromByteCount: Int64(info.memoryInBytes))

            let rows: [[String]] = [
                ["FIELD", "VALUE"],
                ["Server", info.serverStatus],
                ["CLI Version", info.cliVersion],
                ["CLI Build", info.cliBuild],
                ["CLI Commit", info.cliCommit],
                ["Server Version", info.serverVersion],
                ["Server Build", info.serverBuild],
                ["Server Commit", info.serverCommit],
                ["App Root", info.appRoot],
                ["Install Root", info.installRoot],
                ["Containers", "\(info.containersTotal)"],
                ["  Running", "\(info.containersRunning)"],
                ["  Stopped", "\(info.containersStopped)"],
                ["Images", "\(info.images)"],
                ["Images Size", imagesSize],
                ["Volumes", "\(info.volumes)"],
                ["Operating System", info.osVersion],
                ["Architecture", info.architecture],
                ["CPUs", "\(info.cpus)"],
                ["Total Memory", memory],
            ]
            return TableOutput(rows: rows).format()
        }
    }
}
