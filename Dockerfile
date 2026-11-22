FROM node:26-slim@sha256:e6bedef217677b276c591795e169840edd9096dbf13f29df8ef8d1856b8820bc

# The npm release this image is built from. Renovate bumps it from upstream's
# dsh-v* git tags (renovate.json5).
ARG DSH_VERSION=0.2.2-rc.5

# pnpm, which dsh runs to look up and install plugins (`dsh plugin`, the Web UI's plugin
# installer). The image ships no corepack, so without it every plugin lookup fails with
# `spawn pnpm ENOENT`. Kept on the major upstream builds with; Renovate bumps it.
ARG PNPM_VERSION=11.29.0

# The container's own needs: bubblewrap is the command sandbox on kernels without Landlock
# (Unraid; it needs --security-opt seccomp=unconfined and systempaths=unconfined), gosu
# and tini run the entrypoint, xdg-user-dirs locates dsh's default workspace.
#
# The rest is for the agent, which runs unprivileged and cannot apt install: ssh (also
# dsh's SSH workspaces), build tools and python3 (npm and pip packages that compile native
# code; node-gyp needs both), and the everyday shell tools. User-level installs (uv, pip,
# npm -g) land in the persistent /home/node instead.
RUN apt-get update                              \
 && apt-get install -y --no-install-recommends  \
      bubblewrap                                \
      build-essential                           \
      ca-certificates                           \
      curl                                      \
      git                                       \
      gosu                                      \
      jq                                        \
      openssh-client                            \
      procps                                    \
      python3                                   \
      ripgrep                                   \
      tini                                      \
      unzip                                     \
      xdg-user-dirs                             \
      xz-utils                                  \
 && rm -rf /var/lib/apt/lists/*

# uv and uvx, from Astral's published image (Renovate bumps the tag and pins its digest).
# Python tools then run as `uvx <tool>`, and `uv python install` adds other Pythons, all
# into /home/node without root.
COPY --from=ghcr.io/astral-sh/uv:0.13.9 /uv /uvx /usr/local/bin/

RUN npm install -g "@deepseek-ai/dsh@${DSH_VERSION}" "pnpm@${PNPM_VERSION}" \
 && npm cache clean --force

# Runtime files are staged with COPY, installed at their target paths in one place, and the
# staging dir removed in the same layer.
COPY runtime/ /tmp/dsh-runtime/
RUN install -D -m 755 /tmp/dsh-runtime/entrypoint.sh   /usr/local/bin/dsh-entrypoint   \
 && install -D -m 755 /tmp/dsh-runtime/healthcheck.sh  /usr/local/bin/dsh-healthcheck  \
 && rm -rf /tmp/dsh-runtime

# /home/node is a volume so tools the agent installs survive restarts. npm's global prefix
# defaults to /usr/local, which the unprivileged user cannot write, so global installs go to
# ~/.local instead, next to pip --user and uv tool; its bin dir comes first on PATH.
ENV DSH_HOME=/data                          \
    DSH_PORT=3080                           \
    PUID=99                                 \
    PGID=100                                \
    NPM_CONFIG_PREFIX=/home/node/.local     \
    PATH=/home/node/.local/bin:$PATH

RUN mkdir -p /data /workspace /home/node/.local/bin

# Starts as root; dsh-entrypoint remaps node to PUID/PGID and drops to it via gosu.
WORKDIR /workspace
VOLUME ["/data", "/workspace", "/home/node"]
EXPOSE 3080

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD /usr/local/bin/dsh-healthcheck

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/dsh-entrypoint"]

# Last, so the per-build values below never invalidate the cached layers above. source is
# this repository, whose v<version> releases are what 3U and similar tools look up. The
# net.unraid.docker labels give the Docker tab an icon and a WebUI link even for a
# container not created from the template (docker run, compose).
ARG VCS_REF=dev
ARG BUILD_DATE=unknown
ARG BASE_NAME=unknown
ARG BASE_DIGEST=unknown
LABEL org.opencontainers.image.title="DeepSeek Harness"                                                              \
      org.opencontainers.image.description="An open-source AI coding agent."                                         \
      org.opencontainers.image.authors="0x1917 (https://github.com/0x1917)"                                          \
      org.opencontainers.image.source="https://github.com/0x1917/deepseek-harness"                                   \
      org.opencontainers.image.url="https://deepseek.com/en/harness/"                                                \
      org.opencontainers.image.documentation="https://github.com/0x1917/deepseek-harness/blob/master/README.md"      \
      org.opencontainers.image.licenses="MIT"                                                                        \
      org.opencontainers.image.version="${DSH_VERSION}"                                                              \
      org.opencontainers.image.ref.name="${DSH_VERSION}"                                                             \
      org.opencontainers.image.revision="${VCS_REF}"                                                                 \
      org.opencontainers.image.created="${BUILD_DATE}"                                                               \
      org.opencontainers.image.base.name="${BASE_NAME}"                                                              \
      org.opencontainers.image.base.digest="${BASE_DIGEST}"                                                          \
      net.unraid.docker.icon="https://raw.githubusercontent.com/0x1917/unraid-templates/master/assets/dsh/icon.png"  \
      net.unraid.docker.webui="http://[IP]:[PORT:3080]/"
