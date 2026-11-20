FROM node:24-slim

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

COPY entrypoint.sh /usr/local/bin/entrypoint.sh

ENV DSH_HOME=/data  \
    DSH_PORT=3080   \
    PUID=99         \
    PGID=100

# dsh puts its default workspace under the XDG Documents dir; point that at /workspace.
RUN mkdir -p /data /workspace /home/node/.config  \
 && echo 'XDG_DOCUMENTS_DIR="/workspace"'         \
 > /home/node/.config/user-dirs.dirs

# Starts as root; entrypoint.sh remaps node to PUID/PGID and drops to it via gosu.
WORKDIR /workspace
VOLUME ["/data", "/workspace"]
EXPOSE 3080

# dsh has no health endpoint and only listens on the container IP; any HTTP reply (even 401) means it's up.
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3  \
  CMD curl -so /dev/null "http://${DSH_BIND:-$(hostname -i              \
  | awk '{print $1}')}:${DSH_PORT}/"                                    \
  || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]

LABEL org.opencontainers.image.title="DeepSeek Harness"                                  \
      org.opencontainers.image.description="An open-source AI coding agent."             \
      org.opencontainers.image.source="https://github.com/deepseek-ai/deepseek-harness"  \
      org.opencontainers.image.licenses="MIT"                                            \
      org.opencontainers.image.version="${DSH_VERSION}"
