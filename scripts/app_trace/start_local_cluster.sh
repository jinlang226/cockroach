#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DEFAULT_COCKROACH_BIN="${REPO_ROOT}/cockroach"
COCKROACH_BIN="${COCKROACH_BIN:-${DEFAULT_COCKROACH_BIN}}"

if [[ ! -x "${COCKROACH_BIN}" ]]; then
  echo "Cockroach binary not found (or not executable): ${COCKROACH_BIN}"
  echo "Build your local source binary first:"
  echo "  cd ${REPO_ROOT}"
  echo "  ./dev build short"
  echo "Then rerun this script, or set COCKROACH_BIN explicitly."
  exit 1
fi

CLUSTER_DIR="${APP_TRACE_CLUSTER_DIR:-$(pwd)/_app_trace_cluster}"
NODE_COUNT="${APP_TRACE_NODE_COUNT:-5}"
BASE_SQL_PORT="${APP_TRACE_BASE_SQL_PORT:-26257}"
BASE_HTTP_PORT="${APP_TRACE_BASE_HTTP_PORT:-8081}"
RESET_CLUSTER_DIR="${RESET_CLUSTER_DIR:-true}"

if [[ "${RESET_CLUSTER_DIR}" == "true" ]]; then
  rm -rf "${CLUSTER_DIR}"
fi
mkdir -p "${CLUSTER_DIR}"

join_addrs=""
for ((i=0; i<NODE_COUNT; i++)); do
  sql_port=$((BASE_SQL_PORT + i))
  addr="127.0.0.1:${sql_port}"
  if [[ -z "${join_addrs}" ]]; then
    join_addrs="${addr}"
  else
    join_addrs="${join_addrs},${addr}"
  fi
done

echo "Starting ${NODE_COUNT} Cockroach nodes in ${CLUSTER_DIR}"
for ((i=0; i<NODE_COUNT; i++)); do
  node_idx=$((i + 1))
  sql_port=$((BASE_SQL_PORT + i))
  http_port=$((BASE_HTTP_PORT + i))
  node_dir="${CLUSTER_DIR}/node${node_idx}"
  mkdir -p "${node_dir}"

  "${COCKROACH_BIN}" start \
    --insecure \
    --store="${node_dir}" \
    --listen-addr="127.0.0.1:${sql_port}" \
    --advertise-addr="127.0.0.1:${sql_port}" \
    --http-addr="127.0.0.1:${http_port}" \
    --join="${join_addrs}" \
    --background \
    --pid-file="${node_dir}/cockroach.pid"
done

sleep 3

set +e
"${COCKROACH_BIN}" init --insecure --host="127.0.0.1:${BASE_SQL_PORT}"
init_rc=$?
set -e

if [[ ${init_rc} -ne 0 ]]; then
  echo "init returned non-zero (cluster may already be initialized); continuing"
fi

echo "Cluster is up."
echo "SQL endpoint: 127.0.0.1:${BASE_SQL_PORT}"
echo "To stop cluster: scripts/app_trace/stop_local_cluster.sh"
