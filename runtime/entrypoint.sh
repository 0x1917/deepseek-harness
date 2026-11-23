#!/bin/sh
# dsh refuses wildcard binds, so listen on the container's own address.
set -eu

umask "${UMASK:-022}"

# As root: take on the host's UID/GID (Unraid: 99:100), fix ownership, re-run this script as dsh.
if [ "$(id -u)" = 0 ]; then
  groupmod -o -g "$PGID" dsh
  usermod -o -u "$PUID" -g "$PGID" dsh
  # /home/dsh is a volume, so a fresh one is empty: recreate the bin dir on PATH, and the
  # XDG Documents dir, which must point at /workspace (dsh's default workspace lives there).
  mkdir -p /home/dsh/.config /home/dsh/.local/bin
  echo 'XDG_DOCUMENTS_DIR="/workspace"' > /home/dsh/.config/user-dirs.dirs
  find /data /home/dsh \( ! -user dsh -o ! -group dsh \) -exec chown -h dsh:dsh {} +
  # Only claim /workspace when empty: a mounted share should already be owned by PUID/PGID.
  if [ -z "$(ls -A /workspace)" ]; then chown dsh:dsh /workspace; fi
  exec gosu dsh "$0" "$@"
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
