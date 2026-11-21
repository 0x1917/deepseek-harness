# DeepSeek Harness

[![Version](https://img.shields.io/docker/v/0x1917/deepseek-harness)](https://hub.docker.com/r/0x1917/deepseek-harness)
[![Build](https://github.com/0x1917/deepseek-harness/actions/workflows/build.yml/badge.svg)](https://github.com/0x1917/deepseek-harness/actions/workflows/build.yml)
[![Lint](https://github.com/0x1917/deepseek-harness/actions/workflows/lint.yml/badge.svg)](https://github.com/0x1917/deepseek-harness/actions/workflows/lint.yml)
[![Pulls](https://img.shields.io/docker/pulls/0x1917/deepseek-harness)](https://hub.docker.com/r/0x1917/deepseek-harness)
[![Image size](https://img.shields.io/docker/image-size/0x1917/deepseek-harness)](https://hub.docker.com/r/0x1917/deepseek-harness)
[![Platform](https://img.shields.io/badge/platform-linux%2Famd64-blue?logo=linux&logoColor=white)](#requirements)
[![License](https://img.shields.io/github/license/0x1917/deepseek-harness)](https://github.com/0x1917/deepseek-harness/blob/master/LICENSE)

The [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)  web UI repackaged as a container for Unraid. To install it, search for it on the Community Applications plugin
or install it manually with the DSH template from [0x1917/unraid-templates](https://github.com/0x1917/unraid-templates/blob/master/templates/my-deepseek-harness.xml) (copy it to `/boot/config/plugins/dockerMan/templates-user/`).

DeepSeek Harness is an AI coding agent you drive from the browser: give it a workspace and it
reads and edits files, runs commands in a sandbox, keeps a session history, and runs scheduled
tasks. Upstream is a **developer preview** that ships compatibility-breaking changes between
releases, and it executes model-generated commands; read its
[safety notice](https://github.com/deepseek-ai/deepseek-harness/blob/master/SAFETY.md) and mount
only what the agent should be able to change.

## Requirements

- **x86_64** Docker host. The image is built for `linux/amd64`.
- **Extra Parameters** `--security-opt seccomp=unconfined --security-opt systempaths=unconfined`
  on hosts without Landlock, which includes Unraid. See [Command sandbox](#command-sandbox).
- A model provider: a DeepSeek API key or any OpenAI-compatible endpoint (e.g. Ollama).

## How the image is built

Nothing is compiled here. The Dockerfile starts from `node:26-slim` (pinned by digest), installs the published
[`@deepseek-ai/dsh`](https://www.npmjs.com/package/@deepseek-ai/dsh) CLI at the release named by
`ARG DSH_VERSION`, and adds what a container needs around it:

- **`tini`** as PID 1, so stop signals reach dsh and orphaned agent processes are reaped.
- **`gosu`** and `runtime/entrypoint.sh`, which start as root only long enough to remap the
  `node` user to `PUID`/`PGID` and fix ownership, then run dsh unprivileged.
- **`bubblewrap`**, dsh's command sandbox on kernels without Landlock.
- **Tools the agent commonly shells out to:** `git`, `curl`, `python3`.
- **`runtime/healthcheck.sh`**, because dsh has no health endpoint.

### Build

The build context is the repository root.

```sh
docker build -t deepseek-harness:latest .
```

The image carries four provenance labels the CI chain fills in: `image.revision` (the commit,
default `dev`), `image.created` (the commit date, default `unknown`), and `image.base.name` /
`image.base.digest` (read from the `FROM` line, default `unknown`).

#### Test a different upstream release without editing the file

```sh
docker build -t deepseek-harness:beta --build-arg DSH_VERSION=<ver> .
```

`<ver>` is a version published on npm, such as `0.2.2-rc.5`. For a real update, edit the ARG
instead (see [Version management](#version-management)).

## Run

Prebuilt on Docker Hub: `docker pull 0x1917/deepseek-harness:latest`.

```sh
docker run -d                                       \
  --name dsh                                        \
  --restart unless-stopped                          \
  -p 3080:3080                                      \
  --security-opt seccomp=unconfined                 \
  --security-opt systempaths=unconfined             \
  -e DSH_TRUSTED_HOSTS=192.168.1.10                 \
  -e DSH_PUBLIC_URL=http://192.168.1.10:3080/       \
  -v /mnt/user/appdata/dsh/data:/data               \
  -v /mnt/user/appdata/dsh/home:/home/node          \
  -v /mnt/user/appdata/dsh/workspace:/workspace     \
  0x1917/deepseek-harness:latest

docker logs dsh   # prints the login link
```

### Paths

| Path         | Holds                                                                                                  |
| ------------ | ------------------------------------------------------------------------------------------------------ |
| `/data`      | dsh's home (`DSH_HOME`): settings, sessions, plugins, the saved API key, and the cookie signing key    |
| `/home/node` | The app user's home: tools the agent installs (`npm -g`, `pip --user`, `uv tool`), SSH keys and config |
| `/workspace` | What the agent reads and edits. dsh's default workspace is created under it                            |

All three survive restarts and image updates. `/data` and `/home/node` are re-owned to
`PUID`/`PGID` at every start; `/workspace` only when it is empty, so a mounted share is never
chowned.

## First boot

1. **Sign in.** There is no password. Every start prints a login link with a launch token in
   the container log (`docker logs dsh`, or Docker tab > container icon > Logs). Open it once
   per browser and per address: it sets a signed session cookie that keeps that browser signed
   in for 30 days, across restarts. Without a session the UI answers 401.
2. **Add a model** under Settings > Models: a DeepSeek API key, or a custom OpenAI-compatible
   provider. For Ollama, use `http://<host-ip>:11434/v1` as the base URL (`localhost` inside the
   container is the container) and enter any non-empty API key: dsh refuses to call an
   OpenAI-compatible provider without one, even though Ollama ignores it.
3. **Open a workspace** and send a task.

The container is healthy once dsh's listener answers HTTP.

## Environment

Read from the container environment at start; changing a value means recreating the container.

| Variable            | Default                  | Meaning                                                                                                    |
| ------------------- | ------------------------ | ---------------------------------------------------------------------------------------------------------- |
| `DSH_TRUSTED_HOSTS` | `localhost`              | Comma-separated host names or IPs browsers use to reach the UI. Any other name gets 403 on every API call. |
| `DSH_PUBLIC_URL`    | `http://localhost:3080/` | The root of the login link printed in the log. Display only; it grants no access.                          |
| `DSH_BIND`          | container IP             | The address inside the container dsh listens on. Set it only on a container with several networks.         |
| `PUID` / `PGID`     | `99` / `100`             | The user dsh runs as (Unraid's `nobody:users`).                                                            |
| `UMASK`             | `022`                    | Mask for the files dsh creates.                                                                            |
| `DEEPSEEK_API_KEY`  | unset                    | Optional; the UI can store the key in `/data` instead.                                                     |

Baked into the image and not meant to be changed: `DSH_HOME=/data`, `DSH_PORT=3080` (move the UI
with the host side of `-p` instead), `NPM_CONFIG_PREFIX=/home/node/.local`, and
`/home/node/.local/bin` at the front of `PATH`.

### Address and access

dsh refuses to listen on every interface (`0.0.0.0`), so the entrypoint binds the container's
own IP, which is what Docker's port publishing forwards to. On top of that, dsh checks the
`Host` of every API request: loopback and the bind address always pass, anything else must be
listed in `DSH_TRUSTED_HOSTS`. That check defends against DNS rebinding and cross-site requests;
it is not authentication, which is the launch token and the session cookie.

The listener serves plain HTTP. Beyond a trusted LAN, put a TLS reverse proxy in front: over
HTTP the token and the cookie travel in clear text.

## Command sandbox

dsh will not run an agent command without a sandbox. It tries bubblewrap first, then Landlock,
and fails closed when neither works.

| Host                   | Sandbox    | Extra parameters                                                          |
| ---------------------- | ---------- | ------------------------------------------------------------------------- |
| Docker Desktop (macOS) | Landlock   | none                                                                      |
| Unraid                 | bubblewrap | `--security-opt seccomp=unconfined --security-opt systempaths=unconfined` |

Unraid's kernel is built without Landlock (the system call returns `ENOSYS`), so bubblewrap is
the only option there, and Docker's defaults block it twice: the seccomp filter forbids creating
user namespaces, and the masked `/proc` paths stop it mounting a fresh `/proc`. Each flag lifts
one of those. They loosen the container's own isolation, so the sandbox carries more of the
weight.

## Test

`scripts/smoke-test.sh <image>` is the gate CI runs, on the build and again on the bytes publish
loads. It boots the image the way the Unraid template does, with throwaway mounts for all three
paths, and fails on the first broken expectation. Needs `docker`, `curl`, and `bash`.

```sh
docker build -t deepseek-harness:test .
bash scripts/smoke-test.sh deepseek-harness:test
```

| Check                                                  | Proves                                                 |
| ------------------------------------------------------ | ------------------------------------------------------ |
| container becomes healthy                              | dsh started and the healthcheck reaches its listener   |
| `dsh --version` matches the image version label        | the npm install is the release the ARG names           |
| dsh runs as `99:100`                                   | the `PUID`/`PGID` remap and the `gosu` drop            |
| `/data` and the empty `/workspace` owned by `99:100`   | the Unraid appdata ownership contract                  |
| XDG Documents is `/workspace` on a fresh `/home/node`  | dsh can create its default workspace on a new install  |
| npm's global prefix is `/home/node/.local`, on `PATH`  | tools the agent installs land on the persistent volume |
| bubblewrap creates a sandbox                           | agent commands can run on a kernel without Landlock    |
| 401, then 303 with the token, then 200 with the cookie | the launch-token sign-in                               |
| the client bundle loads                                | the web UI is served, not just the document            |
| untrusted `Host` gets 403, a trusted one passes        | `DSH_TRUSTED_HOSTS` reaches dsh's host fence           |

On Ubuntu runners (24.04 on) the bubblewrap check needs two AppArmor restrictions lifted that Unraid does not
have; CI does so, and the comment at the top of the script shows how.

Deliberate gaps: anything needing a model (a real agent turn, a command run through dsh's own
sandbox selection), TLS and reverse-proxy behaviour, and the agent's tools.

`node --test scripts/tags.test.mjs` covers the tag ordering the publish workflow relies on.

## CI

Two workflows, chained, plus lint. Neither of the first two can do the other's job.

| Workflow      | Trigger                                | Does                                                                   |
| ------------- | -------------------------------------- | ---------------------------------------------------------------------- |
| `build.yml`   | every push and PR, weekly, dispatch    | build, smoke test, and package the image as an artifact                |
| `publish.yml` | `workflow_run` after `build` completes | load that run's artifact, verify it, push, tag, and cut the release    |
| `lint.yml`    | every push and PR                      | actionlint, shellcheck, the build-inputs check, the tag-ordering tests |

Build never touches the registry. Publish never builds. The image crosses the boundary as
`docker save | zstd` plus a `meta.json` holding the image ID, the version, and the publish
decision.

| Event                                                      | Build | Publish |
| ---------------------------------------------------------- | ----- | ------- |
| push to `master` changing a build input since the last tag | yes   | yes     |
| push to `master` changing nothing that reaches the image   | yes   | no      |
| pull request, other branch, or the weekly run              | yes   | no      |
| dispatch, `force_publish=false`                            | yes   | no      |
| dispatch, `force_publish=true`                             | yes   | yes     |

Build inputs are the paths that reach the image, listed in [`.github/build-inputs`](.github/build-inputs):
`Dockerfile`, `.dockerignore`, and `runtime/`. Lint fails if the Dockerfile copies from any other
path, so a new `COPY` source cannot change the image without publishing it.

The baseline for "changed" is the highest published `v*` tag, not the previous push, so a
force-push or a README-only amend never republishes. A failed publish leaves no tag, so the next
push retries it. The build first waits up to 15 minutes for the version to appear on npm, since
upstream tags a release slightly before npm has it.

Publish runs only from `master` and only after a green build. It checks out `master`, never the
build run's commit, so the job holding a write token runs only code already on `master`. Then it:

1. Loads the tarball and asserts the image ID matches the one in `meta.json`
2. Runs `smoke-test.sh` again on the loaded bytes, because they travelled through an artifact store
3. Pushes `<ver>` on the first publish of a release, `<ver>-r<n>` on a rebuild, plus `latest`
   when it carries the highest tag of the series, and verifies the pushed digests
4. Creates the git source tag on the build run's commit (`v<ver>`, or `v<ver>-r<n>`)
5. Creates the GitHub release, quoting upstream's notes for `dsh-v<ver>` with contributor
   handles defused, marked as a prerelease when the version is one

Two manual paths:

```sh
# build now, publish on completion
gh workflow run build.yml --ref master -f force_publish=true

# republish an existing build, no rebuild (run id from the Actions URL)
gh workflow run publish.yml -f build_run_id=1234567890
```

Secrets: `DOCKERHUB_TOKEN`, a Docker Hub access token with Read & Write scope.

### Upstream releases

Upstream publishes no GitHub "latest" release, only prereleases on `dsh-v*` git tags, with the
npm package of the same version. [`renovate.json5`](renovate.json5) has Renovate follow those
tags and propose each newer `rc` (never an `alpha`) as a pull request that bumps
`ARG DSH_VERSION`. Its pull requests trigger `build` and `lint`, so the smoke test runs before
anything is merged, and merging publishes. Renovate also keeps the `node` base image pinned by digest, batching
base-image updates weekly (merging one republishes the same version as `-r<n>`), and groups
GitHub Actions updates.

## Version management

`ARG DSH_VERSION` is the single source of truth.

| Thing                     | Form                                              | Example                              |
| ------------------------- | ------------------------------------------------- | ------------------------------------ |
| upstream git tag          | `dsh-v` + version                                 | `dsh-v0.2.2-rc.5`                    |
| npm package               | bare version                                      | `@deepseek-ai/dsh@0.2.2-rc.5`        |
| this repo's Hub tag       | bare version first publish, `<ver>-r<n>` rebuilds | `0x1917/deepseek-harness:0.2.2-rc.5` |
| OCI `image.version` label | bare version                                      | `0.2.2-rc.5`                         |
| git tag (CI)              | `v` + version; rebuilds get `-r<n>`               | `v0.2.2-rc.5`                        |

Tags are ordered by semver ([`scripts/tags.mjs`](scripts/tags.mjs)), not `sort -V`: a final
release outranks its prereleases (`0.2.2` > `0.2.2-rc.5`), and the rebuild suffix is compared
separately, so `rc.5-r1` stays below `rc.6`.

### Update checklist

Renovate does steps 1 to 3 and opens a PR; merging it is step 4. By hand:

1. Read upstream's release notes for `dsh-v<ver>` and confirm `<ver>` is on npm.
2. Edit `ARG DSH_VERSION`.
3. Build and run `smoke-test.sh` locally.
4. Commit and push to `master`; CI publishes `<ver>` and moves `latest`.

### Caveats

- **Version tags are immutable after the first publish.** Every rebuild pushes its own
  `<ver>-r<n>` tag, and `latest` moves only when the run carries the highest tag of the series,
  so re-publishing an older build never drags it backwards. The release for a version is
  retargeted to its newest source tag.
- **Rollback** is a previous version tag (`0x1917/deepseek-harness:<ver>`, or a rebuild's
  `<ver>-r<n>`). Old tags are not deleted. Upstream's own data formats may not roll back with it.
- **Only the newest tag is supported**, and upstream breaks compatibility between releases: read
  the notes before merging a bump.

## Design notes

- **dsh is exec'd behind `tini`.** It is PID 1's direct child, gets `docker stop`'s signal
  itself, and its exit status is the container's. `tini` also reaps the orphans agent commands
  leave behind.
- **Root only at start.** The entrypoint remaps `node` to `PUID`/`PGID`, re-owns only what is
  wrong (so a large `/data` restarts fast), then re-runs itself as `node` through `gosu`.
  Nothing the agent runs has root.
- **The container IP, not `0.0.0.0`.** dsh refuses wildcard binds, and loopback is unreachable
  through Docker's port publishing, so the entrypoint binds the container's address.
- **A persistent home.** `/home/node` is a volume so the agent's installs survive. npm's global
  prefix moves to `~/.local` because its default, `/usr/local`, is not writable by the app user.
  The entrypoint recreates the XDG file and the bin directory on a fresh, empty volume.
- **Layout.** `runtime/` holds what ships in the image; `scripts/` holds what only CI and
  developers run.
