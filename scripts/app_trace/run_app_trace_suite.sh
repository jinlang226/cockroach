#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Default to repo-local binary produced by `./dev build short`.
export COCKROACH_BIN="${COCKROACH_BIN:-${REPO_ROOT}/cockroach}"

START_CLUSTER="${START_CLUSTER:-true}"
STOP_CLUSTER="${STOP_CLUSTER:-true}"
CLUSTER_DIR="${APP_TRACE_CLUSTER_DIR:-$(pwd)/_app_trace_cluster}"
CLUSTER_ENV="${CLUSTER_DIR}/cluster.env"

if [[ "${START_CLUSTER}" == "true" ]]; then
  # Skip the built-in init so init-success can perform the first cockroach init.
  SKIP_INIT=true "${SCRIPT_DIR}/start_local_cluster.sh"
fi

if [[ -f "${CLUSTER_ENV}" ]]; then
  # shellcheck disable=SC1090
  source "${CLUSTER_ENV}"
fi

export COCKROACH_HOST="${COCKROACH_HOST:-127.0.0.1:26257}"

# Traces are created under current working directory by default.
"${SCRIPT_DIR}/run_app_trace_case.sh" init-success
"${SCRIPT_DIR}/run_app_trace_case.sh" init-already-initialized

# Wait for all nodes to register and replicate before running decommission.
echo "Waiting for all nodes to be live..."
for attempt in $(seq 1 60); do
  live_nodes=$("${COCKROACH_BIN}" node status --insecure --host="${COCKROACH_HOST}" --format=csv 2>/dev/null \
    | awk -F, 'NR>1 && $9=="true" {count++} END {print count+0}') || live_nodes=0
  if [[ "${live_nodes}" -ge "${APP_TRACE_NODE_COUNT:-5}" ]]; then
    echo "All ${live_nodes} nodes are live."
    break
  fi
  if [[ "${attempt}" -eq 60 ]]; then
    echo "Timed out waiting for nodes. Proceeding anyway (live: ${live_nodes})."
  fi
  sleep 2
done

DECOMMISSION_NODES="5" "${SCRIPT_DIR}/run_app_trace_case.sh" decommission-single

# After draining node 5, stores on the remaining nodes can be temporarily throttled
# (marked suspect) while they absorb the moved replicas. Wait for the cluster to
# settle before decommissioning the second node.
echo "Waiting 90s for stores to un-throttle after decommission-single..."
sleep 90

DECOMMISSION_NODES="4" "${SCRIPT_DIR}/run_app_trace_case.sh" decommission-custom

if [[ "${STOP_CLUSTER}" == "true" ]]; then
  "${SCRIPT_DIR}/stop_local_cluster.sh"
fi

echo "All app trace cases finished. Check ./traces"
