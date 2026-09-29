# Technical guide

This is the interview map for the zero-downtime pipeline. The README is the front door. This file is where each claim lives in the repo.

The API is one NestJS process on port 3000. It has no ORM. `pg` has one pool and one query, `SELECT 1`. Kubernetes rolls three replicas with `maxUnavailable: 0`. Smoke checks `/health`, `/ready`, and `/version`. A failed rollout or a failed smoke runs `kubectl rollout undo`. Production is a GitHub Environment approval on the same cluster, not a second region.

## What happens during a rollout

1. The new pod starts. It is not in the Service.
2. The startup probe calls `GET /health` until the process answers. Liveness is idle until startup succeeds, so a slow boot is not killed.
3. The readiness probe calls `GET /ready`. That runs `SELECT 1` with a 1 second timeout. On 200 the pod receives traffic. On 503 it stays running and receives none.
4. One old pod is terminated. `preStop` sleeps 5 seconds so endpoints stop sending before the process exits. Then `SIGTERM`. `enableShutdownHooks()` makes Nest stop accepting and finish in-flight work. `terminationGracePeriodSeconds: 30` covers the sleep plus that work. Then `SIGKILL` if it is still alive.
5. Repeat until every pod runs the new SHA. `minReadySeconds: 5` waits before the next pod is taken.

`GET /health` is liveness only. It must not touch Postgres. Pointing liveness at `/ready` turns a database blip into a restart of every pod.

A PodDisruptionBudget of `minAvailable: 2` stops a node drain from evicting the Deployment down to one pod. Without it, the zero-downtime claim is false during drains.

Rolling is the wrong tool when the new code cannot run beside the old code: a breaking API, a destructive SQL change, or a single replica that holds a lock. This API has no schema changes.

## File map

| Path | What it is |
| --- | --- |
| `app/src/main.ts` | Listens on `PORT` or 3000, enables shutdown hooks, writes one JSON access line |
| `app/src/health.controller.ts` | `GET /health`. No database |
| `app/src/ready.controller.ts` | `GET /ready`, including `READY_FAIL` |
| `app/src/version.controller.ts` | `GET /version` from `GIT_SHA` and `BUILT_AT` |
| `app/src/db.service.ts` | Lazy `pg` pool, `SELECT 1`, 1s timeouts, idle-client error handler |
| `app/test/` | Jest. Health must not call `Pool`. Ready is 503 without `DATABASE_URL`. Version returns `GIT_SHA` |
| `Dockerfile` | Multi-stage `node:22-alpine` pinned by digest. Non-root. Build args baked into the image |
| `docker-compose.yml` | Phase A: API and Postgres. Profile `floci`: the AWS emulator |
| `k8s/deployment.yaml` | 3 replicas, rolling numbers, probes, `preStop`, resources |
| `k8s/service.yaml` | LoadBalancer, port 80 to container 3000 |
| `k8s/pdb.yaml` | `minAvailable: 2` |
| `k8s/postgres.yaml` | `postgres:16-alpine`, emptyDir, password from the Secret |
| `k8s/kustomization.yaml` | Namespace `zdp`, image tag `sha-REPLACE` |
| `scripts/smoke.sh` | Requires `SMOKE_URL` and `EXPECTED_SHA` |
| `scripts/rollback.sh` | Undo, wait, print the SHA that is now serving |
| `Makefile` | `test`, `up`, `image`, `floci`, `cluster`, `secrets`, `deploy`, `smoke`, `rollback` |
| `.github/workflows/ci.yml` | Pull requests and pushes to `main`. No Docker build |
| `.github/workflows/deploy.yml` | Build, scan, staging, smoke, rollback, production gate |
| `docs/adr/` | Why rolling, why SHA tags, why environments, why Floci |

The Secret `api-secrets` is created from a gitignored `.env`. The manifests name the Secret. They do not contain the password. Do not put `GIT_SHA` in that Secret. `envFrom` would override the value baked into the image, and smoke would fail a deploy that was otherwise fine.

## Pipeline jobs

`ci.yml` runs four jobs in parallel on `ubuntu-latest`:

| Job | Fails when |
| --- | --- |
| `lint` | eslint, prettier, or `tsc --noEmit` fails |
| `test` | a test fails |
| `sast` | Trivy filesystem scan finds HIGH or CRITICAL |
| `manifests` | `kustomize build k8s` piped to `kubeconform -strict` is invalid |

`deploy.yml` starts from `workflow_run` after `ci` succeeds on `main`, or from `workflow_dispatch` with `action` of `deploy` or `rollback`.

