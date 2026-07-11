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

struct SystemInfoTests {
    private func sampleInfo() -> Application.SystemInfo.Info {
        Application.SystemInfo.Info(
            serverStatus: "running",
            cliVersion: "9.9.9",
            cliBuild: "release",
            cliCommit: "cafebabe",
            serverVersion: "8.8.8",
            serverBuild: "release",
            serverCommit: "deadbeef",
            appRoot: "/var/app",
            installRoot: "/usr/local",
            containersTotal: 5,
            containersRunning: 2,
            containersStopped: 3,
            images: 7,
            imagesSizeInBytes: 1024,
            volumes: 4,
            osVersion: "macOS 26",
            architecture: "arm64",
            cpus: 10,
            memoryInBytes: 2048
        )
    }

    @Test
    func tableIncludesVersionsAndHostDetails() {
        let table = Application.SystemInfo.infoTable(sampleInfo())
        #expect(table.contains("9.9.9"))  // CLI version
        #expect(table.contains("8.8.8"))  // server version
        #expect(table.contains("arm64"))
        #expect(table.contains("running"))
    }

    @Test
    func runningAndStoppedCountsAreOnTheCorrectRows() {
        let lines = Application.SystemInfo.infoTable(sampleInfo()).split(separator: "\n").map(String.init)
        let runningLine = lines.first { $0.contains("Running") }
        let stoppedLine = lines.first { $0.contains("Stopped") }
        // Guards against a running/stopped wiring swap.
        #expect(runningLine?.contains("2") == true)
        #expect(stoppedLine?.contains("3") == true)
    }
}
