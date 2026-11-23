#!/usr/bin/env bash
# Check, or with --fix set, that the image's Node.js major and pnpm are what upstream builds
# the shipped release with, read at its dsh-v<DSH_VERSION> tag: Node from
# PRIMARY_NODE_VERSION in .github/workflows/ci-master.yml (the only Node its CI tests), pnpm
# from packageManager in package.json.
#
#   scripts/check-upstream-match.sh [--fix] [repo-dir]    (default: this repository)
#
# Without --fix it fails on a mismatch: lint runs it, so a Renovate dsh bump whose release
# moved either one goes red. With --fix it rewrites the Dockerfile to match instead:
# PNPM_VERSION, and the FROM line to node:<major>-trixie-slim pinned to that tag's current
# digest (needs docker buildx). Run it on the PR's branch and push the result.
set -euo pipefail

fix=false
if [ "${1:-}" = "--fix" ]; then fix=true; shift; fi
cd "${1:-$(dirname "$0")/..}"

dsh=$(sed -n 's/^ARG DSH_VERSION=//p' Dockerfile | head -1)
pnpm=$(sed -n 's/^ARG PNPM_VERSION=//p' Dockerfile | head -1)
node=$(sed -n 's/^FROM node:\([0-9]*\)-.*/\1/p' Dockerfile | head -1)
[ -n "$dsh" ] && [ -n "$pnpm" ] && [ -n "$node" ] || { echo "cannot read DSH_VERSION, PNPM_VERSION or the node FROM line" >&2; exit 1; }

raw="https://raw.githubusercontent.com/deepseek-ai/deepseek-harness/dsh-v$dsh"
up_pnpm=$(curl -fsSL --retry 3 "$raw/package.json" | jq -r '.packageManager // ""' | sed -n 's/^pnpm@\([^+]*\).*/\1/p')
up_node=$(curl -fsSL --retry 3 "$raw/.github/workflows/ci-master.yml" \
  | sed -n "s/^[[:space:]]*PRIMARY_NODE_VERSION:[[:space:]]*['\"]\{0,1\}\([0-9]*\).*/\1/p" | head -1)
case "$up_pnpm" in ""|*[!0-9A-Za-z.-]*) echo "cannot read upstream's pnpm at dsh-v$dsh: '$up_pnpm'" >&2; exit 1 ;; esac
case "$up_node" in ""|*[!0-9]*) echo "cannot read upstream's Node.js major at dsh-v$dsh: '$up_node'" >&2; exit 1 ;; esac

rc=0
if [ "$pnpm" = "$up_pnpm" ]; then
  echo "pnpm $pnpm matches upstream dsh-v$dsh"
elif $fix; then
  sed -i.bak "s/^ARG PNPM_VERSION=.*/ARG PNPM_VERSION=$up_pnpm/" Dockerfile && rm -f Dockerfile.bak
  echo "pnpm $pnpm -> $up_pnpm, as upstream dsh-v$dsh"
else
  echo "pnpm $pnpm, but upstream dsh-v$dsh builds with $up_pnpm: set ARG PNPM_VERSION=$up_pnpm" >&2; rc=1
fi

base="node:$up_node-trixie-slim"
if [ "$node" = "$up_node" ]; then
  echo "Node.js $node matches upstream dsh-v$dsh"
elif $fix; then
  digest=$(docker buildx imagetools inspect "$base" | sed -n 's/^Digest:[[:space:]]*\(sha256:[0-9a-f]\{64\}\)$/\1/p' | head -1)
  [ -n "$digest" ] || { echo "cannot resolve a digest for $base (is it published?)" >&2; exit 1; }
  sed -i.bak "s|^FROM node:[0-9]*-[^ ]*|FROM $base@$digest|" Dockerfile && rm -f Dockerfile.bak
  echo "Node.js $node -> $up_node, as upstream dsh-v$dsh: FROM $base@$digest"
else
  echo "Node.js $node, but upstream dsh-v$dsh tests on $up_node: switch FROM to $base (pinned by digest)" >&2; rc=1
fi
[ "$rc" = 0 ] || echo "to fix: run scripts/check-upstream-match.sh --fix on this branch and push" >&2
exit "$rc"