| Job | Runner | What |
| --- | --- | --- |
| `build` | self-hosted, label `k3d` | Buildx. Push the SHA tag to GHCR and to Floci ECR. `describe-images` must show the tag. Skipped on rollback |
| `image-scan` | `ubuntu-latest` | Trivy image scan of that GHCR tag. Same severity and exit code. Skipped on rollback |
| `deploy-staging` | self-hosted `k3d`, environment `staging` | `make deploy` |
| `smoke-staging` | self-hosted `k3d`, environment `staging` | `scripts/smoke.sh` |
| `rollback` | self-hosted `k3d` | If staging deploy or smoke failed, or the dispatch action is rollback. Then smoke the previous SHA |
| `deploy-prod` | self-hosted `k3d`, environment `production` | Same apply, after the reviewer |
| `smoke-prod` | self-hosted `k3d`, environment `production` | Same smoke |

The build job's permissions are `contents: read` and `packages: write`. Buildx pushes with provenance and SBOM turned off so the tag is a normal image manifest. Cache is `type=gha`.

If `rollout status` times out, the new pod never became Ready and the old pods are still serving, because `maxUnavailable` is 0. The rollback job runs `kubectl rollout undo` anyway so the failed revision is not left half-applied.

`make deploy` copies `k8s/` to a temp directory before `kustomize edit set image`, so a local deploy does not dirty the committed tag `sha-REPLACE`.

## What was measured

Laptop, 29 September 2026. These are command results, not an Actions run.

- Jest: 4 passed. Lint and `tsc --noEmit` passed.
- Compose: `/health`, `/ready`, and `/version` returned the documented bodies. After `docker stop` on Postgres, `/health` and `/version` stayed 200 and `/ready` returned 503. The process did not exit. `/ready` returned 200 again after Postgres started.
- Trivy filesystem scan of `app/package-lock.json`, HIGH and CRITICAL: 0. Trivy image scan of the runtime image: 0 after the Alpine upgrade and the removal of the unused npm tree.
- `docker image ls` on the API image: 269 MB. Pinned base `node:22-alpine@sha256:16e22a550f3863206a3f701448c45f7912c6896a62de43add43bb9c86130c3e2` is about 230 MB, which is already over the 150 MB budget. The base was kept.
- k3d cluster `zdp`, three API pods Ready, PDB present.
- During `make deploy` of a second SHA, 466 curls of `/version` at about 10 per second were all HTTP 200. The first body was the old SHA. The last body was the new SHA. `kubectl -n zdp rollout history deploy/api` showed both SHAs as change causes.
- `READY_FAIL=true` made `rollout status` time out. The Service kept returning the previous SHA and `/ready` 200. One new pod stayed unready. Rollback restored that SHA.

Floci 2.1.0 (`sha256:f5aa8c18302cedb4f2385f5c4e455b3efc77fee6bf7b6e5d1712b2817ba102db`) accepted `create-repository`, `get-login-password`, `docker push`, and `describe-images` for `sha-plaintest`. Floci 1.7.0, the image that was already on the machine, pushed the blob and then returned no image details. `make floci` pulls before it starts.

Kubeconform, strict, Kubernetes 1.31: 6 resources, 0 invalid.

GitHub Actions has not run. The README says so on purpose.

## Interview questions

### Why does a rollout not drop traffic?

The Service only includes Ready pods. The new pod is not Ready until `/ready` returns 200. `maxUnavailable: 0` means an old pod is not removed until a new one is Ready. `maxSurge: 1` is the extra pod that makes that possible. The node needs spare CPU and memory. If the surge pod cannot schedule, the rollout hangs. That is a capacity fact, not a YAML fact.

Where: `k8s/deployment.yaml` (`replicas`, `strategy`, `readinessProbe`) and `k8s/service.yaml`.

### What is the difference between liveness and readiness?

Liveness restarts the process. Readiness removes traffic. Swapping them turns a database blip into a restart loop. `/health` does not open a connection. The test spies on `Pool.prototype.query` and `Pool.prototype.connect` and fails if `/health` calls either.

Where: `app/src/health.controller.ts`, `app/src/ready.controller.ts`, `app/test/health.spec.ts`.

### Why did the process die when Postgres stopped, the first time?

`pg` emits `error` on an idle client when the server closes the connection. With no listener, Node exits. The pool now handles that event and logs one JSON line to stderr. The next `/ready` fails the query and returns 503. The process stays up. That is the difference between a blip and an outage.

