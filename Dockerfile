FROM node:24-slim

# The npm release this image is built from. Renovate bumps it from upstream's
# dsh-v* git tags (renovate.json5).
ARG DSH_VERSION=0.2.2-rc.5

# Tools the agent commonly shells out to. bubblewrap is the command sandbox on kernels
# without Landlock (Unraid); it needs --security-opt seccomp=unconfined and systempaths=unconfined.
RUN apt-get update                              \
 && apt-get install -y --no-install-recommends  \
      bubblewrap                                \
      ca-certificates                           \
      curl                                      \
      git                                       \
      gosu                                      \
      python3                                   \
      tini                                      \
      xdg-user-dirs                             \
 && rm -rf /var/lib/apt/lists/*

RUN npm install -g "@deepseek-ai/dsh@${DSH_VERSION}" \
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
      org.opencontainers.image.base.name="node:24-slim"                                                              \
      org.opencontainers.image.base.digest="${BASE_DIGEST}"                                                          \
      net.unraid.docker.icon="https://raw.githubusercontent.com/0x1917/unraid-templates/master/assets/dsh/icon.png"  \
      net.unraid.docker.webui="http://[IP]:[PORT:3080]/"
