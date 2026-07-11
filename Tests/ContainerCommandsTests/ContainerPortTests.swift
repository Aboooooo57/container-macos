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

import ContainerResource
import ContainerizationExtras
import Foundation
import Testing

@testable import ContainerCommands

struct ContainerPortTests {

    // MARK: - parsePortFilter

    @Test
    func parsesBarePort() throws {
        let (port, proto) = try Application.ContainerPort.parsePortFilter("80")
        #expect(port == 80)
        #expect(proto == nil)
    }

    @Test
    func parsesPortWithProtocol() throws {
        let (port, proto) = try Application.ContainerPort.parsePortFilter("53/udp")
        #expect(port == 53)
        #expect(proto == "udp")
    }

    @Test
    func normalizesProtocolCase() throws {
        let (_, proto) = try Application.ContainerPort.parsePortFilter("443/TCP")
        #expect(proto == "tcp")
    }

    @Test
    func rejectsNonNumericPort() {
        #expect(throws: (any Error).self) {
            _ = try Application.ContainerPort.parsePortFilter("http")
        }
    }

    @Test
    func rejectsUnknownProtocol() {
        #expect(throws: (any Error).self) {
            _ = try Application.ContainerPort.parsePortFilter("80/sctp")
        }
    }

    // MARK: - mappings (range flattening)

    @Test
    func flattensSinglePort() throws {
        let ports = [
            try PublishPort(hostAddress: try IPAddress("0.0.0.0"), hostPort: 8080, containerPort: 80, proto: .tcp, count: 1)
        ]
        let mappings = Application.ContainerPort.mappings(from: ports)
        #expect(mappings.count == 1)
        #expect(mappings[0] == .init(containerPort: 80, proto: "tcp", hostAddress: "0.0.0.0", hostPort: 8080))
    }

    @Test
    func expandsPortRangeByCount() throws {
        let ports = [
            try PublishPort(hostAddress: try IPAddress("127.0.0.1"), hostPort: 5300, containerPort: 53, proto: .udp, count: 2)
        ]
        let mappings = Application.ContainerPort.mappings(from: ports)
        #expect(mappings.count == 2)
        #expect(mappings[0] == .init(containerPort: 53, proto: "udp", hostAddress: "127.0.0.1", hostPort: 5300))
        #expect(mappings[1] == .init(containerPort: 54, proto: "udp", hostAddress: "127.0.0.1", hostPort: 5301))
    }

    @Test
    func noPublishedPortsYieldsNoMappings() {
        #expect(Application.ContainerPort.mappings(from: []).isEmpty)
    }

    // MARK: - filter

    private func sampleMappings() throws -> [Application.ContainerPort.Mapping] {
        try Application.ContainerPort.mappings(from: [
            PublishPort(hostAddress: try IPAddress("0.0.0.0"), hostPort: 8080, containerPort: 80, proto: .tcp, count: 1),
            PublishPort(hostAddress: try IPAddress("0.0.0.0"), hostPort: 8443, containerPort: 80, proto: .udp, count: 1),
            PublishPort(hostAddress: try IPAddress("0.0.0.0"), hostPort: 5432, containerPort: 5432, proto: .tcp, count: 1),
        ])
    }

    @Test
    func filterByPortReturnsAllProtocols() throws {
        let matches = Application.ContainerPort.filter(try sampleMappings(), port: 80, proto: nil)
        #expect(matches.count == 2)
    }

    @Test
    func filterByPortAndProtocol() throws {
        let matches = Application.ContainerPort.filter(try sampleMappings(), port: 80, proto: "tcp")
        #expect(matches.count == 1)
        #expect(matches[0].hostPort == 8080)
    }

    @Test
    func filterWithNoMatchIsEmpty() throws {
        #expect(Application.ContainerPort.filter(try sampleMappings(), port: 9999, proto: nil).isEmpty)
    }
}
