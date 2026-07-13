# Design: Container Health Probes (Track B1)

Status: **scoping / design** — not yet implemented.

This designs the first Track-B runtime subsystem from the parity roadmap
(`docker-parity-plan.md` §6). It adds Docker-style **health checks** to
`container`, so that a running container has a health state derived from
periodically running a probe command inside it.

## 1. Why

Health checks are the highest-leverage remaining Docker-parity feature: one
subsystem unlocks several things we currently only *warn* about or cannot do:

- `container run --health-cmd …` (and the rest of the `--health-*` flags)
- Compose `healthcheck:` (currently parsed only to emit an "unsupported" warning)
- Compose `depends_on: { condition: service_healthy }` (currently best-effort)
- A health column in `container ls` and a health block in `container inspect`
- A `health_status` event once `system events` (B3) lands

## 2. Terminology (avoid a name collision)

There is already a `HealthCheckHarness` / "health check service"
(`Sources/Services/ContainerAPIService/Server/HealthCheck/`) — that is the
**API server's own liveness** (the `ping` route), unrelated to this. To keep
them distinct, this subsystem is called **health probes** in code
(`HealthProbe`, `HealthProbeMonitor`, `HealthState`), never "health check
service".

## 3. Where the config comes from

A probe is defined by: a command, an `interval`, a `timeout`, a `retries`
count, and a `startPeriod` (grace window during which failures don't count).

Three sources, in precedence order (later overrides earlier):

1. **Image `HEALTHCHECK`** — *stretch, see §8.* Problem: the OCI
   `ContainerizationOCI.ImageConfig` struct (fetched from containerization
   0.37.0) has **no `Healthcheck` field** — Docker stores it as a non-standard
   `Healthcheck` extension in the config JSON, which the standard decode drops.
   Reading it requires custom parsing of the raw config blob. Deferred to the
   last stage so it doesn't block the rest.
2. **CLI flags** on `run`/`create`: `--health-cmd`, `--health-interval`,
   `--health-timeout`, `--health-retries`, `--health-start-period`,
   `--no-healthcheck`.
3. **Compose `healthcheck:`** — mapped by `container compose` onto the CLI
   flags above (§7).

### Model

```
public struct HealthProbeConfiguration: Sendable, Codable {
    public var test: [String]          // e.g. ["CMD", "curl", "-f", "http://localhost/"]
    public var interval: Duration      // default 30s
    public var timeout: Duration       // default 30s
    public var retries: Int            // default 3
    public var startPeriod: Duration   // default 0s
    public var disabled: Bool          // NONE / --no-healthcheck
}
```

Add `var healthProbe: HealthProbeConfiguration?` to `ContainerConfiguration`.
It already serializes across the create XPC route, so **no new route** is
needed to *deliver* the config to the daemon.

`test` follows Docker's convention: first element is `CMD` (exec form),
`CMD-SHELL` (shell string), or `NONE` (disabled).

## 4. Health state model

Health is **orthogonal** to `RuntimeStatus` (a `running` container can be
`starting`/`healthy`/`unhealthy`), so it is a separate field, not a new
`RuntimeStatus` case.

```
public enum HealthState: String, Sendable, Codable {
    case none        // no probe configured
    case starting    // within startPeriod, or no probe result yet
    case healthy
    case unhealthy
}

public struct HealthStatus: Sendable, Codable {
    public var state: HealthState
    public var failingStreak: Int
    public var log: [HealthProbeResult]   // ring buffer, last N (e.g. 5)
}

public struct HealthProbeResult: Sendable, Codable {
    public var start: Date
    public var end: Date
    public var exitCode: Int32
    public var output: String             // truncated stdout+stderr
}
```

Add `var health: HealthStatus?` to `ContainerSnapshot` so it rides the existing
`list`/`state` routes — `inspect`/`ls` get it for free, **no new query route**.

## 5. The prober (the engine)

A per-container **`HealthProbeMonitor`** (an actor), owned by the daemon and
started/stopped with the container's lifecycle.

- **Start:** when a container with a non-disabled `healthProbe` enters
  `running`, spawn a monitor task.
- **Loop:** sleep `interval`; run the probe command via the existing
  `createProcess` + `start` + `wait` path (the same machinery `exec`/`top`
  use), racing `wait` against a `timeout` (kill the probe process on timeout,
  treated as a failure).
  - exit `0` → record success, `failingStreak = 0`, state → `healthy`.
  - exit non-zero / timeout → `failingStreak += 1`; once
    `failingStreak >= retries`, state → `unhealthy`.
  - during `startPeriod`, a failure does **not** count toward the streak and
    the state stays `starting` (but a success still flips it to `healthy`).
- **Stop:** cancel the monitor when the container leaves `running`
  (stop/kill/die/delete).
- **State storage:** in-memory in the container service, keyed by container id
  (Docker also recomputes on daemon restart — persistence is not required for
  v1).

Integration point: `ContainersService` (or the per-container `RuntimeService`
actor) — it already owns start/stop transitions (`startProcess`,
`waitForExit`) where the monitor is spawned/cancelled.

## 6. Surfacing

- **`container inspect`** → add a `health` block (state, failingStreak, log).
- **`container ls`** → STATE cell shows `running (healthy)` /
  `running (unhealthy)` / `running (starting)` when a probe exists.
- **`system events`** (B3) → emit `health_status: healthy|unhealthy` on
  transitions.

## 7. Compose integration

- **Map** compose `healthcheck:` (`test`, `interval`, `timeout`, `retries`,
  `start_period`, `disable`) onto the new `--health-*` flags in
  `ComposeCommand.runArguments`. Removes the current "healthcheck not executed"
  warning.
- **`depends_on: { condition: service_healthy }`**: in `compose up`, after
  starting a dependency that has a probe, poll its `health` (via the snapshot
  the client already fetches) until `healthy` (or a deadline) before starting
  dependents. Reuses the health state — no new mechanism.

## 8. Staging (each stage builds + tests on its own)

| Stage | Deliverable | Risk |
|---|---|---|
| **B1.1** | `HealthProbeConfiguration` model + `--health-*` CLI flags on run/create, stored on `ContainerConfiguration`; shown in `inspect`. No prober yet. | low (mostly parsing; unit-testable) |
| **B1.2** | `HealthState`/`HealthStatus` model + `HealthProbeMonitor` engine in the daemon; `health` on `ContainerSnapshot`; surfaced in `inspect`. | med (daemon actor, probe exec + timeout) |
| **B1.3** | `container ls` health suffix; polish `inspect` output. | low |
| **B1.4** | Compose: map `healthcheck:` → flags; implement `service_healthy` polling in `up`. | low/med (reuses B1.2) |
| **B1.5** (stretch) | Image `HEALTHCHECK` via raw-config parsing (custom decode of the Docker `Healthcheck` extension). | med |

Recommended: land B1.1 first (pure, safe, unit-tested), then B1.2 (the engine),
then B1.3/B1.4. B1.5 is optional.

## 9. Risks & open questions

- **Concurrent exec while init runs:** the probe uses `createProcess` on a
  running container — confirm this composes with the init process (it should;
  `exec`/`top` already do). *Verify in B1.2.*
- **Probe timeout:** need to kill the probe process if it exceeds `timeout`
  (race `wait()` against a sleep; `kill` on timeout). Ensure no leaked
  processes.
- **State lifetime:** in-memory, lost on API-server restart (acceptable, matches
  Docker's recompute-on-restart).
- **`Duration` serialization:** `HealthProbeConfiguration` crosses XPC as part
  of `ContainerConfiguration`; encode durations as whole nanoseconds/seconds in
  Codable to stay stable.
- **No new XPC routes** are required for v1 — config rides `create`, state rides
  the `list`/`state` snapshot. Only add a route if per-probe streaming is wanted
  later.

## 10. Test strategy

- **Unit (daemon-free):** `--health-*` flag parsing; the state-machine
  transitions (start-period grace, streak → unhealthy, success resets streak);
  compose `healthcheck:` → flag mapping. These are pure and follow the existing
  test pattern.
- **Live (build/install/run loop):** a container with `--health-cmd` flips to
  `healthy`, a deliberately-failing probe flips to `unhealthy` after `retries`,
  and compose `service_healthy` gates a dependent's start.