Where: `app/src/db.service.ts`.

### What does the startup probe buy you?

It replaces `initialDelaySeconds` on liveness. Liveness does not run until startup succeeds. The threshold is 12 periods of 5 seconds, so a slow Nest boot has about a minute before it is killed.

Where: `k8s/deployment.yaml`, field `startupProbe`.

### Why sleep in `preStop`?

Endpoints are removed asynchronously. A 5 second sleep gives them time to stop sending before the process exits. Nest then handles `SIGTERM` because `main.ts` calls `enableShutdownHooks()`. Thirty seconds of grace covers the sleep and in-flight requests.

Where: `k8s/deployment.yaml` (`lifecycle.preStop`, `terminationGracePeriodSeconds`) and `app/src/main.ts`.

### Why `maxUnavailable: 0` if I already have three replicas?

Three replicas do not help if the strategy is allowed to take one down before the replacement is Ready. `maxUnavailable: 0` is the line that keeps capacity. It is also why a timed-out rollout still serves the old SHA. We saw that: the new pod was `0/1`, three old pods were `1/1`, and `/version` did not change.

Where: `k8s/deployment.yaml`. The failure run is described in the README.

### What does the PodDisruptionBudget do?

`minAvailable: 2` on pods labeled `app: api`. A voluntary disruption, such as a drain, cannot take the Deployment below two ready pods. It does not stop a crash or a failed readiness probe. It stops the drain-shaped outage that rolling settings do not cover.

Where: `k8s/pdb.yaml`.

### Why is the tag `sha-<git sha>` and not `latest` or `main`?

`:latest` cannot tell a rollback from a debug session which bits are running. `:main` is pushed for humans and is never applied. `/version` reads `GIT_SHA` from the environment set at `docker build`, so the process and the tag are the same value. Smoke fails if the body does not contain `EXPECTED_SHA`.

Where: `Dockerfile` (`ARG`/`ENV`), `app/src/version.controller.ts`, `k8s/kustomization.yaml`, `scripts/smoke.sh`, [ADR 0002](adr/0002-git-sha-tags-never-latest.md).

### Why not a ConfigMap for the SHA?

A ConfigMap can be edited without changing the image. The running process would then report a SHA it was not built from. The image has to report itself.

Where: `Dockerfile` and `app/src/version.controller.ts`.

### A team of one has no reviewer. How is production gated?

Environment `production` requires a reviewer. The second account is that click. A company uses a team. A `sleep` in the workflow is not a gate, because the run approves itself.

Where: `deploy.yml` jobs `deploy-prod` and `smoke-prod`, environment `production`. [ADR 0003](adr/0003-github-environments.md).

### Why is the kubeconfig on the runner?

The cluster is local k3d. GitHub-hosted runners cannot reach it, and a long-lived cloud key would teach the wrong lesson. The company version of this job presents a short-lived OIDC token scoped to namespace `zdp`. Say that sentence. The README says it so the interview matches the repo.

Where: README section "Identity". `deploy.yml` `runs-on: [self-hosted, k3d]`.

### Why is staging the same namespace as production?

One laptop, one cluster. Faking a second cluster would be a diagram, not a system. The thing being demonstrated is the approval gate plus a second smoke.

Where: `deploy.yml`. Both jobs call `make deploy` against namespace `zdp`.

### When is rolling the wrong tool?

When the new version cannot share the database shape or the API with the old one, or when a singleton holds a lock. Blue/green runs two full fleets and switches. Rollback is instant and mixed versions never serve. It costs twice the pods. Canary needs traffic weights and a metric. That is out of scope on one node.

Database rule, even though v1 has no migrations: add columns and new code first, roll out, then drop the old shape in a later release. A breaking `ALTER` during a rolling update is downtime, because both versions run at once.

Where: [ADR 0001](adr/0001-rolling-not-blue-green.md).

### What is Floci doing here, and what is it not?

Floci speaks the ECR API and backs it with a real registry. `create-repository`, `get-login-password`, `docker push`, and `describe-images` are the same calls as AWS. There is no AWS account. The tested control-plane port is 4566. The image URI on Floci 2.1 is `000000000000.dkr.ecr.us-east-1.localhost:4566/zero-downtime-pipeline:sha-<full sha>`. This is not production AWS. ECS, EKS, and RDS are unused.

k3d imports the image because that hostname points at the host, not at the k3d node. A company cluster would pull with an IAM role.

