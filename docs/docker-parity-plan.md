# Docker CLI Parity Plan

> Working plan for implementing Docker CLI commands/subcommands that are not
> yet supported by `container` (this repository). This document is the
> output of a command-by-command audit of the current CLI surface
> (`Sources/ContainerCommands/`, cross-checked against `docs/command-reference.md`)
> compared against the Docker Engine CLI.

## 1. Method

1. Enumerated every command file under `Sources/ContainerCommands/` and every
   documented command in `docs/command-reference.md` to get the current,
   ground-truth CLI surface (not assumptions).
2. Enumerated the standard Docker CLI command set (top-level commands and
   `docker container|image|network|volume|system` subcommands).
3. Diffed the two lists.
4. For every missing command, checked whether the backend
   (`Sources/Services/ContainerAPIService/Client/ContainerClient.swift`,
   `ClientImage.swift`, `NetworkCommand.swift`, etc.) already exposes the
   primitive needed, or whether new plumbing through the XPC service layer
   (`Sources/Services/ContainerAPIService/Server`) is required first.

**Completeness:** every subcommand of Docker's `container`, `image`,
`network`, `volume`, `system`, and `builder` management groups was walked
one-by-one (§3.1-§3.6), plus the top-level shortcut verbs (§3.7) and the
cluster/daemon surface that does not apply (§3.8). No Docker command in
those groups is left uncategorized — each is marked Have, Missing (with a
plan item), or Out of scope (with a reason).

## 2. Current command surface (as of this branch)

| Group | Commands |
|---|---|
| `container` | run, build, create, start, stop, kill, delete/rm, list/ps, exec, export, logs, inspect, stats, copy/cp, prune |
| `container image` | list/ls, pull, push, save, load, tag, delete/rm, prune, inspect |
| `container network` | create, delete/rm, prune, list/ls, inspect |
| `container volume` | create, delete/rm, prune, list/ls, inspect |
| `container builder` | start, status, stop, delete/rm |
| `container registry` | login, logout, list |
| `container machine` | create, run, list/ls, inspect, set, set-default, logs, stop, delete/rm |
| `container system` | start, stop, status, version, logs, df, dns (create/delete/list), kernel set, property list |

`container` has no orchestration layer (`compose`) — confirmed by the
uploaded research summary and by the absence of any compose parsing code in
this tree. That gap is tracked separately in §5 since it is an orchestration
tool, not a single-container primitive.

**Platform gating note:** the whole `network` command group is only
registered on macOS 26+ (`Application.swift:223-236`, `otherCommands()`).
Any new network subcommands (§3.3) inherit that same `#available(macOS 26)`
gate and must be written to compile/behave correctly on older macOS where
the group is absent.

## 3. Gap analysis vs. Docker CLI

### 3.1 `container` (maps to `docker container` / top-level shortcuts)

| Docker command | Status | Backend primitive available? | Notes |
|---|---|---|---|
| `attach` | **Missing** (known limitation) | Partial — `ContainerClient.logs()` streams output, `createProcess` exists, but there is no call that re-attaches to the *existing* init process's live stdio streams | Confirmed unsupported by an in-code comment at `ContainerStart.swift:62` ("we don't support attach currently, so we can't do `start -a` a second time"). Needs a new XPC route to fetch/redirect the running init process's stdio pipes |
| `commit` | **Missing** | No | Needs new "snapshot container rootfs → OCI image" path in `ContainerImagesService` |
| `cp` | Have (`copy`) | — | already implemented |
| `diff` | **Missing** | No | Needs filesystem diff between container's writable layer and image base snapshot |
| `pause` | **Missing** | No | Needs a freeze/thaw primitive in the runtime (cgroup freezer equivalent inside the Linux VM, or `vz` process suspend) |
| `port` | **Missing** | **Yes** — `ContainerConfiguration.publishedPorts` (`ContainerConfiguration.swift:28`) already persists every `-p` spec, retrievable via `ContainerClient.get(id:)` | CLI-only job: format the container's existing published-port list; **no new backend work** |
| `rename` | **Missing** | No | Needs an ID/name update path; container identity is currently fixed at `create` time |
| `restart` | **Missing** | No new primitive — composable from existing `stop` + `start` | Pure CLI command. Mirror `ContainerStart`'s path: `client.get(id:)` → `client.stop(id:opts:)` → `client.bootstrap(id:...)` → `process.start()` (see `ContainerStart.swift:57-99`) |
| `top` | **Missing** | No | Needs a way to list PIDs/process table inside the container (likely via `exec ps` under the hood, or a dedicated guest-agent call) |
| `unpause` | **Missing** | No | Pairs with `pause` |
| `update` | **Missing** | No | Needs live resource-limit mutation (cpu/memory) on a running container |
| `wait` | **Missing** | Partial — `ClientProcess.wait()` exists for exec'd processes | Needs the equivalent for the container's init process exit code |

