# Local Secrets And Inventory

Create these local files before running bootstrap:

- `local/hosts.yml`
- `local/s3.env`
- `local/llm.env`

These files are ignored by Git. Use the matching `*.example` files as templates.

What goes where:

- `local/hosts.yml`: server IPs, SSH user, SSH passwords, host groups
- `local/s3.env`: S3 endpoint, bucket name, access key, secret key, optional region, prefix
- `local/llm.env`: LiteLLM master key and Open WebUI bootstrap admin credentials
