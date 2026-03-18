# Model Artifacts Runbook

## Source And Destination

- Upstream model source: `Qwen/Qwen3.5-27B-GPTQ-Int4`
- Lab storage destination: `s3://$S3_BUCKET/$S3_PREFIX/`

## Sync Workflow

Run:

```bash
make bootstrap
./bootstrap/model-sync.sh
```

The script:

1. Reads credentials from `local/s3.env`
2. Downloads the pinned Hugging Face model locally
3. Synchronizes model artifacts into the configured S3 prefix

## Validation

- Invalid S3 credentials or endpoint settings must cause observable sync failure
- Successful sync must populate the configured S3 prefix
- The serving stack must reference the same `s3://` location
