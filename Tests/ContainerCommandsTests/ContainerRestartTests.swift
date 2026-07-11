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

struct ContainerRestartTests {
    @Test
    func rejectsNoContainersAndNoAll() {
        let cmd = Application.ContainerRestart()
        #expect(throws: (any Error).self) {
            try cmd.validate()
        }
    }

    @Test
    func rejectsExplicitIdsWithAll() {
        var cmd = Application.ContainerRestart()
        cmd.all = true
        cmd.containerIds = ["web"]
        #expect(throws: (any Error).self) {
            try cmd.validate()
        }
    }

    @Test
    func acceptsExplicitIds() throws {
        var cmd = Application.ContainerRestart()
        cmd.containerIds = ["web", "db"]
        try cmd.validate()  // should not throw
    }

    @Test
    func acceptsAllFlagAlone() throws {
        var cmd = Application.ContainerRestart()
        cmd.all = true
        try cmd.validate()  // should not throw
    }
}
