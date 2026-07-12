# Dockerfile & Compose Coverage with `container`

This document audits every standard **Dockerfile instruction** and every common
**Docker Compose key**, and records whether `container` supports it — at build
time, at run time, or via `container compose`.

Legend: ✅ supported · ⚠️ partial / with caveats · ❌ not supported (with reason).

---

## 1. Dockerfile instructions (`container build`)

`container build` drives the same BuildKit Dockerfile frontend
(`buildkit.dockerfile.v0`) that Docker uses, so **every standard instruction is
parsed and built correctly**. The distinction below is whether the instruction's
result is also *honored at run time* by the container runtime.

| Instruction | Built | Honored at run time | Notes |
|---|---|---|---|
| `FROM` | ✅ | — | Base image / multi-stage. |
| `RUN` | ✅ | — | Incl. `--mount`, `--network` build mounts. |
| `CMD` | ✅ | ✅ | Default command; overridable by `container run <img> <cmd>`. |
| `ENTRYPOINT` | ✅ | ✅ | Overridable with `--entrypoint`. |
| `ENV` | ✅ | ✅ | Baked into image config; add more with `-e`. |
| `LABEL` | ✅ | ✅ | Visible via `container image inspect`. |
| `EXPOSE` | ✅ | ⚠️ | Recorded as metadata; **not auto-published** — publish with `-p` (same as `docker run` without `-P`). |
| `COPY` / `ADD` | ✅ | — | Filesystem assembled into the image. |
| `WORKDIR` | ✅ | ✅ | Default working dir; override with `-w`. |
| `USER` | ✅ | ✅ | Default user; override with `-u`. |
| `VOLUME` | ✅ | ⚠️ | Recorded in config; prefer explicit `-v`/`--mount` for data you care about. |
| `ARG` | ✅ | — | Provide with `container build --build-arg`. |
| `STOPSIGNAL` | ✅ | ✅ | Stored in the container config (`stopSignal`) and used by `container stop`. |
| `HEALTHCHECK` | ✅ | ❌ | Built into image config but **not executed** — there is no health-check subsystem (see Compose `healthcheck:`). |
| `SHELL` | ✅ | — | Affects shell-form `RUN`/`CMD` during build. |
| `ONBUILD` | ✅ | — | Triggered when the image is used as a base. |
| `MAINTAINER` | ✅ | — | Deprecated by Docker; use `LABEL`. |

**Bottom line:** any Dockerfile that builds with Docker builds with
`container build`. The only runtime gap is `HEALTHCHECK` (built, not run).

Relevant `container build` flags: `-t/--tag`, `-f/--file`, `--build-arg`,
`--label`, `--target`, `--secret`, `--platform`, `--no-cache`.

---

## 2. Compose keys (`container compose`)

How each service-level key maps onto a native `container` flag. Keys marked ✅
are wired up in `container compose`; ⚠️ are parsed but limited; ❌ have no
`container` equivalent and are ignored (with a warning where behavior would
otherwise be silently wrong).

### Service keys

| Compose key | Maps to | Status |
|---|---|---|
| `image` | `container run <image>` | ✅ |
| `build` (string or `{context, dockerfile}`) | `container build -t <project>_<svc> [-f] <ctx>` | ✅ |
| `command` (string or list) | trailing run args | ✅ |
| `entrypoint` (string or list) | `--entrypoint` | ✅ |
| `ports` | `-p` | ✅ |
| `volumes` (bind) | `-v` | ✅ |
| `volumes` (named) | `-v <project>_<name>:…` + `volume create` | ✅ |
| `environment` (list or map) | `-e` | ✅ |
| `env_file` | `--env-file` | ✅ |
| `depends_on` (list or map) | topological start order | ⚠️ start-order only (`service_started`); `service_healthy` treated as best-effort |
| `container_name` | `--name` | ✅ |
| `labels` | `--label` | ✅ |
| `working_dir` | `-w` | ✅ |
| `user` | `-u` | ✅ |
| `cap_add` | `--cap-add` | ✅ |
| `cap_drop` | `--cap-drop` | ✅ |
| `dns` | `--dns` | ✅ |
| `dns_search` | `--dns-search` | ✅ |
| `tmpfs` | `--tmpfs` | ✅ |
| `shm_size` | `--shm-size` | ✅ |
| `mem_limit` | `-m` | ✅ |
| `cpus` | `-c` | ⚠️ integer counts only; fractional values are skipped (container `--cpus` is a whole number) |
| `read_only` | `--read-only` | ✅ |
| `init` | `--init` | ✅ |
| `platform` | `--platform` | ✅ |
| `restart` | — | ❌ no restart-policy support; **warned** |
| `healthcheck` | — | ❌ not executed; **warned** |
| `networks` (custom) | — | ❌ custom networks not created (services share default networking; network create is macOS 26 only) |
| `expose` | — | ❌ metadata only in Docker too; publish real ports with `ports` |
| `sysctls` | — | ❌ no `container run` flag (config supports it, CLI does not expose it) |
| `ulimits` | — | ❌ `container run --ulimit` exists but the Compose map form is not mapped yet |
| `privileged`, `devices`, `extra_hosts`, `pid`, `ipc`, `network_mode`, `stop_signal`, `stop_grace_period`, `logging`, `configs`, `secrets`, `profiles` | — | ❌ no `container` equivalent |
| `deploy` (replicas, placement, …) | — | ❌ Swarm-oriented; out of scope |

### Top-level keys

| Compose key | Status |
|---|---|
| `services` | ✅ |
| `volumes` (named) | ✅ created as `<project>_<name>` |
| `networks` | ❌ not created (macOS 26 dependency) |
| `name` (project name) | ✅ used as the project name |
| `configs`, `secrets` | ❌ Swarm-oriented |

---

## 3. How to verify quickly

```bash
# Dockerfile: every instruction builds via BuildKit
container build -t coverage-test - <<'EOF'
FROM docker.io/library/alpine
LABEL role=test
ENV GREETING=hi
WORKDIR /app
COPY . .
EXPOSE 8080
STOPSIGNAL SIGTERM
USER nobody
CMD ["sh", "-c", "echo $GREETING"]
EOF
container image history coverage-test    # inspect the built layers/config

# Compose: keys map onto container run
container compose up      # honors ports, env, volumes, depends_on order, caps, dns, ...
container compose ps
container compose down
```

Warnings are emitted for `restart:` and `healthcheck:` so you always know when a
key in your file is not being applied.