### 3.2 `container image` (maps to `docker image`)

| Docker command | Status | Notes |
|---|---|---|
| `build` | Have, as top-level `container build` | equivalent, no gap |
| `history` | **Missing** | `ClientImage.config()` already returns the OCI config, which contains layer history — mostly a CLI formatting task |
| `import` | **Missing** | Needs "import a tarball as a filesystem layer" path, analogous to existing `load` but for a flat rootfs instead of an OCI archive |
| `search` | **Missing** | Needs a registry search API call (Docker Hub `/v1/search`-style); out of scope for registries that don't support it, should degrade gracefully |

### 3.3 `container network` (maps to `docker network`)

| Docker command | Status | Notes |
|---|---|---|
| `connect` | **Missing** | Needs a way to attach an additional network interface to an *already-running* container; today networks are only assigned at `run`/`create` time via `--network` |
| `disconnect` | **Missing** | Inverse of `connect` |

### 3.4 `container volume` (maps to `docker volume`)

No gaps — `create`, `inspect`, `list`, `prune`, `delete` all present. Docker
has no `volume update`/`volume connect`, so parity is complete here.

### 3.5 `container builder` (maps to `docker builder`)

| Docker command | Status | Notes |
|---|---|---|
| `prune` | **Missing** | The builder group only has `start`/`status`/`stop`/`delete` (`Builder.swift:28-33`); there is no build-cache prune command and no cache-GC plumbing anywhere in `Sources/ContainerBuild` or the service layer. Docker's `docker builder prune` reclaims BuildKit cache. Needs a new route into the (BuildKit-based) builder to trigger cache GC |

### 3.6 `container system` (maps to `docker system`)

| Docker command | Status | Notes |
|---|---|---|
| `prune` | **Missing** | Docker's `system prune` is a convenience wrapper that fans out to container/image/network/volume prune; all four underlying primitives already exist in this repo |
| `info` | **Missing** | Needs to aggregate host/VM/runtime info that's scattered across `system status`, `system version`, `system df` today into one Docker-style summary |
| `events` | **Missing** | Needs an event bus/stream (container lifecycle events) — no such subsystem exists today; this is the largest system-level gap |

### 3.7 Top-level invocation aliases (minor UX parity, optional)

These are not missing capabilities, just different invocation paths from
Docker. Listed for completeness so they aren't mistaken for gaps:

- `docker login` / `docker logout` → available here as `container registry
  login` / `container registry logout`. Top-level aliases could be added but
  the functionality exists.
- `docker inspect` (polymorphic, any object) → here inspect is per-resource
  (`container inspect`, `container image inspect`, `container network
  inspect`, `container volume inspect`, `container machine inspect`). A
  unified top-level `inspect` is a convenience, not a capability gap.
- `docker images` / `docker ps` / `docker rmi` shortcuts → provided as
  `container image list`/`container list`/`container image delete` (with
  `ls`/`rm` aliases already present).

### 3.8 Explicitly out of scope

These Docker commands are **not** applicable to `container` and are excluded
from this plan, because `container` is a single-host runtime with no
orchestrator/daemon-cluster concept (same conclusion the uploaded research
doc reaches for compose, just extended to the rest of the cluster surface):

- `docker swarm`, `docker node`, `docker service`, `docker stack`,
  `docker secret`, `docker config` — all Swarm-mode only.
- `docker context` — multi-daemon context switching; `container` is
  single-daemon per host.
- `docker plugin` — Docker Engine plugin API, not applicable to this runtime.
- `docker checkpoint` — experimental CRIU-based checkpoint/restore; would
  require its own research spike, not a straightforward CLI gap.
