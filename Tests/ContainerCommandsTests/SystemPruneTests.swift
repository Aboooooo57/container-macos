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

struct SystemPruneTests {
    @Test
    func defaultWarningMentionsDanglingImagesOnly() {
        let warning = Application.SystemPrune.confirmationWarning(all: false, volumes: false)
        #expect(warning.contains("all stopped containers"))
        #expect(warning.contains("all dangling images"))
        #expect(!warning.contains("without at least one container"))
        #expect(!warning.contains("volumes"))
    }

    @Test
    func allFlagWarnsAboutAllUnusedImages() {
        let warning = Application.SystemPrune.confirmationWarning(all: true, volumes: false)
        #expect(warning.contains("all images without at least one container associated to them"))
        #expect(!warning.contains("dangling"))
    }

    @Test
    func volumesFlagAddsVolumeLine() {
        let warning = Application.SystemPrune.confirmationWarning(all: false, volumes: true)
        #expect(warning.contains("all volumes not used by at least one container"))
    }

    @Test
    func volumesOmittedByDefault() {
        let warning = Application.SystemPrune.confirmationWarning(all: true, volumes: false)
        #expect(!warning.contains("volumes"))
    }
}