GHCR still receives the SHA tag so the public repo has an image a recruiter can open without the laptop.

Where: `docker-compose.yml` service `floci`, `deploy.yml` job `build`, [ADR 0004](adr/0004-ecr-on-floci.md).

### Why did `describe-images` lie on the first try?

The machine had Floci 1.7.0. `docker push` succeeded and the registry catalog listed the tag. `describe-images` returned no image details. That bug is fixed in current Floci by resolving the backing registry from the control plane. Floci 2.1.0 returned the tag. `make floci` pulls so a stale local image is not the gate.

Where: `Makefile` target `floci`.

### Why import Postgres with a tar edit?

`k3d image import postgres:16-alpine` failed on Docker's containerd snapshotter. `docker save` wrote an OCI index whose nested blob was not in the tar, and `ctr` inside the node aborted. The docker `manifest.json` in that tar has the layers. `make import-postgres` drops `index.json` and imports the rest. The Deployment still runs `postgres:16-alpine`. The ceiling is this Docker and k3d pair. The upgrade path is importing the image directly once `docker save` includes that blob.

Where: `Makefile` target `import-postgres`.

### Why is the Service a LoadBalancer?

k3d's `--port 8080:80@loadbalancer` publishes the load balancer, not a ClusterIP. A LoadBalancer Service on port 80 is how host port 8080 reaches the API. v1 has no Ingress. Smoke talks to `SMOKE_URL`, default `http://127.0.0.1:8080`.

Where: `k8s/service.yaml`, `Makefile` target `cluster`.

### Why `imagePullPolicy: IfNotPresent`?

The node never pulls the ECR hostname. The image is imported. `IfNotPresent` uses that import. `Always` would try the registry inside the node and the pod would stay pending.

Where: `k8s/deployment.yaml`.

### What does smoke actually check?

`SMOKE_URL` and `EXPECTED_SHA` are required. `curl -fsS` against `/health`, `/ready`, and `/version`. The version body must contain the expected SHA. Anything else exits non-zero. `curl -f` treats 503 as failure, so a not-ready Service fails the job.

Where: `scripts/smoke.sh`.

### How does rollback know the previous SHA?

It does not hardcode one. It reads the previous ReplicaSet image from `kubectl rollout history --revision`, undoes the Deployment, waits, then prefers the SHA from the live `/version` when `SMOKE_URL` is set. Stdout is that SHA and nothing else. The workflow smokes it.

Where: `scripts/rollback.sh`. Change causes are written by `make deploy` so `kubectl rollout history` shows `sha-...`.

### What is `READY_FAIL`?

An env switch, off by default. If it is `true`, `/ready` returns 503 and does not call the database. The failure-injection commit sets it on the API container and changes nothing else. There is no timer, no feature-flag service, and no second image. The test spies on `DbService.ping` and fails if the flag still hits the database.

Where: `app/src/ready.controller.ts`, `app/test/ready.spec.ts`.

### Why is the image 269 MB?

`docker image ls` says 269 MB. The pinned `node:22-alpine` digest is about 230 MB before application code. Deleting npm in a later layer does not shrink the parent layer, so it does not change that number. It does remove the HIGH and CRITICAL findings Trivy reported in the base image's bundled npm, and `apk upgrade` moves `libcrypto3` and `libssl3` to the fixed Alpine packages. The scan of the image we ship was clean at HIGH and CRITICAL.

Where: `Dockerfile`.

### What is intentionally absent?

DevLearnOps. Blue/green, canary, Argo Rollouts, Istio, NGINX weights. Helm, Terraform, Prometheus, Grafana. A schema, a migration runner, a persistent volume. Ingress. A real AWS account. A coverage gate. The suite is four tests. A floor can wait until it is bigger.

Postgres data is an `emptyDir`. It dies with the pod. That is acceptable because this repo proves deploys, not durability.

## Resume lines

Use these only after the Actions failure demo and the three screenshots exist. Until then they describe intent.

- Built a GitHub Actions pipeline (lint, tests, Trivy, image scan, GHCR) that rolling-deploys a NestJS API to Kubernetes with a manual production environment gate.
- Added post-deploy smoke tests on `/health`, `/ready`, and `/version`, and `kubectl rollout undo` when smoke or rollout status fails.
- Documented why rolling was chosen over blue/green, including the PodDisruptionBudget, readiness versus liveness, and migration ordering.
- Pushed the same image tag to ECR on Floci, a local AWS emulator at port 4566, and gated the deploy on `aws ecr describe-images`.
