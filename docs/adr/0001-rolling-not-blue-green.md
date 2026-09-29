# 0001 — Rolling, not blue/green

Status: accepted

## Decision

We use a rolling update because this is one small API with no schema change. Rolling needs half the replica budget of blue/green, one Service, and `kubectl rollout undo`. It only works with a readiness probe and `maxUnavailable: 0`. Otherwise the Service sends traffic to a pod that is still booting.

Blue/green runs two full fleets and switches. Rollback is instant and mixed versions never serve. It costs twice the pods. Use it when the new version cannot share the database shape or the API with the old one.

Canary needs traffic weights and a metric to promote on. Out of scope on one laptop node.

## Database rule

v1 has no migrations. Add columns and new code first, deploy the rolling update, then drop the old shape in a later release. A breaking `ALTER` during a rolling update is downtime, because old and new pods run at the same time.
