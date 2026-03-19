#!/usr/bin/env bash
set -euo pipefail

POLICY_DIR="policy/spec"
SPEC_DIR="docs/spec"
REMARK="./node_modules/.bin/remark"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# Collect all spec filenames as a JSON array for cross-file checks
all_filenames=$(printf '%s\n' "$SPEC_DIR"/*.md | xargs -I{} basename {} | jq -MRs 'split("\n") | map(select(. != ""))')

# Phase 1: Convert all markdown specs to JSON ASTs in parallel
for file in "$SPEC_DIR"/*.md; do
  [ -f "$file" ] || continue
  name=$(basename "$file")

  is_feature=false
  is_perf=false
  if [[ "$name" == *_feature_* ]]; then
    is_feature=true
  fi
  if [[ "$name" == *_perf_* ]]; then
    is_perf=true
  fi

  metadata=$(jq -Mn \
    --arg filename "$name" \
    --argjson is_feature "$is_feature" \
    --argjson is_perf "$is_perf" \
    --argjson all_filenames "$all_filenames" \
    '{metadata: {filename: $filename, is_feature: $is_feature, is_perf: $is_perf, all_filenames: $all_filenames}}')

  (
    "$REMARK" --tree-out < "$file" 2>/dev/null \
      | jq -M -s ".[0] * $metadata" \
      > "$tmpdir/$name"
  ) &
done

wait

# Phase 2: Run conftest once on all files, show PASS and FAIL in table format
conftest test --parser json --policy "$POLICY_DIR" "$tmpdir"/*.md \
  | sed "s|$tmpdir/||g"
