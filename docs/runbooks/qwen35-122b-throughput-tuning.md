# Qwen35-122B Throughput Tuning Plan

## Goal

Increase parallel request throughput for `qwen35-122b` without losing the currently proven-good startup path.

Current stable baseline:

- predictor source: local PVC cache at `/mnt/models`
- `tensor-parallel-size=2`
- `max-model-len=16384`
- `gpu-memory-utilization=0.85`
- `max-num-seqs=16`
- `enforce-eager`
- model status: `READY=True`

Known history:

- the aggressive pre-recovery profiles caused `vLLM` startup instability and `CrashLoopBackOff`
- startup failures previously included:
  - `Engine core initialization failed`
  - shared-memory / `shm_broadcast` failures
  - memory-pressure symptoms during engine init
- after moving to the conservative eager profile, the model became stable
- later stress testing showed that parallel requests still degraded or failed under load

## Rules

- Change one throughput-sensitive variable at a time.
- Do not combine multiple aggressive changes in a single rollout.
- Keep `LocalPV` cache and the current rollout pattern.
- Always preserve a known-good rollback target.
- Do not start by changing `max-model-len` to the extreme `524288` profile from `v2/v3`.

## Test Method

For every step:

1. Patch only the target parameter.
2. Roll out `qwen35-122b`.
3. Verify startup:
   - pod reaches `1/1 Running`
   - `InferenceService READY=True`
   - no restart loop
   - `vLLM` logs show successful API startup
4. Run the same stress test profile used previously.
5. Record:
   - success/failure rate
   - p50/p95 latency
   - timeout count
   - restart count
   - GPU memory usage
6. Stop escalation at the first unstable step.

## Recommended Escalation Order

### Step 0: Baseline

Keep:

- `max-model-len=16384`
- `gpu-memory-utilization=0.85`
- `max-num-seqs=16`
- `enforce-eager`

Collect a clean baseline stress result before any tuning.

### Step 1: Raise concurrency first

Change only:

- `max-num-seqs: 16 -> 24`

Why:

- this is the lowest-risk knob for parallel throughput
- it directly targets concurrent request handling

If stable, optionally test:

- `max-num-seqs: 24 -> 32`

Do not go beyond `32` before validating the later steps.

### Step 2: Raise GPU utilization carefully

Keep the best `max-num-seqs` from step 1.

Change only:

- `gpu-memory-utilization: 0.85 -> 0.88`

If stable, optionally test:

- `0.88 -> 0.90`

Why:

- this can improve usable KV cache headroom
- but it increases the risk of returning to startup fragility

Stop immediately if startup slows down dramatically or engine init becomes unstable.

### Step 3: Add batched token capacity

Keep the best settings from steps 1 and 2.

Add only:

- `max-num-batched-tokens=16384`

Why:

- this is directly aligned with throughput under concurrent load
- it is safer than changing to ultra-long context first

If stable and beneficial, test:

- `max-num-batched-tokens=24576`

Only if the first batched-token step is clean.

### Step 4: Reintroduce selective serving features

Keep the best settings from previous steps.

Test one at a time:

1. `enable-auto-tool-choice`
2. `tool-call-parser=qwen3_coder` only if tool-calling is required for the workload
3. `default-chat-template-kwargs={"enable_thinking":false}` if the test workload depends on it

Why:

- these affect behavior and overhead
- they are not the first knobs to use for raw concurrency

### Step 5: Revisit prefix caching last

Test only after the model is already stable under load.

Add:

- `enable-prefix-caching`

Why:

- it may help repeated prompts
- but it adds memory/runtime complexity and should not be an early tuning step

### Step 6: Increase context length only if explicitly needed

Do not jump to `524288`.

Use staged tests:

1. `max-model-len: 16384 -> 32768`
2. if stable and required, `32768 -> 65536`
3. stop there unless there is a hard product requirement for longer context

Why:

- extremely large context length strongly increases risk
- the earlier failures were consistent with over-aggressive startup and memory settings

## What Not To Do First

Do not start with the full `v2` or `v3` profile:

- `max-model-len=524288`
- `max-num-seqs=128`
- `max-num-batched-tokens=16384`
- `gpu-memory-utilization=0.9`
- `enable-prefix-caching`
- extra parser/template flags

Reason:

- too many variables change at once
- if the model fails, the root cause is unclear
- it recreates the exact class of aggressive profile that was unstable before recovery

## Suggested Milestones

### Milestone A: Safer throughput bump

Target:

- `max-num-seqs=24` or `32`
- `gpu-memory-utilization=0.88`
- optionally `max-num-batched-tokens=16384`
- keep `max-model-len=16384`
- keep `enforce-eager`

This is the recommended first candidate for the next real stress test.

### Milestone B: Moderate context profile

Target:

- best Milestone A settings
- `max-model-len=32768`

Only if the workload needs more context.

### Milestone C: Experimental high-risk profile

Use only after Milestones A and B are fully characterized.

Candidate:

- best prior settings
- optional `enable-prefix-caching`
- optional `gpu-memory-utilization=0.90`

This is the maximum-risk zone before touching the extreme `v2/v3` values.

## Rollback Rule

If any candidate causes one of the following:

- startup failure
- `CrashLoopBackOff`
- engine-init error
- sustained readiness failure
- materially worse stress-test success rate

Rollback immediately to the last known-good settings.

## Recommendation

The next practical candidate is:

- `max-model-len=16384`
- `gpu-memory-utilization=0.88`
- `max-num-seqs=24`
- `max-num-batched-tokens=16384`
- `enforce-eager`
- keep the current PVC-backed runtime path

This is the highest-signal next step because it targets parallel throughput directly while staying much closer to the stable recovery profile than `v2` or `v3`.
