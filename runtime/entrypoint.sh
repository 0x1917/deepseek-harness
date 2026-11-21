#!/bin/sh
# dsh refuses wildcard binds, so listen on the container's own address.
set -eu

umask "${UMASK:-022}"

# As root: take on the host's UID/GID (Unraid: 99:100), fix ownership, re-run this script as node.
if [ "$(id -u)" = 0 ]; then
  groupmod -o -g "$PGID" node
  usermod -o -u "$PUID" -g "$PGID" node
  find /data /home/node \( ! -user node -o ! -group node \) -exec chown -h node:node {} +
  # Only claim /workspace when empty: a mounted share should already be owned by PUID/PGID.
  if [ -z "$(ls -A /workspace)" ]; then chown node:node /workspace; fi
  exec gosu node "$0" "$@"
fi

host="${DSH_BIND:-$(hostname -i | awk '{print $1}')}"
set -- --host "$host" --port "$DSH_PORT" --no-open "$@"

# Comma-separated host names browsers use to reach the UI (e.g. "unraid.lan,10.10.10.100").
for h in $(echo "${DSH_TRUSTED_HOSTS:-localhost}" | tr ',' ' '); do
  set -- "$@" --trusted-host "$h"
done

# The printed login URL uses this root; set it to the address browsers actually use.
set -- "$@" --public-url "${DSH_PUBLIC_URL:-http://localhost:$DSH_PORT/}"

exec dsh web "$@"
