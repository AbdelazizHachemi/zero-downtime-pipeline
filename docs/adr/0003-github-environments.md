# 0003 — GitHub Environments

Status: accepted

## Decision

`staging` deploys with no reviewer, on a green `main`. `production` requires a reviewer so the Actions UI shows a real gate. A solo maintainer uses a second GitHub account for that click. A company would use a team, plus OIDC from GitHub to the cluster, instead of a kubeconfig sitting on a runner.

This repo uses the runner kubeconfig because the cluster is local k3d and a long-lived cloud credential is the wrong lesson. Staging and production share one namespace on purpose. The gate is the thing being demonstrated, not a second region.
