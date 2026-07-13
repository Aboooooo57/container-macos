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
import Logging
import SystemPackage

extension Application {
    public struct ComposeCommand: AsyncLoggableCommand {
        public init() {}

        public static let configuration = CommandConfiguration(
            commandName: "compose",
            abstract: "Define and run multi-container applications from a Compose file",
            subcommands: [
                ComposeUp.self,
                ComposeDown.self,
                ComposePs.self,
                ComposeBuild.self,
                ComposeStop.self,
                ComposeStart.self,
                ComposeRestart.self,
                ComposePull.self,
                ComposeLogs.self,
                ComposeExec.self,
                ComposeConfig.self,
            ]
        )

        @OptionGroup
        public var logOptions: Flags.Logging

        // MARK: - Labels used to tag and later find a project's resources.

        static let projectLabel = "com.apple.container.compose.project"
        static let serviceLabel = "com.apple.container.compose.service"

        // MARK: - Loading

        static let defaultFileNames = ["compose.yaml", "compose.yml", "docker-compose.yaml", "docker-compose.yml"]

        /// Resolve the Compose file to use, then load and parse it. Returns the
        /// parsed file and its absolute path (used to derive the project name).
        static func load(explicitFile: String?) throws -> (file: ComposeFile, path: String) {
            let fm = FileManager.default
            let path: String
            if let explicitFile {
                guard fm.fileExists(atPath: explicitFile) else {
                    throw ContainerizationError(.notFound, message: "compose file not found: \(explicitFile)")
                }
                path = explicitFile
            } else {
                guard let found = defaultFileNames.first(where: { fm.fileExists(atPath: $0) }) else {
                    throw ContainerizationError(
                        .notFound,
                        message: "no compose file found (looked for: \(defaultFileNames.joined(separator: ", ")))"
                    )
                }
                path = found
            }
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let yaml = String(decoding: data, as: UTF8.self)
            let file = try ComposeFile.parse(yaml)
            let absolute = URL(fileURLWithPath: path).standardizedFileURL.path
            return (file, absolute)
        }

        // MARK: - Naming

        /// Determine the project name: `-p` wins, then the file's `name:`, then
        /// the sanitized parent-directory name of the compose file.
        static func projectName(explicit: String?, fileName: String?, composePath: String) -> String {
            if let explicit, !explicit.isEmpty {
                return sanitize(explicit)
            }
            if let fileName, !fileName.isEmpty {
                return sanitize(fileName)
            }
            let dir = URL(fileURLWithPath: composePath).deletingLastPathComponent().lastPathComponent
            let name = sanitize(dir)
            return name.isEmpty ? "compose" : name
        }

        /// Lowercase and strip characters that are invalid in names/labels.
        static func sanitize(_ value: String) -> String {
            String(value.lowercased().unicodeScalars.filter { s in
                (s >= "a" && s <= "z") || (s >= "0" && s <= "9") || s == "-" || s == "_"
            })
        }

        /// The image tag used for a service that declares a `build:` section.
        static func imageTag(project: String, service: String) -> String {
            "\(sanitize(project))_\(sanitize(service))"
        }

        // MARK: - Ordering

        /// Order services so that every service appears after all of its
        /// `depends_on` dependencies. Throws on cycles or unknown dependencies.
        static func topologicalOrder(services: [String: ComposeService]) throws -> [String] {
            enum Mark { case visiting, done }
            var marks: [String: Mark] = [:]
            var order: [String] = []

            func visit(_ name: String, path: [String]) throws {
                switch marks[name] {
                case .done: return
                case .visiting:
                    throw ContainerizationError(
                        .invalidArgument,
                        message: "dependency cycle detected: \((path + [name]).joined(separator: " -> "))"
                    )
                case nil:
                    break
                }
                marks[name] = .visiting
                for dep in (services[name]?.dependsOn?.services ?? []).sorted() {
                    guard services[dep] != nil else {
                        throw ContainerizationError(
                            .invalidArgument,
                            message: "service '\(name)' depends on undefined service '\(dep)'"
                        )
                    }
                    try visit(dep, path: path + [name])
                }
                marks[name] = .done
                order.append(name)
            }

            for name in services.keys.sorted() {
                try visit(name, path: [])
            }
            return order
        }

        // MARK: - Argument construction (reuse the existing container commands)

        /// `container build` arguments for a service's `build:` section.
        static func buildArguments(project: String, service: String, build: BuildSpec) -> [String] {
            var args = ["build", "-t", imageTag(project: project, service: service)]
            if let dockerfile = build.dockerfile {
                args += ["-f", dockerfile]
            }
            args.append(build.context)
            return args
        }

        /// Rewrite a service volume reference so that references to a declared
        /// named volume are prefixed with the project (`data:/x` -> `proj_data:/x`);
        /// bind mounts and anonymous volumes pass through unchanged.
        static func mapVolumeReference(_ reference: String, project: String, namedVolumes: Set<String>) -> String {
            let parts = reference.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count >= 2 else {
                return reference
            }
            let source = String(parts[0])
            guard namedVolumes.contains(source) else {
                return reference
            }
            let rest = parts.dropFirst().joined(separator: ":")
            return "\(prefixedVolume(project: project, volume: source)):\(rest)"
        }

