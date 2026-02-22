#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START_CLUSTER="${START_CLUSTER:-true}"
STOP_CLUSTER="${STOP_CLUSTER:-true}"

if [[ "${START_CLUSTER}" == "true" ]]; then
  "${SCRIPT_DIR}/start_local_cluster.sh"
fi

export COCKROACH_HOST="${COCKROACH_HOST:-127.0.0.1:26257}"

# traces are created under current working directory by default.
"${SCRIPT_DIR}/run_app_trace_case.sh" init-success
"${SCRIPT_DIR}/run_app_trace_case.sh" init-already-initialized
DECOMMISSION_NODES="5" "${SCRIPT_DIR}/run_app_trace_case.sh" decommission-single
DECOMMISSION_NODES="4" "${SCRIPT_DIR}/run_app_trace_case.sh" decommission-custom

if [[ "${STOP_CLUSTER}" == "true" ]]; then
  "${SCRIPT_DIR}/stop_local_cluster.sh"
fi

echo "All app trace cases finished. Check ./traces"
