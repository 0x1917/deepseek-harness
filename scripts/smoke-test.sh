#!/usr/bin/env bash
# Smoke test for the deepseek-harness image: boot it the way the Unraid template
# does and walk the paths that have broken before. Everything runs in one
# disposable container and a throwaway data dir, removed on exit.
#
#   scripts/smoke-test.sh [image]        (default: deepseek-harness:test)
#
# The command sandbox check runs bubblewrap, the path Unraid takes (its kernel
# has no Landlock). Ubuntu 24.04 runners add two AppArmor restrictions Unraid
# doesn't have, so CI lifts both to test the Unraid path:
#   sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
#   SMOKE_DOCKER_ARGS="--security-opt apparmor=unconfined"
#
# Requires: docker, curl, bash. ~30 s.
set -euo pipefail

IMAGE=${1:-deepseek-harness:test}
# Extra `docker run` arguments, word-split on purpose.
read -r -a EXTRA <<< "${SMOKE_DOCKER_ARGS:-}"
NAME=dsh-smoke-$$
DATA=$(mktemp -d)
JAR="$DATA/cookies"
TRUSTED=dsh.smoke.test

cleanup() {
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  # The entrypoint re-owns the mounts to 99:100, so a non-root runner cannot
  # unlink them; the image itself (as root) can. Cleanup never decides the verdict.
  docker run --rm --entrypoint rm -v "$DATA:/d" "$IMAGE" -rf /d/data /d/workspace >/dev/null 2>&1 || true
  rm -rf "$DATA" 2>/dev/null || echo "note: left $DATA behind" >&2
}
trap cleanup EXIT
pass() { printf 'PASS  %s\n' "$1"; }
die()  { printf 'FAIL  %s\n' "$1" >&2; docker logs "$NAME" 2>&1 | tail -25 >&2 || true; exit 1; }
code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }

mkdir -p "$DATA/data" "$DATA/workspace"
docker run -d --name "$NAME" -p 127.0.0.1::3080                          \
  --security-opt seccomp=unconfined --security-opt systempaths=unconfined \
  -e DSH_TRUSTED_HOSTS="$TRUSTED" "${EXTRA[@]}"                           \
  -v "$DATA/data:/data" -v "$DATA/workspace:/workspace" "$IMAGE" >/dev/null
PORT=$(docker port "$NAME" 3080/tcp | head -1 | sed 's/.*://')
U="http://127.0.0.1:$PORT"

for _ in $(seq 1 60); do
  [ "$(docker inspect -f '{{.State.Running}}' "$NAME")" = true ] || die "container exited during startup"
  [ "$(docker inspect -f '{{.State.Health.Status}}' "$NAME")" = healthy ] && break
  sleep 2
done
[ "$(docker inspect -f '{{.State.Health.Status}}' "$NAME")" = healthy ] || die "healthcheck never passed"
pass "container is healthy"

want=$(docker image inspect -f '{{index .Config.Labels "org.opencontainers.image.version"}}' "$IMAGE")
got=$(docker exec -u node "$NAME" dsh --version | tail -1)
[ -n "$want" ] && [ "$got" = "$want" ] || die "dsh --version is '$got', image label says '$want'"
pass "dsh $got matches the image version label"

# No ps in the image, and node renames its process to MainThread: match the command line.
ids=$(docker exec "$NAME" sh -c 'for p in /proc/[0-9]*; do
  [ "${p#/proc/}" = "$$" ] && continue
  if tr "\0" " " < "$p/cmdline" 2>/dev/null | grep -q "dsh web"; then
    awk "/^Uid:/{u=\$2} /^Gid:/{g=\$2} END{print u\":\"g}" "$p/status"
  fi
done' | sort -u)
[ "$ids" = "99:100" ] || die "dsh runs as '$ids', expected 99:100"
pass "dsh runs as 99:100"

owner=$(docker exec "$NAME" stat -c '%u:%g' /data /workspace | sort -u)
[ "$owner" = "99:100" ] || die "/data and /workspace are owned by '$owner'"
pass "/data and the empty /workspace are owned by 99:100"

docs=$(docker exec -u node "$NAME" xdg-user-dir DOCUMENTS)
[ "$docs" = /workspace ] || die "XDG Documents is '$docs', the default workspace cannot be created"
pass "XDG Documents points at /workspace"

docker exec -u node "$NAME" bwrap --ro-bind / / --dev /dev --proc /proc --unshare-pid --unshare-user true \
  || die "bubblewrap cannot create a sandbox"
pass "bubblewrap sandbox works"

token=$(docker logs "$NAME" 2>&1 | grep -o 'token=[A-Za-z0-9_-]*' | tail -1)
[ -n "$token" ] || die "no login URL in the log"
[ "$(code "$U/")" = 401 ] || die "the UI answers without a session"
[ "$(code -c "$JAR" "$U/?$token")" = 303 ] || die "the launch token was not exchanged for a session"
[ "$(code -b "$JAR" -o "$DATA/index.html" "$U/")" = 200 ] || die "the UI refused a valid session"
pass "launch token login (401 without a session, 303 exchange, 200 with the cookie)"

bundle=$(curl -s -b "$JAR" "$U/" | grep -o 'src="plugins/[^"]*"' | head -1 | sed 's/^src="//; s/"$//; s/&amp;/\&/g')
[ -n "$bundle" ] || die "the UI document references no client bundle"
[ "$(code -b "$JAR" "$U/$bundle")" = 200 ] || die "the client bundle does not load"
pass "client bundle loads"

[ "$(code -b "$JAR" -H "Host: evil.invalid:$PORT" "$U/api/")" = 403 ] || die "an untrusted Host was not fenced"
[ "$(code -b "$JAR" -H "Host: $TRUSTED:$PORT" "$U/api/")" != 403 ] || die "DSH_TRUSTED_HOSTS was not applied"
pass "host fence: untrusted Host gets 403, DSH_TRUSTED_HOSTS is admitted"

echo "smoke test passed: $IMAGE"