        /// The concrete volume name a project's named volume is created under.
        static func prefixedVolume(project: String, volume: String) -> String {
            "\(sanitize(project))_\(volume)"
        }

        /// `container run -d` arguments for a service, tagged with project labels.
        static func runArguments(
            project: String, service: String, spec: ComposeService, namedVolumes: Set<String> = []
        ) -> [String] {
            var args = ["run", "-d"]
            let name = spec.containerName ?? "\(project)-\(service)"
            args += ["--name", name]
            args += ["--label", "\(projectLabel)=\(project)"]
            args += ["--label", "\(serviceLabel)=\(service)"]
            for label in spec.labels?.pairs ?? [] {
                args += ["--label", label]
            }
            for port in spec.ports ?? [] {
                args += ["-p", port]
            }
            for volume in spec.volumes ?? [] {
                args += ["-v", mapVolumeReference(volume, project: project, namedVolumes: namedVolumes)]
            }
            for env in spec.environment?.pairs ?? [] {
                args += ["-e", env]
            }
            for envFile in spec.envFile?.values ?? [] {
                args += ["--env-file", envFile]
            }
            for cap in spec.capAdd ?? [] {
                args += ["--cap-add", cap]
            }
            for cap in spec.capDrop ?? [] {
                args += ["--cap-drop", cap]
            }
            for nameserver in spec.dns?.values ?? [] {
                args += ["--dns", nameserver]
            }
            for domain in spec.dnsSearch?.values ?? [] {
                args += ["--dns-search", domain]
            }
            for tmpfs in spec.tmpfs?.values ?? [] {
                args += ["--tmpfs", tmpfs]
            }
            if let shmSize = spec.shmSize?.string {
                args += ["--shm-size", shmSize]
            }
            if let memory = spec.memLimit?.string {
                args += ["-m", memory]
            }
            // container's `--cpus` is an integer count; skip fractional values
            // rather than failing the whole `up`.
            if let cpus = spec.cpus?.string, Int64(cpus) != nil {
                args += ["-c", cpus]
            }
            if let platform = spec.platform {
                args += ["--platform", platform]
            }
            if spec.readOnly == true {
                args.append("--read-only")
            }
            if spec.initEnabled == true {
                args.append("--init")
            }
            if let workingDir = spec.workingDir {
                args += ["-w", workingDir]
            }
            if let user = spec.user {
                args += ["-u", user]
            }
            if let entrypoint = spec.entrypoint?.args, !entrypoint.isEmpty {
                args += ["--entrypoint", entrypoint.joined(separator: " ")]
            }
            args.append(spec.image ?? imageTag(project: project, service: service))
            if let command = spec.command?.args {
                args += command
            }
            return args
        }

        // MARK: - Unsupported-key warnings

        /// Emit a one-time warning for each Compose key present in the file that
        /// `container` cannot yet honor, so behavior is never silently wrong.
        static func warnUnsupported(services: [String: ComposeService], log: Logger) {
            var warnings: Set<String> = []
            for spec in services.values {
                if spec.restart != nil {
                    warnings.insert("`restart:` policies are not applied — containers are not automatically restarted")
                }
                if spec.healthcheck != nil {
                    warnings.insert("`healthcheck:` is not executed — there is no health-check subsystem")
                }
            }
            for warning in warnings.sorted() {
                log.warning("compose: \(warning)")
            }
        }

        // MARK: - Project lookup

        /// The container name a service runs under (`container_name` or `<project>-<service>`).
        static func containerName(project: String, service: String, spec: ComposeService) -> String {
            spec.containerName ?? "\(project)-\(service)"
        }

        /// IDs of all containers belonging to a project, found by project label.
        static func projectContainerIDs(project: String) async throws -> [String] {
            let client = ContainerClient()
            let filters = ContainerListFilters(labels: [projectLabel: "^\(project)$"]).withoutMachines()
            return try await client.list(filters: filters).map { $0.id }.sorted()
        }

        /// `container exec` arguments for running a command in a service's container.
        static func execArguments(
            containerName: String, interactive: Bool, tty: Bool, command: [String]
        ) -> [String] {
            var args = ["exec"]
            if interactive {
                args.append("-i")
            }
            if tty {
                args.append("-t")
            }
            args.append(containerName)
            args += command
            return args
        }

        // MARK: - Subprocess reuse of the running `container` binary

        /// Start the `container` binary without waiting; caller is responsible
        /// for `waitUntilExit()`. Used to fan out concurrent log follows.
        static func startContainerCLI(_ arguments: [String]) throws -> Foundation.Process {
            let process = Foundation.Process()
            process.executableURL = URL(fileURLWithPath: CommandLine.executablePath.string)
            process.arguments = arguments
            try process.run()
            return process
        }


        /// Run the `container` binary (the one currently executing) with the
        /// given arguments, inheriting stdio, and throw if it exits non-zero.
        @discardableResult
        static func runContainerCLI(_ arguments: [String]) throws -> Int32 {
            let binary = CommandLine.executablePath.string
            let process = Foundation.Process()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = arguments
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                throw ContainerizationError(
                    .internalError,
                    message: "`container \(arguments.joined(separator: " "))` failed with status \(process.terminationStatus)"
                )
            }
            return process.terminationStatus
        }
    }
}
