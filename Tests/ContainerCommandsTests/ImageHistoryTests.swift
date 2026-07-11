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

import ContainerizationOCI
import Foundation
import Testing

@testable import ContainerCommands

struct ImageHistoryTests {
    @Test
    func nonEmptyLayersConsumeSizesInOrder() {
        let history = [
            History(createdBy: "ADD base", emptyLayer: false),
            History(createdBy: "RUN install", emptyLayer: false),
        ]
        let entries = Application.ImageHistory.buildEntries(history: history, layerSizes: [100, 200])
        #expect(entries.count == 2)
        #expect(entries[0].size == 100)
        #expect(entries[1].size == 200)
    }

    @Test
    func emptyLayersReportZeroAndDoNotConsumeSizes() {
        // A metadata-only record (e.g. ENV/CMD) sits between two real layers.
        let history = [
            History(createdBy: "ADD base", emptyLayer: false),
            History(createdBy: "ENV FOO=bar", emptyLayer: true),
            History(createdBy: "RUN install", emptyLayer: false),
        ]
        let entries = Application.ImageHistory.buildEntries(history: history, layerSizes: [100, 200])
        #expect(entries.map { $0.size } == [100, 0, 200])
    }

    @Test
    func missingEmptyLayerFlagTreatedAsNonEmpty() {
        let history = [History(createdBy: "ADD base")]
        let entries = Application.ImageHistory.buildEntries(history: history, layerSizes: [512])
        #expect(entries[0].size == 512)
    }

    @Test
    func fewerLayersThanRecordsFallsBackToZero() {
        let history = [
            History(createdBy: "ADD base", emptyLayer: false),
            History(createdBy: "RUN install", emptyLayer: false),
        ]
        let entries = Application.ImageHistory.buildEntries(history: history, layerSizes: [100])
        #expect(entries.map { $0.size } == [100, 0])
    }

    @Test
    func carriesThroughCreatedByAndComment() {
        let history = [History(created: "2026-01-01T00:00:00Z", createdBy: "RUN x", comment: "hi", emptyLayer: false)]
        let entries = Application.ImageHistory.buildEntries(history: history, layerSizes: [1])
        #expect(entries[0].created == "2026-01-01T00:00:00Z")
        #expect(entries[0].createdBy == "RUN x")
        #expect(entries[0].comment == "hi")
    }
}
