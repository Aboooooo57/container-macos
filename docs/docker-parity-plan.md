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
- `docker compose` — tracked separately (§5), it's an orchestration tool
  layered on top of the primitives here, not a `container` subcommand gap.

## 4. Implementation plan

Phased by (a) how much of the backend already exists and (b) how close the
result gets to full Docker parity for everyday single-container workflows.

### Phase 1 — CLI-only, no backend changes (low risk, fast wins)

1. **`container restart`** — new `ContainerCommands/Container/ContainerRestart.swift`, composes `ContainerClient.stop(id:opts:)` then re-starts via the existing start path used by `ContainerStart`. Mirrors `ContainerStop`'s `--all`/`--time`/`--signal` flags.
2. **`container port`** — new `ContainerCommands/Container/ContainerPort.swift`. Reads the container's stored publish specs (already captured at `create`/`run` time) via `ContainerClient.get(id:)`/inspect and prints them in `hostPort/proto -> containerPort` form.
3. **`container system prune`** — new `ContainerCommands/System/SystemPrune.swift`. Fans out to the existing `ContainerPrune`, `ImagePrune`, `NetworkPrune`, `VolumePrune` logic (call the same underlying client methods each of those commands calls), gated by a confirmation prompt and `-f/--force`/`--volumes` flags to match Docker's UX.
4. **`container image history`** — new `ContainerCommands/Image/ImageHistory.swift`, built from `ClientImage.config(for:)` which already returns the OCI `history` array; format as a table.
5. **`container system info`** — new `ContainerCommands/System/SystemInfo.swift`, aggregates existing `SystemStatus`, `SystemVersion`, `SystemDF` data sources into one summary view.

### Phase 2 — Small backend additions (new XPC route, existing service processes)

6. **`container wait`** — extend `ContainerAPIService` with an XPC route that returns a running container's exit code (mirrors `ClientProcess.wait()`, but for the container's init process rather than an exec'd one). CLI: `ContainerCommands/Container/ContainerWait.swift`.
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

### Phase 5 — Orchestration (tracked from the uploaded research)

19. **`container compose`** — no native support exists today (confirmed both by this audit and by the uploaded `Apple_Container_Ecosystem_Summary.md`, which points at the third-party `Mcrich23/Container-Compose` as the only current bridge). If in-tree compose support is wanted, scope it as a separate design doc: a `docker-compose.yml` parser plus an orchestrator that maps services to sequenced `container build`/`container run`/`container network create`/`container volume create` calls, reusing Phases 1-3's primitives (especially `network connect`, `restart`, and `wait`) as building blocks. This is intentionally sequenced last because it depends on several Phase 1-3 primitives (particularly `wait`, `restart`, and dependency-ordered start/stop) being in place first.

## 5. Suggested execution order

Phase 1 → Phase 2 → Phase 3 → (Phase 4 and Phase 5 can proceed in parallel,
since events and compose are independent efforts) once Phase 2's `wait` and
`restart`-adjacent primitives exist, as compose dependency ordering needs
`wait` to sequence `depends_on` correctly.

Each numbered item above should land as its own PR: new command file(s)
under `Sources/ContainerCommands/`, matching entry in
`docs/command-reference.md`, and integration test(s) under `Tests/` following
the existing per-command test pattern (see `Tests/` for current
`Container*`/`Image*` command coverage) before moving to the next item.
