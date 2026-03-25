# Local Secrets And Inventory

Create these local files before running bootstrap:

- `local/hosts.yml`
- `local/s3.env`
- `local/llm.env`

These files are ignored by Git. Use the matching `*.example` files as templates.

What goes where:

- `local/hosts.yml`: server IPs, SSH user, SSH passwords or SSH keys, host groups, and control-plane `access_ip` values when workers join over public IPs
- `local/s3.env`: S3 endpoint, bucket name, access key, secret key, optional region, prefix
- `local/llm.env`: LiteLLM master key and Open WebUI bootstrap admin credentials

Important note for node replacement:

- if new worker nodes cannot reach control-plane private IPs, set `access_ip` on `cp-1`, `cp-2`, and `cp-3` to the reachable public API addresses before rendering inventory