- `docker trust`/`docker manifest` — Notary/manifest-list tooling; could be
  revisited later but isn't part of the core single-container workflow gap.
- `docker compose` — **in scope**, but as its own orchestration effort with
  a full design in Phase 5 / §4 item #19 (covers the popular
  `docker compose -f … up --build` workflow). Listed here only to note it is
  not a single-container primitive like the rest of §3.

## 4. Implementation plan

Phased by (a) how much of the backend already exists and (b) how close the
result gets to full Docker parity for everyday single-container workflows.

### Phase 1 — CLI-only, no backend changes (low risk, fast wins)

1. **`container restart`** — ✅ **implemented** in `ContainerCommands/Container/ContainerRestart.swift`; composes `ContainerClient.stop(id:opts:)` then re-starts via the detached path from `ContainerStart`. Mirrors `ContainerStop`'s `--all`/`--time`/`--signal` flags. Registered in `Application.swift`, documented in `docs/command-reference.md`.
2. **`container port`** — ✅ **implemented** in `ContainerCommands/Container/ContainerPort.swift`; reads `configuration.publishedPorts` via `ContainerClient.get(id:)`, flattens `count` ranges, prints `containerPort/proto -> hostAddress:hostPort` (or filters by `PORT[/PROTO]`). Registered in `Application.swift`, documented, unit-tested (`Tests/ContainerCommandsTests/ContainerPortTests.swift`).

> Note: implementation was authored against the observed source APIs but
> **not compiled** — this repo targets macOS 15+ and depends on
> Virtualization/XPC/Darwin, so it cannot build in the Linux CI sandbox used
> for this change. A `swift build` + `swift test` on macOS is required before
> merge.
3. **`container system prune`** — ✅ **implemented** in `ContainerCommands/System/SystemPrune.swift`. Fans out to the existing `ContainerPrune`/`ImagePrune`/`NetworkPrune`/`VolumePrune` commands (constructs each and calls `run()`, so the deletion logic is reused, not duplicated), gated by a confirmation prompt with `-f/--force`, `-a/--all` (all unused images), and `--volumes`. Network pruning is guarded by `#available(macOS 26)`. Registered + documented.
4. **`container image history`** — ✅ **implemented** in `ContainerCommands/Image/ImageHistory.swift`, built from `ClientImage.config(for:)` (OCI `history`) + `manifest(for:)` (layer sizes). Maps non-empty history records to layers in order, prints newest-first with `--no-trunc`/`--format`/platform flags. Registered, documented, unit-tested (`Tests/ContainerCommandsTests/ImageHistoryTests.swift`).
5. **`container system info`** — ✅ **implemented** in `ContainerCommands/System/SystemInfo.swift`; aggregates `ClientHealthCheck` (server/version/roots), `ContainerClient.list` (container counts), `ClientDiskUsage` (image/volume counts + size), and `ProcessInfo`/`Arch` (host OS/arch/CPU/memory) into one view. Degrades gracefully when the daemon is down. Registered + documented.

> **Phase 1 complete.** All five commands authored against verified source
> APIs (OCI `History`/`Manifest` fields confirmed against the pinned
> `containerization` 0.37.0 tag). Still **not compiled** — needs
> `swift build && swift test` on macOS before merge, per the note above.
>
> **Test coverage.** Each command's real logic was extracted into pure static
> helpers and unit-tested **without needing the daemon** (run with
> `swift test --filter ContainerCommandsTests`):
> - `restart` → `validate()` argument rules (`ContainerRestartTests`)
> - `port` → `parsePortFilter`, `mappings` (range flattening), `filter`
>   (`ContainerPortTests`)
> - `system prune` → `confirmationWarning` flag wiring (`SystemPruneTests`)
> - `system info` → `infoTable` field/row wiring, incl. a running/stopped
>   swap guard (`SystemInfoTests`)
> - `image history` → `buildEntries` (layer↔record mapping) and `truncate`
>   (`ImageHistoryTests`)

### Phase 2 — Small backend additions (new XPC route, existing service processes)

