# Validation Summary

## Repository-Level Validation Completed

Validated without requiring a live cluster:

- `make validate-static`
- `./tests/validate-cluster.sh hosts`
- `./tests/validate-serving.sh static`
- `./tests/validate-observability.sh static`

## Expected Runtime Validation

These commands require a bootstrapped cluster:

- `./tests/validate-cluster.sh all`
- `./tests/validate-platform.sh all`
- `./tests/validate-serving.sh runtime`
- `./tests/validate-observability.sh runtime`
- `make smoke-test`

## Smoke Test Prerequisites

The smoke test requires:

- `LITELLM_BASE_URL=http://<infra-1-public-ip>:32080`
- `LITELLM_API_KEY=<valid-api-key>`

Without a reachable endpoint, the expected failure mode is a connection error from `curl`.
