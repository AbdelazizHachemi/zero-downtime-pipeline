# 0004 — ECR on Floci, not an AWS account

Status: accepted

## Decision

The image the cluster runs is pushed to ECR on Floci at `127.0.0.1:4566`. Floci speaks the ECR API and backs the registry with a real OCI registry, so `create-repository`, `get-login-password`, `docker push`, and `describe-images` are the same calls as AWS. There is no AWS account and no bill.

GHCR still receives the same SHA tag so the public repo has an image a recruiter can see. k3d imports the image after the push because the ECR hostname resolves to the host, not to the k3d node. ECS, EKS, and RDS stay unused. One registry API is the AWS experience this pipeline can defend.
