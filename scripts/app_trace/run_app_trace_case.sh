#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <case-name>"
  echo "Cases: init-success | init-already-initialized | decommission-single | decommission-two-nodes | decommission-custom"
  exit 1
fi

CASE_NAME="$1"
shift || true

COCKROACH_BIN="${COCKROACH_BIN:-cockroach}"
COCKROACH_HOST="${COCKROACH_HOST:-127.0.0.1:26257}"
COCKROACH_INSECURE="${COCKROACH_INSECURE:-true}"
TRACE_DIR="${TRACE_DIR:-$(pwd)/traces}"
TRACE_FILE="${TRACE_DIR}/${CASE_NAME}.json"

mkdir -p "${TRACE_DIR}"
rm -f "${TRACE_FILE}"

COMMON_FLAGS=("--host=${COCKROACH_HOST}")
if [[ "${COCKROACH_INSECURE}" == "true" ]]; then
  COMMON_FLAGS+=("--insecure")
else
  if [[ -z "${COCKROACH_CERTS_DIR:-}" ]]; then
    echo "COCKROACH_CERTS_DIR must be set when COCKROACH_INSECURE=false"
    exit 1
  fi
  COMMON_FLAGS+=("--certs-dir=${COCKROACH_CERTS_DIR}")
fi

export COCKROACH_APP_TRACE_ENABLED=true
export COCKROACH_APP_TRACE_PATH="${TRACE_FILE}"
export COCKROACH_APP_RECONCILE_ID="app/${CASE_NAME}#$(date +%s)"
export COCKROACH_APP_TRACE_ID="app/${CASE_NAME}-$(date +%s%N)"

run_init() {
  set +e
  "${COCKROACH_BIN}" init "${COMMON_FLAGS[@]}" "$@"
  rc=$?
  set -e
  return ${rc}
}

run_decommission() {
  local nodes="$1"
  shift
  if [[ -z "${nodes}" ]]; then
    echo "No target node IDs provided for decommission"
    exit 1
  fi
  "${COCKROACH_BIN}" node decommission ${nodes} "${COMMON_FLAGS[@]}" --wait=all "$@"
}

case "${CASE_NAME}" in
  init-success)
    echo "Running init-success..."
    if run_init "$@"; then
      echo "init succeeded"
    else
      echo "init failed (cluster may already be initialized)"
      exit 1
    fi
    ;;

  init-already-initialized)
    echo "Running init-already-initialized..."
    if run_init "$@"; then
      echo "init unexpectedly succeeded; cluster was likely not initialized yet"
      echo "Tip: run init-success first, then rerun this case"
      exit 1
    else
      echo "init failed as expected for already-initialized cluster"
    fi
    ;;

  decommission-single)
    echo "Running decommission-single..."
    nodes="${DECOMMISSION_NODES:-5}"
    run_decommission "${nodes}" "$@"
    ;;

  decommission-two-nodes)
    echo "Running decommission-two-nodes..."
    nodes="${DECOMMISSION_NODES:-4 5}"
    run_decommission "${nodes}" "$@"
    ;;

  decommission-custom)
    echo "Running decommission-custom..."
    nodes="${DECOMMISSION_NODES:-}"
    run_decommission "${nodes}" "$@"
    ;;

  *)
    echo "Unknown case: ${CASE_NAME}"
    exit 1
    ;;
esac

if [[ ! -f "${TRACE_FILE}" ]]; then
  echo "Trace file was not generated: ${TRACE_FILE}"
  exit 1
fi

python3 - <<PY
import json
p = "${TRACE_FILE}"
with open(p, "r", encoding="utf-8") as f:
    d = json.load(f)
print(f"Trace generated: {p}")
print(f"Event count: {len(d.get('events', []))}")
PY
