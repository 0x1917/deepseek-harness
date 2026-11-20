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

# Comma-separated roots browsers use, e.g. "http://10.10.10.100:3080/,https://dsh.example.com/".
# dsh advertises only one (the first) and prints a login link for it alone.
urls=$(echo "${DSH_PUBLIC_URL:-http://localhost:$DSH_PORT/}" | tr ',' ' ')
first=${urls%% *}
others=${urls#"$first"}
set -- "$@" --public-url "$first"

if [ -z "$(echo "$others" | tr -d ' ')" ]; then
  exec dsh web "$@"
fi

# The launch token works on every trusted host, but the session cookie it is exchanged for
# is per host, so each address needs its own link: repeat dsh's for every other root.
# dsh's output goes through a FIFO to a reader rather than a pipe, so dsh is still exec'd: it
# stays tini's direct child, gets stop signals itself, and its exit status is the container's.
# The reader is a shell loop, not awk: Debian's mawk block-buffers input from a FIFO.
fifo=/tmp/dsh-output
rm -f "$fifo" && mkfifo "$fifo"
(
  seen=
  while IFS= read -r line; do
    printf '%s\n' "$line"
    case $line in
      *[?\&]token=*)
        [ -n "$seen" ] && continue
        seen=1
        token=${line##*token=}
        token=${token%%[!A-Za-z0-9_-]*}
        for url in $others; do
          case $url in *\?*) sep='&' ;; *) sep='?' ;; esac
          printf 'dsh web: %s%stoken=%s\n' "$url" "$sep" "$token"
        done
        ;;
    esac
  done
) < "$fifo" &
exec dsh web "$@" > "$fifo" 2>&1
