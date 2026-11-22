#!/usr/bin/env bash
# Fail when the image's Node.js major or pnpm differs from what upstream builds the shipped
# release with, read at its dsh-v<DSH_VERSION> tag: Node from PRIMARY_NODE_VERSION in
# .github/workflows/ci-master.yml (the only Node its CI tests), pnpm from packageManager in
# package.json.
#
# Renovate keeps pnpm in step by itself. It cannot move the base image's major without
# dropping its digest pin, so it proposes no node majors; when upstream moves, this check
# fails the dsh bump's PR and names the base image to switch to.
#
#   scripts/check-upstream-match.sh
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

dsh=$(sed -n 's/^ARG DSH_VERSION=//p' Dockerfile | head -1)
pnpm=$(sed -n 's/^ARG PNPM_VERSION=//p' Dockerfile | head -1)
node=$(sed -n 's/^FROM node:\([0-9]*\)-.*/\1/p' Dockerfile | head -1)
[ -n "$dsh" ] && [ -n "$pnpm" ] && [ -n "$node" ] || { echo "cannot read DSH_VERSION, PNPM_VERSION or the node FROM line" >&2; exit 1; }

raw="https://raw.githubusercontent.com/deepseek-ai/deepseek-harness/dsh-v$dsh"
up_pnpm=$(curl -fsSL --retry 3 "$raw/package.json" | jq -r '.packageManager // ""' | sed -n 's/^pnpm@\([^+]*\).*/\1/p')
up_node=$(curl -fsSL --retry 3 "$raw/.github/workflows/ci-master.yml" \
  | sed -n "s/^[[:space:]]*PRIMARY_NODE_VERSION:[[:space:]]*['\"]\{0,1\}\([0-9]*\).*/\1/p" | head -1)
[ -n "$up_pnpm" ] && [ -n "$up_node" ] || { echo "cannot read upstream's pnpm or Node version at dsh-v$dsh" >&2; exit 1; }

rc=0
if [ "$pnpm" = "$up_pnpm" ]; then echo "pnpm $pnpm matches upstream dsh-v$dsh"
else echo "pnpm $pnpm, but upstream dsh-v$dsh builds with $up_pnpm: set ARG PNPM_VERSION=$up_pnpm" >&2; rc=1; fi
if [ "$node" = "$up_node" ]; then echo "Node.js $node matches upstream dsh-v$dsh"
else echo "Node.js $node, but upstream dsh-v$dsh tests on $up_node: switch FROM to node:$up_node-trixie-slim (pinned by digest)" >&2; rc=1; fi
exit "$rc"
