#!/usr/bin/env bash
set -euo pipefail

: "${SMOKE_URL:?SMOKE_URL is required}"
: "${EXPECTED_SHA:?EXPECTED_SHA is required}"

base="${SMOKE_URL%/}"

health="$(curl -fsS "${base}/health")"
printf '%s\n' "$health" | grep -q '"status":"ok"'

ready="$(curl -fsS "${base}/ready")"
printf '%s\n' "$ready" | grep -q '"status":"ready"'

version="$(curl -fsS "${base}/version")"
printf '%s\n' "$version" | grep -q "${EXPECTED_SHA}"
printf '%s\n' "$version"
