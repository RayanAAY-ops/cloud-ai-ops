#!/usr/bin/env bash
# Invoke the app Lambda with a sample item.
#
#   ./invoke.sh          # once, on dev
#   ./invoke.sh dev 3    # 3 times (same minute -> the Errors metric shows 3)
#
# While dynamodb:PutItem is disabled (terraform/role.tf), every call returns
# "FunctionError": "Unhandled" with an AccessDeniedException. That's expected.
set -euo pipefail

ENV="${1:-dev}"
COUNT="${2:-1}"
FUNCTION="cloudops-ai-app-${ENV}"
RESPONSE="$(mktemp)"
trap 'rm -f "$RESPONSE"' EXIT

for i in $(seq 1 "$COUNT"); do
  echo "--- invoke $i/$COUNT: $FUNCTION"
  aws lambda invoke \
    --no-cli-pager \
    --function-name "$FUNCTION" \
    --cli-binary-format raw-in-base64-out \
    --payload '{"item_name": "Widget", "price": 9.99}' \
    "$RESPONSE"
  echo "Response:"
  cat "$RESPONSE"
  echo
done
