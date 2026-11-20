# Security policy

This repository packages [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)
(`dsh`) into one container image: the published npm CLI, an entrypoint, and bubblewrap as
the command sandbox. It is a build and packaging repository, not a fork of the application.
That split decides where a report belongs, so read the first section before opening anything.

## Where to report

| Subject                                                           | Report it at                                                                              |
| ----------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| This image: `Dockerfile`, `entrypoint.sh`, the sandbox, workflows | [Private report here](https://github.com/0x1917/deepseek-harness/security/advisories/new) |
| Upstream app: the agent, tools, plugins, auth, the web UI         | Report it here privately; see below                                                       |

Upstream has no security policy and no private reporting channel: its issue tracker is
closed and its [Discussions](https://github.com/deepseek-ai/deepseek-harness/discussions)
are public. Report an upstream vulnerability here, privately, and it will be passed on to
the upstream maintainers without publishing the details. Upstream's own statement of what it
does and does not protect is [SAFETY.md](https://github.com/deepseek-ai/deepseek-harness/blob/master/SAFETY.md).

If you are unsure which side a bug sits on, report it here. A report sent to the wrong place
is fine, a report never sent is not.

Private vulnerability reporting opens an advisory thread visible only to you and the
maintainer, and that thread becomes the place the fix is discussed and published. Please do
not open a public issue or Discussion with a working exploit that other people's instances
are vulnerable to. Everything else is fine as a normal issue: a crash you can only trigger
on your own box, a scanner warning, a misconfiguration in the example commands.

## Supported versions

Only the **newest published image tag**. Image tags are the upstream release number
(`0.2.2-rc.5`, `latest`), with `-r<n>` for a rebuild of the same release; a fix ships as a
new tag, and older tags are never patched. Upstream is a developer preview with
compatibility-breaking changes between releases, so there is no LTS and no backport.

```sh
docker pull 0x1917/deepseek-harness:latest
```

## What the image does and does not protect

Worth knowing before you report, because much of what looks like a finding is a documented
trade-off:

- **DeepSeek Harness runs model-generated commands.** Upstream says plainly that it is
  unaudited and that its sandbox reduces risk without guaranteeing isolation
  ([SAFETY.md](https://github.com/deepseek-ai/deepseek-harness/blob/master/SAFETY.md)). Mount
  only what the agent should be able to change.
- **The Unraid template turns off two Docker protections.** `--security-opt
  seccomp=unconfined` and `--security-opt systempaths=unconfined` are what bubblewrap needs
  on a kernel without Landlock; without them dsh refuses to run commands. They weaken the
  container's own isolation, so the agent's sandbox carries more of the weight.
- **The container starts as root** only to remap the `node` user to `PUID`/`PGID` and fix
  ownership of `/data`; it then drops to that user with `gosu`. dsh and everything the agent
  runs are unprivileged.
- **Authentication is dsh's launch token**, printed in the container log at every start and
  exchanged for a signed session cookie (30 days, signing key in `/data`). Anyone who can
  read the container log can sign in. There is no password.
- **The listener serves plain HTTP.** On anything but a trusted LAN, put a TLS reverse proxy
  in front; over HTTP the token and the cookie travel in clear text.
- **The host fence** (`DSH_TRUSTED_HOSTS`) defends against DNS rebinding and cross-site
  requests. It is not authentication.
- The image ships no secrets. An API key arrives at run time, through the UI (stored in
  `/data`) or the `DEEPSEEK_API_KEY` variable.

Dependency updates and base-image CVEs with no reachable exploit path are Renovate's job
here; a report is more useful when it says how an attacker reaches the code.

## What to include

- The image tag and, if you have it, the digest.
- How you run it: `docker run`, a compose file, Unraid, or behind a reverse proxy, and what
  sits in front of it.
- Steps to reproduce, with the request or command that triggers it.
- What an attacker gets: the host, data outside the workspace, another user's session,
  denial of service, nothing.
