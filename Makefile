SHA ?= $(shell git rev-parse HEAD 2>/dev/null || echo dev)
BUILT_AT ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)
SMOKE_URL ?= http://127.0.0.1:8080
IMAGE_REPO := 000000000000.dkr.ecr.us-east-1.localhost:4566/zero-downtime-pipeline
IMAGE := $(IMAGE_REPO):sha-$(SHA)
GHCR := ghcr.io/abdelazizhachemi/zero-downtime-pipeline:sha-$(SHA)

.PHONY: test up image floci cluster secrets deploy smoke rollback import-postgres

test:
	npm --prefix app test

up:
	docker compose up --build

image:
	docker build \
		--provenance=false \
		--sbom=false \
		--build-arg GIT_SHA=$(SHA) \
		--build-arg BUILT_AT=$(BUILT_AT) \
		-t $(IMAGE) \
		-t $(GHCR) \
		.

floci:
	docker compose --profile floci pull floci
	docker compose --profile floci up -d floci

cluster:
	@k3d cluster list | awk 'NR>1 { print $$1 }' | grep -qx zdp \
		|| k3d cluster create zdp --port 8080:80@loadbalancer --agents 0
	$(MAKE) import-postgres

# ponytail: Docker's containerd snapshotter saves a pulled image with an OCI
# index whose nested blob is absent, and k3d import then fails. The docker
# manifest in the same tar is complete. Upgrade path: import postgres:16-alpine
# directly once save includes that blob.
import-postgres:
	docker save postgres:16-alpine -o /tmp/zdp-postgres.tar
	tar --delete -f /tmp/zdp-postgres.tar index.json oci-layout
	k3d image import /tmp/zdp-postgres.tar -c zdp
	rm -f /tmp/zdp-postgres.tar

secrets:
	@test -f .env || { echo 'Copy .env.example to .env' >&2; exit 1; }
	kubectl create namespace zdp --dry-run=client -o yaml | kubectl apply -f -
	kubectl -n zdp create secret generic api-secrets \
		--from-env-file=.env --dry-run=client -o yaml | kubectl apply -f -

deploy: secrets import-postgres
	@docker image inspect $(IMAGE) >/dev/null
	k3d image import $(IMAGE) -c zdp
	rm -rf /tmp/zdp-k8s && cp -a k8s /tmp/zdp-k8s
	cd /tmp/zdp-k8s && kustomize edit set image $(IMAGE_REPO)=$(IMAGE)
	printf '%s\n' \
		'apiVersion: apps/v1' \
		'kind: Deployment' \
		'metadata:' \
		'  name: api' \
		'  annotations:' \
		'    kubernetes.io/change-cause: sha-$(SHA)' \
		> /tmp/zdp-k8s/cause.yaml
	printf '\npatches:\n  - path: cause.yaml\n' >> /tmp/zdp-k8s/kustomization.yaml
	kubectl apply -k /tmp/zdp-k8s
	kubectl -n zdp rollout status deploy/api --timeout=180s

smoke:
	SMOKE_URL=$(SMOKE_URL) EXPECTED_SHA=$(SHA) ./scripts/smoke.sh

rollback:
	SMOKE_URL=$(SMOKE_URL) ./scripts/rollback.sh
