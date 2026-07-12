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

// Commands are exercised through ArgumentParser's `parse`, which populates the
// argument property wrappers (including defaults). Reading those wrappers on a
// hand-constructed command is unsupported and traps.
struct ContainerWaitTests {
    @Test
    func rejectsNoContainers() {
        #expect(throws: (any Error).self) {
            let cmd = try Application.ContainerWait.parse([])
            try cmd.validate()
        }
    }

    @Test
    func acceptsOneContainer() throws {
        let cmd = try Application.ContainerWait.parse(["web"])
        try cmd.validate()  // should not throw
    }

    @Test
    func acceptsMultipleContainers() throws {
        let cmd = try Application.ContainerWait.parse(["web", "db"])
        try cmd.validate()  // should not throw
    }
}
