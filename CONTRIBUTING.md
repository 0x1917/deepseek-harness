# Contributing

This repository packages [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)
(`dsh`) into a single container image and publishes it. It holds no application code: the
`Dockerfile`, the `runtime/` scripts it installs, and the CI workflows are the whole of it.

## Where a report or a change belongs

| Subject                                                                                     | Goes to                                                                                                 |
| ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| The image: build, entrypoint, PUID/PGID, the command sandbox, CI, how the container behaves | Here: [issues](https://github.com/0x1917/deepseek-harness/issues) and pull requests                     |
| The Unraid template: fields, defaults, artwork, the Docker tab entry                        | [`0x1917/unraid-templates`](https://github.com/0x1917/unraid-templates/issues)                          |
| DeepSeek Harness itself: the agent, models, tools, plugins, the web UI                      | Upstream [Discussions](https://github.com/deepseek-ai/deepseek-harness/discussions) (issues are closed) |
| Configuration and use of the app                                                            | [Upstream documentation](https://deepseek-harness.github.io/deepseek-harness/)                          |
| A security vulnerability                                                                    | [SECURITY.md](SECURITY.md), privately, not a public issue                                               |

If you are unsure, open it here and it will be moved rather than closed.

## Run the checks before you open a pull request

CI runs all of these, and a pull request that fails them will not be reviewed until it passes:

```sh
node --test scripts/tags.test.mjs
shellcheck -x -S warning runtime/*.sh scripts/*.sh
actionlint .github/workflows/*.yml
```

The tag tests cover the version ordering the publish workflow uses to decide whether
`latest` moves. They need only Node.

```sh
docker build -t deepseek-harness:test .
bash scripts/smoke-test.sh deepseek-harness:test
```

The smoke test boots the image the way the Unraid template does and checks health, the
version, the 99:100 privilege drop, `/data` ownership, the default workspace, the bubblewrap
sandbox, token login, the client bundle and the host fence. It needs `docker`, `curl` and
`bash`, and takes about 30 seconds. On Ubuntu 24.04 the sandbox check needs the two AppArmor
restrictions lifted, as CI does (see the comment at the top of the script).

## The invariants the tests enforce

A failing check here is usually telling you something deliberate. Each exists because the
alternative was a bug:

- **No `USER` instruction.** The entrypoint must start as root to remap `node` to
  `PUID`/`PGID` and fix `/data`, then drops privileges with `gosu`.
- **dsh listens on the container IP, never `0.0.0.0`.** dsh refuses wildcard binds.
- **`/workspace` is only re-owned when it is empty.** A mounted share must never be chowned.
- **XDG Documents points at `/workspace`.** Without it dsh cannot create its default workspace.
- **Git tags are `v<version>`**, with `v<version>-r<n>` for a rebuild. Versions are upstream
  prereleases, so ordering is semver (`scripts/tags.mjs`), not `sort -V`.

## Changing the image

- Keep the privilege model intact: nothing runs as root after the entrypoint's setup.
- Comments explain *why* a thing is done, especially where the obvious alternative fails. A
  change that removes one needs to replace it with the reason.
- If you change behaviour a user can see, update [README.md](README.md). If the change affects
  what the image needs at run time, the Unraid template needs a matching change, in the
  templates repository, as a separate pull request.

## Versions, tags, and releases

Do not bump `DSH_VERSION`, create a git tag, or edit the publish workflow's release logic in a
pull request: Renovate proposes upstream bumps and the maintainer cuts releases. Image tags are
bare versions (`0.2.2-rc.5`, `latest`), the git source tag is `v0.2.2-rc.5`, and republishing
the same upstream release appends a rebuild number (`v0.2.2-rc.5-r1`). Only the newest image
tag is supported.

## Pull request shape

- One concern per pull request. A formatting sweep mixed with a fix will be asked to split.
- Say why in the description, not just what. The diff already says what.
- Do not reorder `Dockerfile` layers for tidiness; the order is the cache.
- Do not reformat files you did not otherwise touch.

## Licensing

This repository is [MIT](LICENSE). There is no CLA and no contributor agreement: by opening a
pull request you agree your contribution is licensed under the same terms. DeepSeek Harness
itself carries its own license in
[`deepseek-ai/deepseek-harness`](https://github.com/deepseek-ai/deepseek-harness).
