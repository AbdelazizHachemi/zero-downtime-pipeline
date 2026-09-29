#!/usr/bin/env bash
set -euo pipefail

ns=zdp
name=api

kubectl -n "$ns" rollout history "deploy/$name" >&2

rev="$(kubectl -n "$ns" get deploy "$name" -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}')"
prev="$((rev - 1))"
if [ "$prev" -lt 1 ]; then
  echo "no previous revision to roll back to" >&2
  exit 1
fi

image="$(kubectl -n "$ns" rollout history "deploy/$name" --revision="$prev" | awk '/Image:/ { print $2; exit }')"
sha="${image##*:sha-}"

kubectl -n "$ns" rollout undo "deploy/$name" >&2
kubectl -n "$ns" rollout status "deploy/$name" --timeout=180s >&2

if [ -n "${SMOKE_URL:-}" ]; then
  live="$(curl -fsS "${SMOKE_URL%/}/version")"
  live_sha="$(printf '%s' "$live" | sed -n 's/.*"sha":"\([^"]*\)".*/\1/p')"
  if [ -n "$live_sha" ]; then
    sha="$live_sha"
  fi
fi

if [ -z "$sha" ] || [ "$sha" = "$image" ]; then
  echo "could not read the previous SHA from rollout history" >&2
  exit 1
fi

printf '%s\n' "$sha"