6. **`container wait`** — ✅ **implemented**. During implementation the audit found the `containerWait` XPC route **already exists and is registered** (`XPC+.swift`, `APIServer+Start.swift:303`), and the init process shares the container ID (`ContainersService.swift:598`; `kill` uses `processIdentifier = id`). So **no new route was needed** — only a `ContainerClient.wait(id:)` method (reusing the route with `processIdentifier = id`) and a `ContainerCommands/Container/ContainerWait.swift` command that waits on each container and prints its exit code, `docker wait`-style. Registered, documented, validate() unit-tested. Known limit: waiting on a container whose runtime is already gone may error rather than return a cached code.

> **Remaining Phase 2 items (#7-#10) are genuinely multi-layer** — each needs
> a *new* XPC route plus a server-side handler (and for some, runtime/plugin
> changes), unlike #6 which reused existing plumbing. They are best done one
> at a time with a compile/test cycle in the loop rather than authored blind.
> Difficulty, hardest last:
> - **#9 `image import`** — new `imageImport` route + server handler to turn a
>   rootfs tarball into a layer/config/manifest. Self-contained (image service
>   only), no runtime changes. *Most tractable of the four.*
> - **#7 `rename`** — new route + re-keying the container store. Complicated
>   because the container ID *is* the identity: it's the store key and appears
>   in the launchd service label (`container-runtime-linux.<id>`), so a rename
>   is really a re-register. Needs care to avoid orphaning a running container.
> - **#10 `builder prune`** — BuildKit cache GC through the builder VM's gRPC
>   (`container-builder-shim`); requires visibility into that gRPC surface.
> - **#8 `network connect`/`disconnect`** — hot-plug a NIC into a *running* VM;
>   hardest, and gated to macOS 26. *Do last.*
7. **`container rename`** — add a `rename(id:newName:)` method to `ContainerClient`/server that updates the container's stored name/ID mapping without touching its running state. CLI: `ContainerCommands/Container/ContainerRename.swift`. Needs care around ID uniqueness checks already enforced at `create`.
8. **`container network connect` / `disconnect`** — extend `Services/Network` server to support attaching/detaching a network interface on a live container (today network attachment is fixed at container-create time in `ContainerCreate.swift`/`ContainerRun.swift`). CLI: `ContainerCommands/Network/NetworkConnect.swift`, `NetworkDisconnect.swift`. **Must be added under the existing `#available(macOS 26)` gate** that guards the whole `network` group (see §2).
9. **`container image import`** — extend `ContainerImagesService` with an "import raw rootfs tarball as image layer" path alongside the existing `load` (OCI archive) path. CLI: `ContainerCommands/Image/ImageImport.swift`.
10. **`container builder prune`** — add a build-cache GC route into the BuildKit-based builder (`Sources/ContainerBuild` + builder service) and a `ContainerCommands/Builder/BuilderPrune.swift` command, registered alongside the existing start/status/stop/delete in `Builder.swift`. Match Docker's `-f/--force`/`--all` flags. (Backend GC does not exist yet, so this is more than a CLI wrapper — hence Phase 2, not Phase 1.)

### Phase 3 — Runtime-level primitives (larger design work)

11. **`container pause` / `container unpause`** — requires a freeze/thaw primitive at the VM or cgroup level inside `Containerization`/`ContainerizationOS`. Needs a design spike: does the Virtualization.framework VM support process-group suspend, or does this need a cgroup freezer inside the guest kernel? CLI additions are trivial once the primitive exists (`ContainerPause.swift`, `ContainerUnpause.swift`, following the `ContainerKill`/`ContainerStop` `--all` pattern).
12. **`container top`** — requires a guest-side process listing call. Likely implemented as a special-cased `exec` that runs `ps` inside the container's namespace and parses the output, reusing the existing `createProcess`/exec machinery rather than inventing a new protocol. CLI: `ContainerCommands/Container/ContainerTop.swift`.
13. **`container update`** — requires live resource-limit mutation (cpu/memory) on a running container/VM, likely via the same config path used at `create` time (`-c/--cpus`, `-m/--memory`) but applied post-hoc. Needs `Containerization` support for adjusting a running VM's allocated resources.
14. **`container attach`** — requires a route to re-attach to a running init process's existing stdio streams (distinct from `exec`, which starts a *new* process). Confirmed as a current known limitation (`ContainerStart.swift:62`). Needs design work in `ContainerClient`/`APIServer` to expose the already-running process's pipes to a second CLI invocation.
15. **`container diff`** — requires a filesystem-diff primitive between the container's writable layer and its base image snapshot. Depends on how `Containerization`'s snapshotter/overlay layer works; likely needs a new method in `ContainerImagesService`/snapshot handling.
16. **`container commit`** — requires snapshotting a running or stopped container's writable layer into a new OCI image, reusing `ClientImage`'s save/tag primitives once a container-to-image snapshot method exists. Depends on #15's diff/snapshot work being in place first.

### Phase 4 — Larger/optional scope

17. **`container image search`** — registry search endpoint call; only meaningful against registries that implement a search API (Docker Hub does, most private registries don't). Should be additive and fail gracefully with a clear error for registries lacking the endpoint.
18. **`container system events`** — needs a new pub/sub event bus for container/image/network/volume lifecycle events, plus a streaming CLI command (`container system events --since ... --filter ...`). This is the largest single addition in this plan — treat as its own design doc before implementation, since every existing command that mutates state (create/start/stop/kill/delete/pull/etc.) would need to publish to the bus.

### Phase 5 — Compose orchestration (tracked from the uploaded research)

19. **`container compose`** — no native support exists today (confirmed both by this audit and by the uploaded `Apple_Container_Ecosystem_Summary.md`, which points at the third-party `Mcrich23/Container-Compose` as the only current bridge). This is the single most-requested "popular Docker command" — e.g. `docker compose -f docker-compose-prod.yml up --build` — so it gets a dedicated design below rather than a one-line entry.

This is deliberately sequenced last because it *reuses* the earlier
primitives (`wait` #6 for `depends_on` ordering, `restart` #1, `network
connect` #8, `system events` #18 for `--watch`/log following) instead of
reinventing them. A `compose` command that shipped before those would have
to duplicate their logic.

#### 19.1 Target invocation (must work end to end)

```
container compose -f docker-compose-prod.yml up --build
```

Broken down, the orchestrator must honor:

- `-f, --file <path>` (repeatable) — parse the named compose file(s) instead of the default `./docker-compose.yml` / `compose.yml`. Also `-p/--project-name`, `--env-file`, `--profile`.
- `up` — reconcile the whole file to a running state: create networks, create volumes, (re)build or pull images, then create + start every service container in `depends_on` order.
- `--build` — force `container build` for every service that declares a `build:` section *before* starting it (default is build-if-missing).
- Common `up` flags to cover: `-d/--detach`, `--force-recreate`, `--no-build`, `--no-deps`, `--remove-orphans`, `--wait` (block until healthy), `--pull`.

#### 19.2 Project model (already supported by existing primitives)

Docker Compose tags every resource with `com.docker.compose.project=<name>`
so it can find them again for `ps`/`down`/`logs`. `container` **already has
the two primitives this needs**, so no backend work is required for the
project model itself:

- **Set** labels at creation: `-l/--label` on run/create (`Flags.swift:280`).
- **Find** them later by label: `ContainerListFilters.labels` supports
  regex-matched label filtering (`ContainerListFilters.swift:34`), and
  volumes already carry labels (`ClientVolume.create(..., labels:)`).

So the orchestrator stamps every container/volume/network it creates with,
e.g., `com.apple.container.compose.project=<project>` and
`com.apple.container.compose.service=<service>`, and later selects a
project's resources with a label filter. This is exactly how `down`, `ps`,
`logs`, `stop`, and `restart --project` locate what they own.

#### 19.3 Compose file → container primitive mapping

| Compose key | Maps to | Backing primitive | Status |
|---|---|---|---|
| `services.<s>.image` | `container run <image>` | `ContainerClient.create`/`ContainerRun` | exists |
| `services.<s>.build` | `container build -t <s> <ctx>` (forced when `--build`) | `BuildCommand` | exists |
| `services.<s>.ports` | `-p host:container[/proto]` | `publishedPorts` | exists |
| `services.<s>.volumes` (bind) | `-v/--mount` | mount flags | exists |
| `services.<s>.volumes` (named) | `container volume create` + mount | `ClientVolume.create` | exists |
| `services.<s>.environment` | `-e KEY=VALUE` | `--env` | exists |
| `services.<s>.env_file` | `--env-file` | `--env-file` | exists |
| `services.<s>.command` / `entrypoint` | positional args / `--entrypoint` | run args / `--entrypoint` | exists |
| `services.<s>.networks` | `--network` at create (+ `network connect` for extras) | `--network` / #8 | partial (#8) |
| `services.<s>.depends_on` | topological start order; block on readiness | `wait` (#6) | needs #6 |
| `services.<s>.labels` | `-l/--label` (merged with project labels) | `--label` | exists |
| `services.<s>.cpus` / `mem_limit` | `-c/--cpus`, `-m/--memory` | resource flags | exists |
| `services.<s>.restart` | restart policy | **no restart-policy concept exists** | **gap — see 19.5** |
| `services.<s>.healthcheck` | readiness gate for `depends_on: condition: service_healthy` | none today | **gap — see 19.5** |
| top-level `networks` | `container network create` | `NetworkCreate` | exists (macOS 26+) |
| top-level `volumes` | `container volume create` | `VolumeCreate` | exists |

#### 19.4 `up --build` execution algorithm

1. Parse `-f docker-compose-prod.yml` into a service graph; resolve `--env-file`/variable interpolation; derive the project name (`-p`, else the file's directory name).
2. Create top-level `networks` and `volumes` that don't already exist (label them with the project).
3. Topologically sort services by `depends_on` (error on cycles).
4. Because `--build` is set, run `container build -t <project>_<service> <build.context>` for every service that has a `build:` section (services with only `image:` are pulled on first run).
5. In dependency order, `create` + `start` each service container, stamped with project/service labels, wired to the project network, ports, volumes, env. For a dependency declared `condition: service_started`, proceed once started; for `service_healthy`, block on the healthcheck (see 19.5 gap); the generic ordering barrier reuses `container wait` (#6).
6. If not `-d`, attach/stream aggregated logs (reusing `ContainerClient.logs`); on `--wait`, block until all are healthy/running.

#### 19.5 Known limitations to call out in the design doc

Two compose fields have **no backing primitive today** and must either be
implemented first or explicitly documented as unsupported in v1:

- **`restart:` policies** (`no`/`always`/`on-failure`/`unless-stopped`) — there is no restart-policy concept anywhere in `Sources/` (verified). v1 options: (a) document as unsupported, or (b) add a restart-policy field to `ContainerConfiguration` + a supervisor in the runtime. Recommend (a) for v1.
- **`healthcheck:` + `depends_on: condition: service_healthy`** — no healthcheck subsystem exists. v1 can support `condition: service_started` (via `wait`/start ordering) and treat `service_healthy` as best-effort (fall back to started) with a clear warning, deferring true healthchecks to a later phase.
- **`deploy:` / replicas / placement** — Swarm-oriented; out of scope (consistent with §3.8).
- **`profiles:`** — supportable in the parser (`--profile` filter) with modest effort; include if cheap, else defer.

#### 19.6 Compose subcommand priority

Ship in this order so the headline workflow works first:

1. **`up` (incl. `--build`), `down`, `build`, `ps`, `logs`** — the core loop, covers the requested `up --build` invocation and its teardown.
2. `stop`, `start`, `restart`, `pull`, `config` (validate/render).
3. `exec`, `run`, `kill`, `pause`/`unpause`, `top`, `cp`, `events` — thin wrappers over the single-container commands of the same name (several of which are themselves Phase 1-3 items, so these land naturally after those).

## 5. Suggested execution order

Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5.

Phase 5 (compose) is last on purpose: its `up --build` flow reuses Phase 1's
`restart`, Phase 2's `wait` (#6, for `depends_on` ordering) and `network
connect` (#8), and — for `compose events`/`--watch` — Phase 4's `system
events` (#18). Building compose before those means duplicating their logic.
Everything compose needs for the *headline* `up --build`/`down` loop except
`depends_on` ordering already exists today (build, run, network/volume
create, label-based project selection), so a minimal compose could ship
right after Phase 2's `wait` lands if that workflow is prioritized ahead of
Phase 3/4.

Each numbered item above should land as its own PR: new command file(s)
under `Sources/ContainerCommands/`, matching entry in
`docs/command-reference.md`, and integration test(s) under `Tests/` following
the existing per-command test pattern (see `Tests/` for current
`Container*`/`Image*` command coverage) before moving to the next item.
