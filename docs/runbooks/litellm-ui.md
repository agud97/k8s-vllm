# LiteLLM UI Runbook

## Purpose

This runbook covers the DB-backed `LiteLLM` admin UI authentication flow used by this lab.

## Components

- `deployment/litellm -n llm`
- `statefulset/litellm-postgres -n llm`
- `service/litellm -n llm`
- `service/litellm-postgres -n llm`
- `secret/litellm-auth -n llm`
- `secret/litellm-postgres-auth -n llm`

## Local Inputs

`local/llm.env` must contain:

- `LITELLM_MASTER_KEY`
- `LITELLM_POSTGRES_PASSWORD`
- `LITELLM_UI_ADMIN_NAME`
- `LITELLM_UI_ADMIN_EMAIL`
- `LITELLM_UI_ADMIN_PASSWORD`
- `LITELLM_UI_ADMIN_ROLE`

The current deployment defaults the UI credentials to the same operator identity used for `Open WebUI`, but they can be split later if needed.

## Bootstrap

Apply or refresh the required app secrets:

```bash
./bootstrap/app-secrets.sh
```

Ensure the internal `LiteLLM` admin user exists and has the configured password:

```bash
./bootstrap/litellm-ui-user.sh
```

## Login

- URL: `http://<infra-1-public-ip>:32080/ui/`
- Login type: internal `LiteLLM` user
- Username/email: value of `LITELLM_UI_ADMIN_EMAIL`
- Password: value of `LITELLM_UI_ADMIN_PASSWORD`

## Validation

Check the database and app rollout:

```bash
kubectl -n llm rollout status statefulset/litellm-postgres
kubectl -n llm rollout status deployment/litellm
kubectl -n llm get pods -l app.kubernetes.io/name=litellm
kubectl -n llm get pods -l app.kubernetes.io/name=litellm-postgres
```

Check that the UI user exists:

```bash
source local/llm.env
curl -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -G --data-urlencode "user_id=$LITELLM_UI_ADMIN_EMAIL" \
  http://<infra-1-public-ip>:32080/user/info
```

## Failure Modes

`Authentication Error, Not connected to DB!`

- `LiteLLM` is running without a working `DATABASE_URL`
- verify `secret/litellm-postgres-auth`
- verify `statefulset/litellm-postgres`
- verify the active `LiteLLM` pod is the DB-backed revision

`/user/new` or `/user/update` returns a DB error

- `Postgres` is absent, unhealthy, or unreachable from `LiteLLM`
- check `kubectl -n llm logs deploy/litellm`
- check `kubectl -n llm logs statefulset/litellm-postgres`

New `LiteLLM` pod stalls during startup

- the DB-backed image can spend time applying Prisma migrations on first start
- if the pod is `OOMKilled`, increase memory in [`gitops/apps/litellm/deployment.yaml`](../../gitops/apps/litellm/deployment.yaml)

## Current Live Notes

- `LiteLLM` admin UI auth now uses in-cluster `Postgres`
- the current seeded admin user is `admin@openwebui.local`
- the current role is `proxy_admin`
