# 0002 — Git SHA tags, never latest

Status: accepted

## Decision

The Deployment tag is `sha-` plus the full `github.sha`. `:main` is pushed for humans and is never applied. `:latest` is forbidden because a rollback and a debug session cannot tell which bits are running.

`/version` reads `GIT_SHA` from the image environment set at build, so the process and the tag are the same value. Smoke fails if they differ.
