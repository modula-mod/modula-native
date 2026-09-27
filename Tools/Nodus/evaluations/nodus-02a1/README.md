# NODUS-02A.1 reviewed physical evaluations

This directory contains only reviewed, non-sensitive evidence that is safe to track in Git.
Raw device exports, private conversations, credentials, Memory, and user Knowledge stay outside the
repository.

`reviewed-interactions.jsonl` is generated with:

```bash
python3 Tools/Nodus/scripts/build_nodus_02a1_evidence.py \
  --conversations /private/path/conversations.json \
  --evaluations /private/path/developer-evaluations.json \
  --reviews /private/path/reviews.json \
  --output Tools/Nodus/evaluations/nodus-02a1/reviewed-interactions.jsonl
```

The review overlay is keyed by Nodus response message ID. Every emitted record must have a human
rating. Wrong, outdated, and hallucinated records must include a correction. Failure labels and root
causes use the controlled NODUS-02A.1 taxonomies enforced by the normalizer.

An empty `reviewed-interactions.jsonl` means no interaction has passed review yet; it is not evidence
of a passing acceptance run.
