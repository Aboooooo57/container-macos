//===----------------------------------------------------------------------===//
// Copyright © 2026 Apple Inc. and the container project authors.
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
import Testing

@testable import ContainerCommands

struct ComposeTests {
    private let sample = """
        services:
          web:
            build: ./web
            ports:
              - "8080:80"
            depends_on:
              - db
            environment:
              - FOO=bar
          db:
            image: postgres:16
            environment:
              POSTGRES_PASSWORD: secret
            volumes:
              - data:/var/lib/postgresql/data
        volumes:
          data:
        """

    // MARK: - Parsing (union-typed fields)

    @Test
    func parsesServicesAndUnionTypes() throws {
        let file = try ComposeFile.parse(sample)
        #expect(file.services.count == 2)

        let web = try #require(file.services["web"])
        #expect(web.build?.context == "./web")
        #expect(web.ports == ["8080:80"])
        #expect(web.dependsOn?.services == ["db"])
        #expect(web.environment?.pairs == ["FOO=bar"])

        let db = try #require(file.services["db"])
        #expect(db.image == "postgres:16")
        #expect(db.environment?.pairs == ["POSTGRES_PASSWORD=secret"])  // map form
        #expect(db.volumes == ["data:/var/lib/postgresql/data"])

        #expect(file.volumes?.keys.contains("data") == true)
    }

    @Test
    func parsesCommandStringAndListForms() throws {
        let yaml = """
            services:
              a:
                image: busybox
                command: echo hello world
              b:
                image: busybox
                command: ["echo", "hi"]
            """
        let file = try ComposeFile.parse(yaml)
        #expect(file.services["a"]?.command?.args == ["echo", "hello", "world"])
        #expect(file.services["b"]?.command?.args == ["echo", "hi"])
    }

    // MARK: - Topological ordering

    @Test
    func ordersDependenciesFirst() throws {
        let file = try ComposeFile.parse(sample)
        let order = try Application.ComposeCommand.topologicalOrder(services: file.services)
        let dbIndex = try #require(order.firstIndex(of: "db"))
        let webIndex = try #require(order.firstIndex(of: "web"))
        #expect(dbIndex < webIndex)
    }

    @Test
    func detectsDependencyCycle() throws {
        let yaml = """
            services:
              a:
                image: x
                depends_on: [b]
              b:
                image: y
                depends_on: [a]
            """
        let file = try ComposeFile.parse(yaml)
        #expect(throws: (any Error).self) {
            _ = try Application.ComposeCommand.topologicalOrder(services: file.services)
        }
    }

    @Test
    func rejectsUnknownDependency() throws {
        let yaml = """
            services:
              a:
                image: x
                depends_on: [ghost]
            """
        let file = try ComposeFile.parse(yaml)
        #expect(throws: (any Error).self) {
            _ = try Application.ComposeCommand.topologicalOrder(services: file.services)
        }
    }

    // MARK: - Argument construction

    @Test
    func runArgumentsForImageService() throws {
        let file = try ComposeFile.parse(sample)
        let db = try #require(file.services["db"])
        let args = Application.ComposeCommand.runArguments(project: "proj", service: "db", spec: db)
        #expect(
            args == [
                "run", "-d",
                "--name", "proj-db",
                "--label", "com.apple.container.compose.project=proj",
                "--label", "com.apple.container.compose.service=db",
                "-v", "data:/var/lib/postgresql/data",
                "-e", "POSTGRES_PASSWORD=secret",
                "postgres:16",
            ])
    }

    @Test
    func runArgumentsForBuiltServiceUsesGeneratedTag() throws {
        let file = try ComposeFile.parse(sample)
        let web = try #require(file.services["web"])
        let args = Application.ComposeCommand.runArguments(project: "proj", service: "web", spec: web)
        // No image: falls back to the generated build tag, and the port is published.
        #expect(args.contains("proj_web"))
        #expect(zip(args, args.dropFirst()).contains { $0 == "-p" && $1 == "8080:80" })
        #expect(args.last == "proj_web")
    }

    @Test
    func buildArgumentsUseTagAndContext() throws {
        let file = try ComposeFile.parse(sample)
        let build = try #require(file.services["web"]?.build)
        let args = Application.ComposeCommand.buildArguments(project: "proj", service: "web", build: build)
        #expect(args == ["build", "-t", "proj_web", "./web"])
    }

    // MARK: - Project naming

    @Test
    func projectNameFromDirectoryWhenNoOverride() {
        let name = Application.ComposeCommand.projectName(
            explicit: nil, fileName: nil, composePath: "/Users/me/MyApp/compose.yml")
        #expect(name == "myapp")
    }

    @Test
    func explicitProjectNameWins() {
        let name = Application.ComposeCommand.projectName(
            explicit: "Custom-1", fileName: "fromfile", composePath: "/x/y/compose.yml")
        #expect(name == "custom-1")
    }

    @Test
    func sanitizeStripsInvalidCharacters() {
        #expect(Application.ComposeCommand.sanitize("My App!2024") == "myapp2024")
    }
}
