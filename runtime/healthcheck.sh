#!/bin/sh
# dsh has no health endpoint, and it listens on the container IP rather than loopback (the
# entrypoint binds there because dsh refuses wildcards), so probe that same address. Any
# HTTP reply, even 401, means the listener is up; only a dead socket fails.
host="${DSH_BIND:-$(hostname -i | awk '{print $1}')}"
exec curl -so /dev/null "http://$host:$DSH_PORT/"
