# Model Artifacts Runbook

## Source And Destination

- Upstream model sources:
  - `openai/gpt-oss-20b`
  - `Qwen/Qwen3.5-9B`
- Lab storage destination: `s3://$S3_BUCKET/$S3_PREFIX/`
- Phase-1 canonical layout under that prefix:
  - `openai/gpt-oss-20b` -> `s3://$S3_BUCKET/$S3_PREFIX/openai__gpt-oss-20b/`
  - `Qwen/Qwen3.5-9B` -> `s3://$S3_BUCKET/$S3_PREFIX/Qwen__Qwen3.5-9B/`

## Sync Workflow

Run:

```bash
make bootstrap
./bootstrap/model-sync.sh
```

The script:

1. Reads credentials from `local/s3.env`
2. Downloads the pinned Hugging Face models locally
3. Synchronizes model artifacts into the configured S3 prefix using repository-safe subdirectories derived from the Hugging Face repo id

## Validation

- Invalid S3 credentials or endpoint settings must cause observable sync failure
- Successful sync must populate the configured S3 prefix
- The serving stack must reference the same `s3://` location and the same repo-derived subdirectory names
