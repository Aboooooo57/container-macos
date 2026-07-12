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

import Foundation
import Yams

// A minimal Docker Compose file model. Only the fields needed to map services
// onto `container` commands are decoded; unknown keys are ignored. The custom
// decoders below handle Compose's union-typed fields (a value that may be a
// scalar, a list, or a map).

/// A YAML scalar (string / number / bool) rendered to its string form.
struct ComposeScalar: Codable {
    let string: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            string = s
        } else if let i = try? c.decode(Int.self) {
            string = String(i)
        } else if let d = try? c.decode(Double.self) {
            string = String(d)
        } else if let b = try? c.decode(Bool.self) {
            string = b ? "true" : "false"
        } else {
            string = ""
        }
    }
}

/// `key=value` pairs from either a `["K=V"]` list or a `{K: V}` map.
struct KeyValueSpec: Codable {
    let pairs: [String]
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let list = try? c.decode([String].self) {
            pairs = list
        } else {
            let map = try c.decode([String: ComposeScalar].self)
            pairs = map.map { "\($0.key)=\($0.value.string)" }.sorted()
        }
    }
}

/// A value that is either a single string or a list of strings.
struct StringOrList: Codable {
    let values: [String]
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            values = [s]
        } else {
            values = try c.decode([String].self)
        }
    }
}

/// `command` / `entrypoint`: a shell string or an explicit argument list.
struct CommandSpec: Codable {
    let args: [String]
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            // v1: naive whitespace split of the shell form.
            args = s.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        } else {
            args = try c.decode([String].self)
        }
    }
}

/// `depends_on`: a list of service names or a map keyed by service name.
struct DependsOn: Codable {
    let services: [String]
    private struct Condition: Codable {}
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let list = try? c.decode([String].self) {
            services = list
        } else {
            let map = try c.decode([String: Condition].self)
            services = Array(map.keys)
        }
    }
}

/// `build`: a context path string or an object with `context`/`dockerfile`.
struct BuildSpec: Codable {
    let context: String
    let dockerfile: String?
    private struct Object: Codable {
        let context: String?
        let dockerfile: String?
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            context = s
            dockerfile = nil
        } else {
            let obj = try c.decode(Object.self)
            context = obj.context ?? "."
            dockerfile = obj.dockerfile
        }
    }
}

/// Placeholder for top-level `volumes:`/`networks:` entries; we only need the
/// keys, so any value (a map or `null`) is accepted and ignored.
struct ComposeResourceStub: Codable {
    init(from decoder: Decoder) throws {}
}

struct ComposeService: Codable {
    var image: String?
    var build: BuildSpec?
    var command: CommandSpec?
    var entrypoint: CommandSpec?
    var ports: [String]?
    var volumes: [String]?
    var environment: KeyValueSpec?
    var envFile: StringOrList?
    var dependsOn: DependsOn?
    var containerName: String?
    var labels: KeyValueSpec?
    var restart: String?
    var workingDir: String?
    var user: String?

    enum CodingKeys: String, CodingKey {
        case image, build, command, entrypoint, ports, volumes, environment
        case envFile = "env_file"
        case dependsOn = "depends_on"
        case containerName = "container_name"
        case labels, restart
        case workingDir = "working_dir"
        case user
    }
}

struct ComposeFile: Codable {
    var name: String?
    var services: [String: ComposeService]
    var volumes: [String: ComposeResourceStub?]?
    var networks: [String: ComposeResourceStub?]?

    /// Decode a Compose file from YAML text.
    static func parse(_ yaml: String) throws -> ComposeFile {
        try YAMLDecoder().decode(ComposeFile.self, from: yaml)
    }
}
