#!/usr/bin/env bash
# Load test script for the API
#
# Sends concurrent requests to the API /health endpoint to generate CPU load
# and trigger the HPA to scale up.
#
# Usage:
#   ./loadtest.sh [URL] [DURATION_SECONDS] [CONCURRENCY]

set -euo pipefail

URL="${1:-http://localhost:8080/health}"
DURATION="${2:-60}"
CONCURRENCY="${3:-10}"

echo "=== Load Test ==="
echo "Target:      $URL"
echo "Duration:    ${DURATION}s"
echo "Concurrency: $CONCURRENCY"
echo ""

# Check if 'hey' is installed for better load testing
if command -v hey &>/dev/null; then
  echo "Using 'hey' for load generation..."
  hey -z "${DURATION}s" -c "$CONCURRENCY" "$URL"
else
  echo "Using curl in a loop (install 'hey' for better results: go install github.com/rakyll/hey@latest)"
  echo ""

  END_TIME=$((SECONDS + DURATION))

  send_requests() {
    while [ $SECONDS -lt "$END_TIME" ]; do
      curl -s -o /dev/null -w "%{http_code}" "$URL"
      echo ""
    done
  }

  # Launch concurrent workers
  for i in $(seq 1 "$CONCURRENCY"); do
    send_requests &
  done

  echo "Load test running... (${DURATION}s remaining)"
  echo "Press Ctrl+C to stop early."
  wait

  echo ""
  echo "=== Load test complete ==="
fi
